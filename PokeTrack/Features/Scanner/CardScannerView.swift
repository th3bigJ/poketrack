import SwiftUI
import AVFoundation

struct CardScannerView: View {
    @Environment(AppServices.self) private var services
    var onMatch: (Card) -> Void
    var onDismiss: () -> Void

    @State private var viewModel = CardScannerViewModel()
    @State private var permissionDenied = false
    @State private var torchOn = false
    @State private var isInspectorOpen = false

    var body: some View {
        GeometryReader { geo in
            let sideInset: CGFloat = 16
            let usableWidth = geo.size.width - geo.safeAreaInsets.leading - geo.safeAreaInsets.trailing
            let contentWidth = min(380, max(260, usableWidth - sideInset * 2))

            ZStack {
                if viewModel.capturedImage == nil {
                    liveCameraStage
                } else {
                    reviewStage
                }

                VStack {
                    Spacer()
                    HStack {
                        Spacer(minLength: 0)
                        bottomPanel(width: contentWidth)
                        Spacer(minLength: 0)
                    }
                    .padding(.bottom, 6)
                }

                VStack {
                    HStack {
                        if viewModel.capturedImage != nil {
                            Button {
                                isInspectorOpen.toggle()
                            } label: {
                                Image(systemName: isInspectorOpen ? "info.circle.fill" : "info.circle")
                                    .font(.system(size: 28))
                                    .foregroundStyle(.white, .black.opacity(0.5))
                                    .padding(20)
                            }
                        } else {
                            Button {
                                torchOn.toggle()
                                setTorch(torchOn)
                                HapticManager.impact(.light)
                            } label: {
                                Image(systemName: torchOn ? "bolt.fill" : "bolt.slash")
                                    .font(.system(size: 22))
                                    .foregroundStyle(torchOn ? .yellow : .white, .black.opacity(0.5))
                                    .padding(20)
                            }
                        }
                        Spacer()
                        Button(action: onDismiss) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 30))
                                .foregroundStyle(.white, .black.opacity(0.5))
                                .padding(20)
                        }
                    }
                    Spacer()
                }

                if permissionDenied {
                    permissionDeniedOverlay
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onAppear {
            viewModel.configure(cardDataService: services.cardData)
            viewModel.onMatch = onMatch
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            if status == .denied || status == .restricted {
                permissionDenied = true
            } else {
                viewModel.startSession()
            }
        }
        .onDisappear {
            if torchOn { setTorch(false) }
            viewModel.stopSession()
        }
        .onChange(of: viewModel.capturedImage) { _, _ in
            isInspectorOpen = false
        }
    }

    // MARK: - Torch

    private func setTorch(_ on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        try? device.lockForConfiguration()
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
    }

    private var liveCameraStage: some View {
        ZStack {
            CameraPreviewView(session: viewModel.session)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .ignoresSafeArea()

            CardScannerReticle { rect in
                viewModel.cardNormalizedRect = rect
            }
        }
    }

