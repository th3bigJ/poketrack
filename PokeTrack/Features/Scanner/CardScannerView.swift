import SwiftUI
import AVFoundation

struct CardScannerView: View {
    @Environment(AppServices.self) private var services
    var onMatch: (Card) -> Void
    var onDismiss: () -> Void

    @State private var viewModel = CardScannerViewModel()
    @State private var permissionDenied = false

    // Result bar state
    @State private var currentResultIndex = 0
    /// Swipe up / Details expands the bar in-place (catalog art + pricing); not a separate sheet.
    @State private var isResultBarExpanded = false
    @State private var barDragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let expanded = isResultBarExpanded
            let cameraHeight = expanded ? 0 : geo.size.height * (2.0 / 3.0)
            let resultsHeight = expanded ? geo.size.height : geo.size.height * (1.0 / 3.0)

            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    // Camera + reticle: top 2/3 when collapsed; hidden when results are expanded full screen.
                    ZStack(alignment: .top) {
                        CameraPreviewView(session: viewModel.session)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        if case .idle = viewModel.scanState {
                            CardScannerReticle(
                                frameQuality: viewModel.frameQuality,
                                isCapturing: viewModel.isCapturing
                            ) { rect in
                                viewModel.cardNormalizedRect = rect
                            }
                        } else if case .scanning = viewModel.scanState {
                            CardScannerReticle(
                                frameQuality: viewModel.frameQuality,
                                isCapturing: true
                            ) { rect in
                                viewModel.cardNormalizedRect = rect
                            }
                        }

                        // Undo — same card-frame geometry as `CardScannerReticle` (below the reticle).
                        if !viewModel.scanResults.isEmpty, cameraHeight > 0 {
                            ScannerUndoBelowFrameButton {
                                HapticManager.impact(.light)
                                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                                    viewModel.undoLastScan()
                                    if currentResultIndex > 0 {
                                        currentResultIndex -= 1
                                    }
                                    isResultBarExpanded = false
                                }
                            }
                        }

                        // Error toast — anchored to bottom of camera strip
                        if let err = viewModel.lastErrorMessage {
                            VStack {
                                Spacer()
                                Text(err)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .padding(.horizontal, 24)
                                    .padding(.bottom, 16)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                        }
                    }
                    .frame(height: cameraHeight)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .background(Color.black)
                    .animation(.spring(response: 0.42, dampingFraction: 0.88), value: expanded)

