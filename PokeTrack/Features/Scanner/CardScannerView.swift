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
                    CardScannerReticle()
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
            viewModel.stopSession()
        }
        .onChange(of: viewModel.capturedImage) { _, new in
            if new == nil { showPossibleMatches = false }
        }
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
    var body: some View {
        GeometryReader { geo in
            let cardW = geo.size.width * 0.82
            let cardH = cardW * 1.395  // standard Pokémon card aspect ratio
            let y = (geo.size.height - cardH) / 2 - 20  // slightly above center

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
                                    .position(x: geo.size.width / 2, y: y + cardH / 2)
                                    .blendMode(.destinationOut)
                            )
                            .compositingGroup()
                    )

                // Corner brackets
                CornerBrackets(width: cardW, height: cardH)
                    .position(x: geo.size.width / 2, y: y + cardH / 2)
            }
        }
        .ignoresSafeArea()
    }
}

private struct CornerBrackets: View {
    let width: CGFloat
    let height: CGFloat
    private let len: CGFloat = 24
    private let thickness: CGFloat = 3
    private let radius: CGFloat = 10

    var body: some View {
        ZStack {
            ForEach([
                CGPoint(x: -width/2, y: -height/2),
                CGPoint(x:  width/2, y: -height/2),
                CGPoint(x: -width/2, y:  height/2),
                CGPoint(x:  width/2, y:  height/2)
            ], id: \.x) { corner in
                BracketCorner(len: len, thickness: thickness, radius: radius)
                    .rotationEffect(.degrees(rotationFor(corner: corner, w: width, h: height)))
                    .offset(x: corner.x, y: corner.y)
            }
        }
    }

    private func rotationFor(corner: CGPoint, w: CGFloat, h: CGFloat) -> Double {
        switch (corner.x < 0, corner.y < 0) {
        case (true,  true):  return 0
        case (false, true):  return 90
        case (false, false): return 180
        case (true,  false): return 270
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