    private var reviewStage: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color.black.opacity(0.92), Color(red: 0.08, green: 0.1, blue: 0.14)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack {
                Spacer(minLength: 56)
                cardPreview
                Spacer(minLength: 240)
            }
            .padding(.horizontal, 20)
        }
    }

    private var cardPreview: some View {
        let preview = viewModel.flattenedCardImage ?? viewModel.croppedCardImage ?? viewModel.capturedImage

        return Group {
            if let image = preview {
                GeometryReader { proxy in
                    let width = min(proxy.size.width, 420)
                    let height = width * 1.395

                    ZStack {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: width, height: height)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                            )

                        if viewModel.reviewStep == .flattened {
                            ScanZoneGuide(width: width, height: height)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(height: min(UIScreen.main.bounds.height * 0.5, 560))
            }
        }
    }

    private func bottomPanel(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            if viewModel.capturedImage == nil {
                scanStatusBar
                liveCaptureControls
            } else {
                if isInspectorOpen {
                    scanStatusBar
                    reviewStepContent
                }
                reviewControls
            }
        }
        .frame(width: width, alignment: .center)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private var reviewStepContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                switch viewModel.reviewStep {
                case .flattened:
                    stepHeader("Step 1 of 3", viewModel.reviewStep.title)
                    stepBody("The app first crops to the reticle, then tries `VNDetectRectanglesRequest` inside that crop and applies perspective correction to flatten the card before OCR.")
                    stepBody(viewModel.detectedCardQuad == nil
                             ? "Rectangle detection did not produce a better quad for this shot, so the OCR image is the cropped card."
                             : "Rectangle detection found a card outline and the corrected image above is the OCR input.")

                case .extractedText:
                    stepHeader("Step 2 of 3", viewModel.reviewStep.title)
                    extractedField("Name", viewModel.debugInfo.extractedName)
                    extractedField("HP", viewModel.debugInfo.extractedHP)
                    extractedField("Set #", viewModel.debugInfo.extractedSetNumber)
                    extractedField("Illustrator", viewModel.debugInfo.extractedIllustrator)
                    extractedField("Center text", viewModel.debugInfo.extractedCenterHint)
                    extractedField("Summary", viewModel.debugInfo.matchedSummary)
                    extractedField("OCR raw", viewModel.debugInfo.rawOCRStrings.joined(separator: "\n"))

                case .matchReview:
                    stepHeader("Step 3 of 3", viewModel.reviewStep.title)
                    stepBody("We build a candidate pool from whichever signals were read: name, HP, set number, illustrator, and center text. Missing fields are simply skipped.")
                    extractedField("Pool query", viewModel.debugInfo.searchQueryUsed)
                    extractedField("Pool path", viewModel.debugInfo.narrowTier)
                    extractedField("How it works", viewModel.debugInfo.determinedOutline)

                    if viewModel.candidateExplanations.isEmpty {
                        extractedField("Results", viewModel.lastErrorMessage ?? "No ranked candidates.")
                    } else {
                        Text("Best candidates")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        ForEach(viewModel.candidateExplanations) { explanation in
                            candidateExplanationRow(
                                explanation,
                                isTop: explanation.id == viewModel.candidateExplanations.first?.id
                            )
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 310)
        .background(.regularMaterial)
    }

    private func stepHeader(_ eyebrow: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
        }
    }

    private func stepBody(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func extractedField(_ label: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
            Text((value?.isEmpty == false ? value : "—") ?? "—")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func candidateExplanationRow(_ explanation: ScannerCandidateExplanation, isTop: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(explanation.card.cardName)
                        .font(.body.weight(.semibold))
                    Text("\(explanation.card.setCode.uppercased()) · #\(explanation.card.cardNumber)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isTop {
                    Text("Best")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.22))
                        .clipShape(Capsule())
                }
            }

            Text("total \(explanation.totalScore) = name \(explanation.nameScore) + hp \(explanation.hpScore) + center \(explanation.centerScore) + set \(explanation.setScore) + artist \(explanation.artistScore) + ex \(explanation.exScore)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)

            Button {
                viewModel.confirmOpenCard(explanation.card)
            } label: {
                Label("Open this card", systemImage: "rectangle.portrait.and.arrow.forward")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }

    private var reviewControls: some View {
        VStack(spacing: 10) {
            if viewModel.capturedImage != nil {
                HStack(spacing: 8) {
                    Image(systemName: isInspectorOpen ? "info.circle.fill" : "info.circle")
                        .foregroundStyle(.secondary)
                    Text(isInspectorOpen ? "Hide step details" : "Show step details")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(viewModel.reviewStep.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    isInspectorOpen.toggle()
                }
            }

            HStack(spacing: 10) {
                Button {
                    viewModel.goToPreviousReviewStep()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.reviewStep == .flattened)

                if viewModel.reviewStep == .matchReview, case .found(let card) = viewModel.scanState {
                    Button {
                        viewModel.confirmOpenCard(card)
                    } label: {
                        Label("Open best match", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        viewModel.goToNextReviewStep()
                    } label: {
                        Label("Next", systemImage: "chevron.right")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.reviewStep == .matchReview)
                }
            }

            Button {
                viewModel.retake()
            } label: {
                Label("Retake photo", systemImage: "arrow.counterclockwise.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    private var scanStatusBar: some View {
        VStack(spacing: 8) {
            statusLabel
            if let text = viewModel.detectedText {
                Text(text)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(4)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.85)
            }
            if let err = viewModel.lastErrorMessage {
                Text(err)
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 14)
        .background(.ultraThinMaterial)
    }

    private var liveCaptureControls: some View {
        Button {
            viewModel.capturePhoto()
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(.white.opacity(0.9), lineWidth: 4)
                    .frame(width: 72, height: 72)
                Circle()
                    .fill(.white)
                    .frame(width: 58, height: 58)
            }
            .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isCapturing || !viewModel.isCameraReady)
        .opacity(viewModel.isCapturing || !viewModel.isCameraReady ? 0.45 : 1)
        .overlay {
            if viewModel.isCapturing {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.2)
            }
        }
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch viewModel.scanState {
        case .idle:
            Text(
                viewModel.capturedImage == nil
                    ? "Fill the frame, then tap the shutter"
                    : "Review each step below"
            )
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)

        case .scanning:
            HStack(spacing: 8) {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(0.85)
                Text("Processing capture…")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }

        case .found(let card):
            VStack(spacing: 6) {
                HStack(alignment: .center, spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Best match so far: \(card.cardName)")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                Text("Walk through the review steps, then confirm.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var permissionDeniedOverlay: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "camera.slash")
                    .font(.system(size: 48))
                    .foregroundStyle(.white.opacity(0.6))
                Text("Camera access required")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Open Settings and allow camera access for PokeTrack to scan cards.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

// MARK: - Reticle

private struct CardScannerReticle: View {
    var onRectChanged: (CGRect) -> Void

    var body: some View {
        GeometryReader { geo in
            let cardW = geo.size.width * 0.58
            let cardH = cardW * 1.395
            let cardX = geo.size.width / 2
            let cardY = (geo.size.height - cardH) / 2 - 20
            let cardCenterY = cardY + cardH / 2

            ZStack {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .mask(
                        Rectangle()
                            .ignoresSafeArea()
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .frame(width: cardW, height: cardH)
                                    .position(x: cardX, y: cardCenterY)
                                    .blendMode(.destinationOut)
                            )
                            .compositingGroup()
                    )

                CornerBrackets(width: cardW, height: cardH)
                    .position(x: cardX, y: cardCenterY)
            }
            .onAppear {
                let screenW = geo.size.width
                let screenH = geo.size.height
                let normRect = CGRect(
                    x: (cardX - cardW / 2) / screenW,
                    y: cardY / screenH,
                    width: cardW / screenW,
                    height: cardH / screenH
                )
                onRectChanged(normRect)
            }
        }
        .ignoresSafeArea()
    }
}

private struct ScanZoneGuide: View {
    let width: CGFloat
    let height: CGFloat

    private let divider1: CGFloat = 0.20
    private let divider2: CGFloat = 0.50
    private let divider3: CGFloat = 0.85

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { ctx, size in
                let w = size.width
                let h = size.height
                let y1 = h * divider1
                let y2 = h * divider2
                let y3 = h * divider3

                ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: y1)),
                         with: .color(.yellow.opacity(0.08)))
                ctx.fill(Path(CGRect(x: 0, y: y2, width: w, height: y3 - y2)),
                         with: .color(.blue.opacity(0.08)))
                ctx.fill(Path(CGRect(x: 0, y: y3, width: w, height: h - y3)),
                         with: .color(.green.opacity(0.08)))

                let dashStyle = StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                let lineColor = GraphicsContext.Shading.color(.white.opacity(0.55))

                var l1 = Path(); l1.move(to: CGPoint(x: 0, y: y1)); l1.addLine(to: CGPoint(x: w, y: y1))
                ctx.stroke(l1, with: lineColor, style: dashStyle)
                var l2 = Path(); l2.move(to: CGPoint(x: 0, y: y2)); l2.addLine(to: CGPoint(x: w, y: y2))
                ctx.stroke(l2, with: lineColor, style: dashStyle)
                var l3 = Path(); l3.move(to: CGPoint(x: 0, y: y3)); l3.addLine(to: CGPoint(x: w, y: y3))
                ctx.stroke(l3, with: lineColor, style: dashStyle)
            }

            GeometryReader { geo in
                let h = geo.size.height
                let w = geo.size.width
                Group {
                    ZoneLabel(text: "NAME + HP")
                        .position(x: w / 2, y: h * divider1 / 2)
                    ZoneLabel(text: "ATTACKS")
                        .position(x: w / 2, y: h * (divider2 + divider3) / 2)
                    ZoneLabel(text: "CARD #")
                        .position(x: w / 2, y: h * (divider3 + 1.0) / 2)
                }
            }
        }
        .frame(width: width, height: height)
        .allowsHitTesting(false)
    }
}

private struct ZoneLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.6))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 3))
    }
}

