import SwiftUI
import AVFoundation

struct CardScannerView: View {
    @Environment(AppServices.self) private var services
    var onMatch: (Card) -> Void
    var onDismiss: () -> Void

    @State private var viewModel = CardScannerViewModel()
    @State private var permissionDenied = false
    @State private var showDebug = true
    @State private var showPossibleMatches = false
    @State private var torchOn = false

    var body: some View {
        GeometryReader { geo in
            let sideInset: CGFloat = 16
            /// Width inside safe area — avoid clipping when horizontal insets are non-zero.
            let usableWidth = geo.size.width - geo.safeAreaInsets.leading - geo.safeAreaInsets.trailing
            /// Narrow centered column; never wider than usable width minus margins.
            let contentWidth = min(360, max(260, usableWidth - sideInset * 2))

            ZStack {
                // Live preview or frozen capture for OCR
                Group {
                    if let shot = viewModel.capturedImage {
                        Image(uiImage: shot)
                            .resizable()
                            .scaledToFill()
                    } else {
                        CameraPreviewView(session: viewModel.session)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .ignoresSafeArea()

                // Viewfinder guide (live only — still review uses the full frame)
                if viewModel.capturedImage == nil {
                    CardScannerReticle { rect in
                        viewModel.cardNormalizedRect = rect
                    }
                }

                // Debug — only after a still is captured (OCR + extraction exist).
                VStack {
                    if showDebug, viewModel.capturedImage != nil {
                        HStack {
                            Spacer(minLength: 0)
                            debugPanel(width: contentWidth)
                            Spacer(minLength: 0)
                        }
                        .padding(.top, 52)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                // Bottom: status + matches + buttons — strict width, centered (no `.frame(maxWidth: .infinity)` on the column or it expands past the screen).
                VStack {
                    Spacer()
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        VStack(spacing: 0) {
                            scanStatusBar
                            matchReviewSection
                            captureControls
                        }
                        .frame(width: contentWidth, alignment: .center)
                        .layoutPriority(1)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                        )
                        Spacer(minLength: 0)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 6)

                // Top buttons row (ladybug only relevant once there is OCR/debug to show)
                VStack {
                    HStack {
                        if viewModel.capturedImage != nil {
                            Button {
                                showDebug.toggle()
                            } label: {
                                Image(systemName: showDebug ? "ladybug.fill" : "ladybug")
                                    .font(.system(size: 22))
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
        .onChange(of: viewModel.capturedImage) { _, new in
            if new == nil { showPossibleMatches = false }
        }
    }

    // MARK: - Torch

    private func setTorch(_ on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        try? device.lockForConfiguration()
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
    }

    // MARK: - Debug panel

    private func debugPanel(width: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                debugRow("captures", "\(viewModel.debugInfo.captureCount)")

                Text("DETERMINED (read → use)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(red: 1, green: 0.95, blue: 0.4))
                Text(viewModel.debugInfo.determinedOutline.isEmpty ? "—" : viewModel.debugInfo.determinedOutline)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineSpacing(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)

                debugRow("search used", viewModel.debugInfo.searchQueryUsed ?? "—")
                debugRow("tier", viewModel.debugInfo.narrowTier ?? "—")
                debugRow("results", "\(viewModel.debugInfo.searchResultCount)")
                debugRow("top", viewModel.debugInfo.topResult ?? "—")
                debugRow("buffer", viewModel.debugInfo.matchBufferState.isEmpty ? "—" : viewModel.debugInfo.matchBufferState)

                Divider().background(Color.white.opacity(0.35))

                Text("OCR raw (\(viewModel.debugInfo.rawOCRStrings.count) strings):")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(red: 1, green: 0.95, blue: 0.4))
                ForEach(Array(viewModel.debugInfo.rawOCRStrings.prefix(16).enumerated()), id: \.offset) { i, s in
                    Text("[\(i)] \(s)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white)
                        .lineSpacing(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .frame(width: width)
        .frame(maxHeight: 360)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.94))
                .shadow(color: .black.opacity(0.45), radius: 12, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    /// Stacked label + value so narrow columns wrap instead of one long line.
    private func debugRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(red: 1, green: 0.95, blue: 0.4).opacity(0.9))
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white)
                .lineSpacing(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    // MARK: - Status bar

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

    /// Confirmed matches (multi-select list) or hidden alternatives after a failed primary search.
    @ViewBuilder
    private var matchReviewSection: some View {
        if case .found(let primary) = viewModel.scanState, !viewModel.searchResults.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Review match")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                if viewModel.searchResults.count > 1 {
                    Text("Multiple catalog hits — pick the right printing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.searchResults) { card in
                            matchRow(card, isPrimary: card.masterCardId == primary.masterCardId)
                        }
                    }
                }
                .frame(maxHeight: min(220, CGFloat(viewModel.searchResults.count) * 56))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial)
        } else if viewModel.capturedImage != nil,
                  case .idle = viewModel.scanState,
                  !viewModel.alternativeMatches.isEmpty {
            VStack(spacing: 10) {
                Button {
                    showPossibleMatches.toggle()
                } label: {
                    Label(
                        showPossibleMatches
                            ? "Hide possible matches"
                            : "Show possible matches (\(viewModel.alternativeMatches.count))",
                        systemImage: showPossibleMatches ? "chevron.up" : "magnifyingglass"
                    )
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white.opacity(0.28))
                .foregroundStyle(.white)

                if showPossibleMatches {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(viewModel.alternativeMatches) { card in
                                matchRow(card, isPrimary: false)
                            }
                        }
                    }
                    .frame(maxHeight: min(260, CGFloat(viewModel.alternativeMatches.count) * 56))
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 6)
            .background(.regularMaterial)
        }
    }

    private func matchRow(_ card: Card, isPrimary: Bool) -> some View {
        Button {
            viewModel.confirmOpenCard(card)
        } label: {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.cardName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(card.setCode.uppercased()) · #\(card.cardNumber)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                if isPrimary {
                    Text("Top")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.25))
                        .clipShape(Capsule())
                        .layoutPriority(1)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .layoutPriority(1)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
    }

    /// Shutter + retake — still capture first; live continuous scan can return later.
    private var captureControls: some View {
        Group {
            if viewModel.capturedImage != nil {
                VStack(spacing: 10) {
                    if case .found(let card) = viewModel.scanState {
                        Button {
                            viewModel.confirmOpenCard(card)
                            HapticManager.impact(.medium)
                        } label: {
                            Label("Open card", systemImage: "rectangle.portrait.and.arrow.forward")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.accentColor)
                    }
                    Button {
                        viewModel.retake()
                        HapticManager.impact(.light)
                    } label: {
                        Label("Retake photo", systemImage: "arrow.counterclockwise.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white.opacity(0.35))
                    .foregroundStyle(.white)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            } else {
                Button {
                    viewModel.capturePhoto()
                    HapticManager.impact(.medium)
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
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch viewModel.scanState {
        case .idle:
            Text(
                viewModel.capturedImage == nil
                    ? "Fill the frame, then tap the shutter"
                    : (viewModel.lastErrorMessage != nil ? "No match" : "Try Retake")
            )
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
        case .scanning:
            HStack(spacing: 8) {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(0.85)
                Text("Scanning…")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
        case .found(let card):
            VStack(spacing: 6) {
                HStack(alignment: .center, spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Likely match: \(card.cardName)")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                Text("Confirm below before opening.")
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
    /// Called whenever the card frame rect changes; rect is normalized 0–1 within the screen.
    var onRectChanged: (CGRect) -> Void

    var body: some View {
        GeometryReader { geo in
            let cardW = geo.size.width * 0.58
            let cardH = cardW * 1.395  // standard Pokémon card aspect ratio
            let cardX = geo.size.width / 2
            let cardY = (geo.size.height - cardH) / 2 - 20  // slightly above center
            let cardCenterY = cardY + cardH / 2

            ZStack {
                // Dim everything outside the card frame
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

                // OCR zone guide lines
                ScanZoneGuide(width: cardW, height: cardH)
                    .position(x: cardX, y: cardCenterY)

                // Corner brackets
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

/// Overlay showing the 3 OCR scan zones inside the card frame with labels.
/// Matches CardOCRFieldExtractor's spatial bands (Vision Y flipped to view Y).
///   Vision topBandMinY=0.80    → view Y = 1-0.80 = 0.20  (top 20% = name+HP zone)
///   Vision centerBandMaxY=0.50 → view Y = 1-0.50 = 0.50  (divider above attacks)
///   Vision centerBandMinY=0.15 → view Y = 1-0.15 = 0.85  (divider below attacks)
private struct ScanZoneGuide: View {
    let width: CGFloat
    let height: CGFloat

    // Divider positions as fractions from the top of the card frame
    private let divider1: CGFloat = 0.20   // below name+HP zone
    private let divider2: CGFloat = 0.50   // below artwork, above attacks
    private let divider3: CGFloat = 0.85   // above card number strip

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Coloured zone fills
            Canvas { ctx, size in
                let w = size.width
                let h = size.height
                let y1 = h * divider1
                let y2 = h * divider2
                let y3 = h * divider3

                // Name + HP zone — top tint
                ctx.fill(Path(CGRect(x: 0, y: 0,  width: w, height: y1)),
                         with: .color(.yellow.opacity(0.08)))
                // Attacks zone — middle tint
                ctx.fill(Path(CGRect(x: 0, y: y2, width: w, height: y3 - y2)),
                         with: .color(.blue.opacity(0.08)))
                // Card number zone — bottom tint
                ctx.fill(Path(CGRect(x: 0, y: y3, width: w, height: h - y3)),
                         with: .color(.green.opacity(0.08)))

                // Divider lines
                let dashStyle = StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                let lineColor = GraphicsContext.Shading.color(.white.opacity(0.55))

                var l1 = Path(); l1.move(to: CGPoint(x: 0, y: y1)); l1.addLine(to: CGPoint(x: w, y: y1))
                ctx.stroke(l1, with: lineColor, style: dashStyle)
                var l2 = Path(); l2.move(to: CGPoint(x: 0, y: y2)); l2.addLine(to: CGPoint(x: w, y: y2))
                ctx.stroke(l2, with: lineColor, style: dashStyle)
                var l3 = Path(); l3.move(to: CGPoint(x: 0, y: y3)); l3.addLine(to: CGPoint(x: w, y: y3))
                ctx.stroke(l3, with: lineColor, style: dashStyle)
            }

            // Zone labels
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
            Corner(id: 0, point: CGPoint(x: -width/2, y: -height/2), rotation: 0),
            Corner(id: 1, point: CGPoint(x:  width/2, y: -height/2), rotation: 90),
            Corner(id: 2, point: CGPoint(x:  width/2, y:  height/2), rotation: 180),
            Corner(id: 3, point: CGPoint(x: -width/2, y:  height/2), rotation: 270),
        ]
        ZStack {
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
            path.addQuadCurve(to: CGPoint(x: 0, y: radius),
                              control: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 0, y: len))
            ctx.stroke(path, with: .color(.white), lineWidth: thickness)
        }
        .frame(width: len + thickness, height: len + thickness)
    }
}