                    // Results: bottom 1/3 when collapsed; full screen when expanded — same black base as camera.
                    ZStack {
                        Color.black
                        if !viewModel.scanResults.isEmpty {
                            resultBar(geo: geo, resultsRegionHeight: resultsHeight)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                    .frame(height: resultsHeight)
                    .frame(maxWidth: .infinity)
                    .animation(.spring(response: 0.42, dampingFraction: 0.88), value: expanded)
                }
                .ignoresSafeArea(edges: .top)

                // Close (and scanning pill) stay reachable when results cover the camera (expanded).
                scannerTopChrome
                    .padding(.top, geo.safeAreaInsets.top)

                if permissionDenied { permissionDeniedOverlay }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onAppear {
            viewModel.configure(cardDataService: services.cardData)
            viewModel.onMatch = { _ in
                HapticManager.impact(.medium)
                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                    currentResultIndex = 0  // newest is always first
                    isResultBarExpanded = false
                }
            }
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
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: viewModel.scanResults.count)
        .animation(.easeOut(duration: 0.2), value: viewModel.lastErrorMessage)
    }

    // MARK: - Top chrome (scanning, dismiss)

    @ViewBuilder
    private var scannerTopChrome: some View {
        VStack {
            HStack {
                if case .scanning = viewModel.scanState {
                    Color.clear.frame(width: 44, height: 1)
                    Spacer()
                    HStack(spacing: 6) {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.8)
                        Text("Identifying…")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    Spacer()
                } else {
                    Spacer(minLength: 0)
                }

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.white, .black.opacity(0.5))
                        .padding(20)
                }
            }
            Spacer()
        }
    }

    // MARK: - Result bar with swipe left/right

    @ViewBuilder
    private func resultBar(geo: GeometryProxy, resultsRegionHeight: CGFloat) -> some View {
        let results = viewModel.scanResults
        let count = results.count
        let expandedMaxH: CGFloat = {
            if isResultBarExpanded {
                return max(280, geo.size.height - geo.safeAreaInsets.top - geo.safeAreaInsets.bottom - 210)
            }
            return max(160, min(geo.size.height * 0.42, resultsRegionHeight * 0.72))
        }()
        let sideInset: CGFloat = 16
        let usableWidth = geo.size.width - geo.safeAreaInsets.leading - geo.safeAreaInsets.trailing
        let barWidth = min(420, usableWidth - sideInset * 2)

        // No outer ScrollView — it prevented horizontal paging. Inner `ScanResultBar` scrolls when expanded.
        VStack(spacing: 8) {
            ZStack {
                ForEach(Array(results.enumerated()), id: \.element.id) { i, result in
                    let offset = CGFloat(i - currentResultIndex) * (barWidth + 12) + barDragOffset
                    ScanResultBar(
                        result: result,
                        isCurrentPage: i == currentResultIndex,
                        isExpanded: $isResultBarExpanded,
                        maxExpandedContentHeight: expandedMaxH,
                        onPickAlternative: { picked in
                            viewModel.replaceScanResult(id: result.id, with: picked)
                        }
                    )
                    .frame(width: barWidth)
                    .offset(x: offset)
                    .scaleEffect(i == currentResultIndex ? 1.0 : 0.95)
                    .opacity(abs(i - currentResultIndex) <= 1 ? (i == currentResultIndex ? 1 : 0.6) : 0)
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: currentResultIndex)
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: barDragOffset)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(width: barWidth)
            .contentShape(Rectangle())
            // Horizontal paging must not lose to child vertical drags — use simultaneous + axis checks on both sides.
            .simultaneousGesture(
                DragGesture(minimumDistance: 18)
                    .onChanged { value in
                        guard abs(value.translation.width) > abs(value.translation.height) + 4 else { return }
                        barDragOffset = value.translation.width
                    }
                    .onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) + 4 else {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { barDragOffset = 0 }
                            return
                        }
                        let threshold: CGFloat = 60
                        let velocity = value.predictedEndTranslation.width
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            if (value.translation.width < -threshold || velocity < -200) && currentResultIndex < count - 1 {
                                currentResultIndex += 1
                                HapticManager.selection()
                            } else if (value.translation.width > threshold || velocity > 200) && currentResultIndex > 0 {
                                currentResultIndex -= 1
                                HapticManager.selection()
                            }
                            barDragOffset = 0
                        }
                    }
            )

            if count > 1 {
                HStack(spacing: 5) {
                    ForEach(0..<count, id: \.self) { i in
                        Circle()
                            .fill(i == currentResultIndex ? Color.white : Color.white.opacity(0.35))
                            .frame(width: i == currentResultIndex ? 6 : 4,
                                   height: i == currentResultIndex ? 6 : 4)
                            .animation(.spring(response: 0.2), value: currentResultIndex)
                    }
                }
                .padding(.bottom, 2)
                .allowsHitTesting(!isResultBarExpanded)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, isResultBarExpanded ? geo.safeAreaInsets.top + 52 : 8)
        .padding(.bottom, 12 + geo.safeAreaInsets.bottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Permission overlay

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

// MARK: - Undo below reticle

/// Placed under the card frame using the same layout as `CardScannerReticle`.
private struct ScannerUndoBelowFrameButton: View {
    var action: () -> Void

    var body: some View {
        GeometryReader { geo in
            let cardW = geo.size.width * 0.72
            let cardH = cardW * 1.395
            let cardY = (geo.size.height - cardH) / 2 - 20
            let belowFrameTop = cardY + cardH + 28

            VStack(spacing: 0) {
                Spacer()
                    .frame(height: belowFrameTop)
                Button(action: action) {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Undo last scan")
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .allowsHitTesting(true)
    }
}

// MARK: - Reticle

private struct CardScannerReticle: View {
    /// Matches `CardScannerViewModel` auto-capture: `frameQuality >= good` shows green / “Hold steady”.
    private static let qualityGood: Double = 0.45
    private static let qualityWarming: Double = 0.2

    var frameQuality: Double
    var isCapturing: Bool
    var onRectChanged: (CGRect) -> Void

    var body: some View {
        GeometryReader { geo in
            let cardW = geo.size.width * 0.72
            let cardH = cardW * 1.395
            let cardX = geo.size.width / 2
            let cardY = (geo.size.height - cardH) / 2 - 20
            let cardCenterY = cardY + cardH / 2

            ZStack {
                // Dimmed surround (scoped to camera region only)
                Color.black.opacity(0.45)
                    .mask(
                        Rectangle()
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .frame(width: cardW, height: cardH)
                                    .position(x: cardX, y: cardCenterY)
                                    .blendMode(.destinationOut)
                            )
                            .compositingGroup()
                    )

                // Quality-tinted continuous border (no corner brackets)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isCapturing ? 2.5 : 2)
                    .frame(width: cardW, height: cardH)
                    .position(x: cardX, y: cardCenterY)
                    .animation(.easeInOut(duration: 0.25), value: frameQuality)

                // Quality label at bottom of reticle
                VStack {
                    Spacer()
                        .frame(height: cardCenterY + cardH / 2 + 12)
                    qualityLabel
                        .position(x: cardX, y: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .onAppear { reportNormalizedReticleRect(geo: geo, cardX: cardX, cardY: cardY, cardW: cardW, cardH: cardH) }
            .onChange(of: geo.size) { _, _ in
                reportNormalizedReticleRect(geo: geo, cardX: cardX, cardY: cardY, cardW: cardW, cardH: cardH)
            }
        }
    }

    private func reportNormalizedReticleRect(geo: GeometryProxy, cardX: CGFloat, cardY: CGFloat, cardW: CGFloat, cardH: CGFloat) {
        let screenW = geo.size.width
        let screenH = geo.size.height
        guard screenW > 0, screenH > 0 else { return }
        let normRect = CGRect(
            x: (cardX - cardW / 2) / screenW,
            y: cardY / screenH,
            width: cardW / screenW,
            height: cardH / screenH
        )
        onRectChanged(normRect)
    }

    private var borderColor: Color {
        if isCapturing { return .white }
        if frameQuality >= Self.qualityGood { return Color.green }
        if frameQuality >= Self.qualityWarming { return Color.yellow.opacity(0.8) }
        return Color.white.opacity(0.6)
    }

    @ViewBuilder
    private var qualityLabel: some View {
        if isCapturing {
            Label("Capturing…", systemImage: "camera.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
        } else if frameQuality >= Self.qualityGood {
            Label("Hold steady", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
        } else {
            Text("Align card in frame")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.black.opacity(0.3), in: Capsule())
        }
    }
}