private struct CornerBrackets: View {
    let width: CGFloat
    let height: CGFloat
    private let len: CGFloat = 20
    private let thickness: CGFloat = 3
    private let radius: CGFloat = 10

    private struct Corner: Identifiable {
        let id: Int
        let point: CGPoint
        let rotation: Double
    }

    var body: some View {
        let corners = [
            Corner(id: 0, point: CGPoint(x: -width / 2, y: -height / 2), rotation: 0),
            Corner(id: 1, point: CGPoint(x: width / 2, y: -height / 2), rotation: 90),
            Corner(id: 2, point: CGPoint(x: width / 2, y: height / 2), rotation: 180),
            Corner(id: 3, point: CGPoint(x: -width / 2, y: height / 2), rotation: 270),
        ]

        return ZStack {
            ForEach(corners) { corner in
                BracketCorner(len: len, thickness: thickness, radius: radius)
                    .rotationEffect(.degrees(corner.rotation))
                    .offset(x: corner.point.x, y: corner.point.y)
            }
        }
    }
}

private struct BracketCorner: View {
    let len: CGFloat
    let thickness: CGFloat
    let radius: CGFloat

    var body: some View {
        Canvas { ctx, _ in
            var path = Path()
            path.move(to: CGPoint(x: len, y: 0))
            path.addLine(to: CGPoint(x: radius, y: 0))
            path.addQuadCurve(to: CGPoint(x: 0, y: radius), control: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 0, y: len))
            ctx.stroke(path, with: .color(.white), lineWidth: thickness)
        }
        .frame(width: len + thickness, height: len + thickness)
    }
}
