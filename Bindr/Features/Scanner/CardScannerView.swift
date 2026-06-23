import SwiftUI
import AVFoundation

private enum ScannerCardFrameLayout {
    static let verticalCenterBias: CGFloat = 8
    /// Stable content height for the controls/results area below the camera.
    static let bottomPanelContentHeight: CGFloat = 300
    static let bottomSheetTopCornerRadius: CGFloat = 28
    /// Top inset for the bottom sheet drag handle (capture button sits fully in the camera area).
    static let sheetTopContentInset: CGFloat = 16
    /// Gap between the bottom of the capture button and the top edge of the bottom sheet.
    static let captureButtonBottomGap: CGFloat = 28
    /// Keeps the preview usable when the scanner is presented on a compact-height device.
    static let minimumCameraContentHeight: CGFloat = 360
    /// Alignment frame width as a fraction of preview width. Slightly smaller than full-card fill helps autofocus lock on the subject.
    static let reticleWidthFraction: CGFloat = 0.52
    /// Pokémon TCG–style aspect (tall card).
    static let cardAspectHeightOverWidth: CGFloat = 1.395
}

enum CardScannerPurpose {
    case collection
    case trade(onAdd: ([NewTradeItemInput]) -> Void)
}

struct CardScannerView: View {
    @Environment(AppServices.self) private var services
    var purpose: CardScannerPurpose = .collection
    var onMatch: (Card) -> Void
    var onDismiss: () -> Void

    @State private var viewModel = CardScannerViewModel()
    @State private var permissionDenied = false

    @State private var currentResultIndex = 0
    @State private var barDragOffset: CGFloat = 0
    @State private var showDetailSheet = false
    @State private var showBulkAddSheet = false
    @State private var isCameraPaused = false
    @State private var wasCameraPausedBeforeDetail = false
    /// Variant selected in the overlay bar at the moment the user swiped up, keyed by ScanResult.id.
    @State private var selectedVariantsByResultID: [UUID: String] = [:]
    /// Quantity selected per variant for each scanned card (resultID -> variantKey -> qty).
    @State private var selectedVariantQuantitiesByResultID: [UUID: [String: Int]] = [:]
    @State private var showScanLimitPaywall = false
    @State private var showQuantityWarning = false

    private var canTriggerCapture: Bool {
        guard !permissionDenied, !isCameraPaused, !viewModel.isCapturing, viewModel.isCameraReady else { return false }
        if case .scanning = viewModel.scanState { return false }
        return true
    }

    private var canAddCurrentScannedCard: Bool {
        guard viewModel.scanResults.indices.contains(currentResultIndex) else { return false }
        let resultID = viewModel.scanResults[currentResultIndex].id
        let quantities = selectedVariantQuantitiesByResultID[resultID] ?? [:]
        return quantities.values.contains(where: { $0 > 0 })
    }

    private var addActionTitle: String {
        switch purpose {
        case .collection: return "Add to collection"
        case .trade: return "Add to trade"
        }
    }

    var body: some View {
        GeometryReader { geo in
            let preferredBottomPanelHeight =
                ScannerCardFrameLayout.bottomPanelContentHeight + geo.safeAreaInsets.bottom
            let minimumCameraHeight =
                ScannerCardFrameLayout.minimumCameraContentHeight + geo.safeAreaInsets.top
            let availableBottomPanelHeight = max(0, geo.size.height - minimumCameraHeight)
            let bottomPanelHeight = min(preferredBottomPanelHeight, availableBottomPanelHeight)
            let cameraHeight = geo.size.height - bottomPanelHeight

            VStack(spacing: 0) {
                // Camera preview + reticle. The remaining height is reserved for the safe-area-aware bottom panel.
                ZStack(alignment: .top) {
                    CameraPreviewView(session: viewModel.session)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    LinearGradient(
                        colors: [
                            .black.opacity(0.58),
                            .black.opacity(0.18),
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 170)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(false)

                    if case .idle = viewModel.scanState {
                        CardScannerReticle(
                            alignmentTier: viewModel.alignmentTier,
                            isCapturing: viewModel.isCapturing,
                            showsAlignmentLabel: false
                        ) { rect in
                            viewModel.cardNormalizedRect = rect
                        }
                    } else if case .scanning = viewModel.scanState {
                        CardScannerReticle(
                            alignmentTier: viewModel.alignmentTier,
                            isCapturing: false,
                            showsAlignmentLabel: false
                        ) { rect in
                            viewModel.cardNormalizedRect = rect
                        }
                    }

                    if !viewModel.scanResults.isEmpty {
                        ScannerUndoBelowFrameButton {
                            HapticManager.impact(.light)
                            viewModel.undoLastScan()
                            if currentResultIndex > 0 { currentResultIndex -= 1 }
                        }
                    }

                    scannerScanningOverlay(geo: geo)

                    ScannerTopStatusPill(
                        brand: viewModel.scanBrand.displayTitle,
                        scannedCount: viewModel.scanResults.count,
                        isReady: viewModel.isCameraReady,
                        alignmentTier: viewModel.alignmentTier
                    )
                    .padding(.top, ScannerSheetLayout.statusBarHeight + 8)
                    .padding(.leading, 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .allowsHitTesting(false)

                    if permissionDenied { permissionDeniedOverlay }

                    VStack {
                        if showQuantityWarning {
                            Label("Add at least 1 card before scanning the next", systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color.orange.opacity(0.88), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .padding(.horizontal, 24)
                                .padding(.top, ScannerSheetLayout.statusBarHeight + 48)
                                .transition(.move(edge: .top).combined(with: .opacity))
                                .onAppear {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                        withAnimation { showQuantityWarning = false }
                                    }
                                }
                        } else if let err = viewModel.lastErrorMessage {
                            Button {
                                if viewModel.hasReachedScanLimit { showScanLimitPaywall = true }
                            } label: {
                                Text(err)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .padding(.horizontal, 24)
                                    .padding(.top, ScannerSheetLayout.statusBarHeight + 48)
                            }
                            .buttonStyle(.plain)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        Spacer(minLength: 0)
                    }
                    .allowsHitTesting(!permissionDenied)

                    // Value scanned label — bottom-leading of camera area
                    if !viewModel.scanResults.isEmpty {
                        ScannerValueLabel(
                            results: viewModel.scanResults,
                            selectedVariantsByResultID: selectedVariantsByResultID,
                            selectedVariantQuantitiesByResultID: selectedVariantQuantitiesByResultID
                        )
                        .transition(AnyTransition.opacity.combined(with: AnyTransition.move(edge: .bottom)))
                    }

                    // Bottom-trailing controls
                    VStack {
                        Spacer(minLength: 0)
                        HStack {
                            Spacer(minLength: 0)
                            HStack(spacing: 12) {
                                if !viewModel.scanResults.isEmpty {
                                    Button {
                                        guard canAddCurrentScannedCard else { return }
                                        showBulkAddSheet = true
                                        HapticManager.impact(.medium)
                                    } label: {
                                        Text(addActionTitle)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 9)
                                            .background(services.theme.accentColor, in: Capsule())
                                            .overlay(
                                                Capsule()
                                                    .strokeBorder(services.theme.accentColor.opacity(0.4), lineWidth: 1)
                                            )
                                            .opacity(canAddCurrentScannedCard ? 1 : 0.5)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(!canAddCurrentScannedCard)
                                    .accessibilityLabel(addActionTitle)
                                }
                            }
                            .padding(.trailing, 16)
                            .padding(.bottom, 14)
                        }
                    }
                    .allowsHitTesting(!permissionDenied)
                }
                .frame(maxWidth: .infinity)
                .frame(height: cameraHeight)
                .clipped()

                // Bottom sheet — idle instructions or scan results
                ZStack {
                    ScannerDockBackground(accentColor: services.theme.chartAccentColor)

                    if viewModel.scanResults.isEmpty {
                        ScannerIdleInstructions()
                            .transition(AnyTransition.opacity)
                    } else {
                        ScannerResultsOverlay(
                            results: viewModel.scanResults,
                            currentResultIndex: $currentResultIndex,
                            barDragOffset: $barDragOffset,
                            selectedVariantsByResultID: $selectedVariantsByResultID,
                            selectedVariantQuantitiesByResultID: $selectedVariantQuantitiesByResultID,
                            onOpenDetails: { showDetailSheet = true },
                            onDeleteResult: { id in
                                viewModel.removeScanResult(id: id)
                                selectedVariantsByResultID[id] = nil
                                selectedVariantQuantitiesByResultID[id] = nil
                                let count = viewModel.scanResults.count
                                if count == 0 {
                                    currentResultIndex = 0
                                } else {
                                    currentResultIndex = min(currentResultIndex, count - 1)
                                }
                            },
                            onPickAlternative: { id, picked in
                                viewModel.replaceScanResult(id: id, with: picked)
                            }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(maxHeight: .infinity)
                .clipShape(
                    UnevenRoundedRectangle(
                        cornerRadii: RectangleCornerRadii(
                            topLeading: ScannerCardFrameLayout.bottomSheetTopCornerRadius,
                            bottomLeading: 0,
                            bottomTrailing: 0,
                            topTrailing: ScannerCardFrameLayout.bottomSheetTopCornerRadius
                        ),
                        style: .continuous
                    )
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                if !permissionDenied {
                    ScannerCaptureButton(
                        canCapture: canTriggerCapture,
                        accentColor: services.theme.accentColor
                    ) {
                        guard canTriggerCapture else { return }
                        viewModel.capturePhoto()
                        HapticManager.impact(.medium)
                    }
                    .padding(.bottom, bottomPanelHeight + ScannerCardFrameLayout.captureButtonBottomGap)
                    .allowsHitTesting(!permissionDenied)
                }
            }
            .ignoresSafeArea()
            .overlay(alignment: .topTrailing) {
                if case .scanning = viewModel.scanState {
                    EmptyView()
                } else {
                    ChromeGlassCircleButton(accessibilityLabel: "Close scanner", action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .environment(\.colorScheme, .dark)
                    .padding(.top, ScannerSheetLayout.statusBarHeight + 8)
                    .padding(.trailing, 16)
                }
            }
            .sheet(isPresented: $showDetailSheet, onDismiss: {
                if wasCameraPausedBeforeDetail {
                    isCameraPaused = true
                } else {
                    isCameraPaused = false
                    viewModel.startSession()
                }
            }) {
                ScannerDetailSheet(
                    results: viewModel.scanResults,
                    currentResultIndex: $currentResultIndex,
                    selectedVariantsByResultID: selectedVariantsByResultID,
                    onPickAlternative: { id, picked in
                        viewModel.replaceScanResult(id: id, with: picked)
                    }
                )
                .environment(services)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(20)
            }
            .onChange(of: showDetailSheet) { _, isShowing in
                if isShowing {
                    wasCameraPausedBeforeDetail = isCameraPaused
                    isCameraPaused = true
                    viewModel.stopSession()
                }
            }
            .onChange(of: showBulkAddSheet) { _, isShowing in
                if isShowing { viewModel.stopSession() }
            }
            .sheet(isPresented: $showBulkAddSheet, onDismiss: {
                if !isCameraPaused { viewModel.startSession() }
            }) {
                ScannerBulkAddSheet(
                    results: viewModel.scanResults,
                    selectedVariantsByResultID: $selectedVariantsByResultID,
                    selectedVariantQuantitiesByResultID: $selectedVariantQuantitiesByResultID,
                    purpose: purpose,
                    onSuccessClearSession: {
                        viewModel.clearAllScanResults()
                        selectedVariantsByResultID = [:]
                        selectedVariantQuantitiesByResultID = [:]
                        currentResultIndex = 0
                    },
                    onTradeAddComplete: {
                        if case .trade = purpose {
                            onDismiss()
                        }
                    }
                )
                .environment(services)
                .bindrTheme(accent: services.theme.accentColor)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(24)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            viewModel.configure(cardDataService: services.cardData, storeService: services.store)
            let selectedBrand = services.brandSettings.selectedCatalogBrand
            viewModel.scanBrand = selectedBrand
            viewModel.requiresBrandSelection = false
            viewModel.onMatch = { result in
                let defaultVariant = result.card.pricingVariants?.first ?? "normal"
                selectedVariantsByResultID[result.id] = defaultVariant
                selectedVariantQuantitiesByResultID[result.id] = [defaultVariant: 1]
                HapticManager.impact(.medium)
                currentResultIndex = 0
            }
            viewModel.captureBlocker = {
                guard !viewModel.scanResults.isEmpty else { return false }
                let resultID = viewModel.scanResults[0].id
                let quantities = selectedVariantQuantitiesByResultID[resultID] ?? [:]
                return !quantities.values.contains(where: { $0 > 0 })
            }
            viewModel.onCaptureBlocked = {
                HapticManager.notification(.warning)
                withAnimation { showQuantityWarning = true }
            }
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            if status == .denied || status == .restricted {
                permissionDenied = true
            } else {
                viewModel.startSession()
            }
        }
        .onChange(of: selectedVariantQuantitiesByResultID) { _, _ in
            if showQuantityWarning, viewModel.captureBlocker?() == false {
                withAnimation { showQuantityWarning = false }
            }
        }
        .onDisappear { viewModel.stopSession() }
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: viewModel.scanResults.isEmpty)
        .animation(.easeOut(duration: 0.2), value: viewModel.lastErrorMessage)
        .sheet(isPresented: $showScanLimitPaywall) {
            PaywallSheet().environment(services)
        }
        .background(Color.black.ignoresSafeArea())
        .interactiveDismissDisabled(true)
    }

    @ViewBuilder
    private func scannerScanningOverlay(geo: GeometryProxy) -> some View {
        if case .scanning = viewModel.scanState {
            let cardW = geo.size.width * ScannerCardFrameLayout.reticleWidthFraction
            let cardH = cardW * ScannerCardFrameLayout.cardAspectHeightOverWidth
            let cardCenterY = ((geo.size.height - cardH) / 2 - ScannerCardFrameLayout.verticalCenterBias) + (cardH / 2)

            ZStack {
                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        ProgressView().tint(.white).scaleEffect(0.8)
                        Text("Scanning…")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.thinMaterial, in: Capsule())

                    Button {
                        viewModel.cancelCurrentScan()
                        HapticManager.impact(.light)
                    } label: {
                        Text("Cancel")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(.black.opacity(0.35), in: Capsule())
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel scanning")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.black.opacity(0.28), in: Capsule())
                .position(x: geo.size.width / 2, y: cardCenterY)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(true)
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
                    .font(.headline).foregroundStyle(.white)
                Text("Open Settings and allow camera access for Bindr to scan cards.")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center).padding(.horizontal, 32)
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

// MARK: - Layout constants

enum ScannerSheetLayout {
    static var statusBarHeight: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.top ?? 54
    }
    static let deviceCornerRadius: CGFloat = (UIScreen.main.value(forKey: "displayCornerRadius") as? CGFloat) ?? 44
}

// MARK: - Scanner chrome

private struct ScannerTopStatusPill: View {
    let brand: String
    let scannedCount: Int
    let isReady: Bool
    let alignmentTier: ScannerAlignmentTier

    private var statusText: String {
        if !isReady { return "Warming camera" }
        switch alignmentTier {
        case .ready: return "Ready to scan"
        case .holdSteady: return "Hold steady"
        case .align: return "Align card"
        }
    }

    private var statusColor: Color {
        if !isReady { return .orange }
        switch alignmentTier {
        case .ready: return .green
        case .holdSteady: return .yellow
        case .align: return .white.opacity(0.72)
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.18))
                    .frame(width: 34, height: 34)
                Image(systemName: isReady ? "viewfinder.circle.fill" : "camera.metering.unknown")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(statusColor)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(statusText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(scannedCount == 0 ? brand : "\(scannedCount) scanned")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.62))
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 13)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: 16, y: 8)
        .animation(.easeInOut(duration: 0.35), value: alignmentTier)
    }
}

private struct ScannerDockBackground: View {
    let accentColor: Color

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)

            Color(red: 0.055, green: 0.055, blue: 0.075)
                .opacity(0.90)

            LinearGradient(
                colors: [
                    accentColor.opacity(0.18),
                    accentColor.opacity(0.07),
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottomTrailing
            )

            LinearGradient(
                colors: [
                    Color.white.opacity(0.10),
                    Color.white.opacity(0.025),
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            accentColor.opacity(0.46),
                            Color.white.opacity(0.16),
                            accentColor.opacity(0.10)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
                .opacity(0.7)
        }
        .shadow(color: accentColor.opacity(0.16), radius: 22, y: -8)
        .ignoresSafeArea(edges: .bottom)
        .allowsHitTesting(false)
    }
}

// MARK: - Capture button

private struct ScannerCaptureButton: View {
    let canCapture: Bool
    let accentColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(Color.white.opacity(canCapture ? 0.20 : 0.08), lineWidth: 4)
                    .frame(width: 80, height: 80)

                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(canCapture ? 0.95 : 0.30),
                                accentColor.opacity(canCapture ? 0.88 : 0.22),
                                Color.purple.opacity(canCapture ? 0.72 : 0.18)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 3
                    )
                    .frame(width: 68, height: 68)
                    .shadow(color: accentColor.opacity(canCapture ? 0.40 : 0), radius: 10)

                Circle()
                    .fill(.white.opacity(canCapture ? 1 : 0.42))
                    .frame(width: 56, height: 56)
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 2)

                Image(systemName: "camera.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(canCapture ? 0.72 : 0.28))
            }
        }
        .buttonStyle(.plain)
        .disabled(!canCapture)
        .opacity(canCapture ? 1 : 0.76)
        .accessibilityLabel("Take photo")
    }
}

// MARK: - Value scanned label

private struct ScannerValueLabel: View {
    @Environment(AppServices.self) private var services

    let results: [ScanResult]
    let selectedVariantsByResultID: [UUID: String]
    let selectedVariantQuantitiesByResultID: [UUID: [String: Int]]

    @State private var totalText: String = "—"

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Scanned value")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.55))
                    Text(totalText)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.25), value: totalText)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                )

                Spacer(minLength: 0)
            }
            .padding(.leading, 16)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .task(id: taskID) { await refreshTotal() }
    }

    private var taskID: String {
        results.map { r in
            let quantities = selectedVariantQuantitiesByResultID[r.id] ?? [:]
            let sorted = quantities.keys.sorted().map { "\($0):\(quantities[$0] ?? 0)" }.joined(separator: "|")
            let selected = selectedVariantsByResultID[r.id] ?? ""
            return "\(r.card.masterCardId)_\(selected)_\(sorted)"
        }.joined(separator: ",")
        + "_\(services.priceDisplay.currency.rawValue)_\(services.pricing.usdToGbp)"
    }

    private func refreshTotal() async {
        var total: Double = 0
        for result in results {
            let quantities = selectedVariantQuantitiesByResultID[result.id] ?? [:]
            for (variantKey, quantity) in quantities where quantity > 0 {
                if let usd = await services.pricing.usdPriceForVariantAndGrade(
                    for: result.card, variantKey: variantKey, grade: "raw"
                ) {
                    total += usd * Double(quantity)
                }
            }
        }
        let formatted = services.priceDisplay.currency.format(
            amountUSD: total,
            usdToGbp: services.pricing.usdToGbp
        )
        await MainActor.run {
            withAnimation { totalText = formatted }
        }
    }
}

// MARK: - Brand pick (multi-franchise)

private struct ScannerBrandPickPanel: View {
    let brands: [TCGBrand]
    var onSelect: (TCGBrand) -> Void

    @State private var appeared = false

    /// Splits brands into two rows: first row gets the ceiling half (e.g. 3 → 2+1, 2 → 1+1).
    private var firstRowBrands: [TCGBrand] {
        let n = (brands.count + 1) / 2
        return Array(brands.prefix(n))
    }

    private var secondRowBrands: [TCGBrand] {
        let n = (brands.count + 1) / 2
        return Array(brands.dropFirst(n))
    }

    var body: some View {
        let safeBottom = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.bottom ?? 0

        VStack(spacing: 0) {
            Text("Select a brand to scan")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 8)

            VStack(spacing: 14) {
                brandLogoRow(brands: firstRowBrands, singleItemMaxWidth: 200)
                if !secondRowBrands.isEmpty {
                    brandLogoRow(brands: secondRowBrands, singleItemMaxWidth: 200)
                }
            }
            .padding(.horizontal, 20)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)

            Spacer(minLength: 0)

            Capsule()
                .fill(Color.white.opacity(0.15))
                .frame(width: 36, height: 4)
                .padding(.bottom, max(safeBottom, 16))
                .opacity(appeared ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { appeared = true }
        }
        .onDisappear { appeared = false }
    }

    @ViewBuilder
    private func brandLogoRow(brands rowBrands: [TCGBrand], singleItemMaxWidth: CGFloat) -> some View {
        let row = HStack(spacing: 12) {
            ForEach(rowBrands) { brand in
                Button {
                    onSelect(brand)
                } label: {
                    scannerBrandLogo(brand)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Scan \(brand.displayTitle) cards")
                .frame(maxWidth: .infinity)
            }
        }

        if rowBrands.count == 1 {
            HStack {
                Spacer(minLength: 0)
                row.frame(maxWidth: singleItemMaxWidth)
                Spacer(minLength: 0)
            }
        } else {
            row
        }
    }

    private func scannerBrandLogo(_ brand: TCGBrand) -> some View {
        brandPickerImage(brand)
            .resizable()
            .renderingMode(.original)
            .interpolation(.high)
            .scaledToFit()
            .frame(height: 40)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
    }

    private func brandPickerImage(_ brand: TCGBrand) -> Image {
        switch brand {
        case .pokemon: Image("BrandPokemonLogo")
        }
    }
}

// MARK: - Idle instructions panel

private struct ScannerIdleInstructions: View {
    @State private var appeared = false

    private struct Step {
        let icon: String
        let iconColor: Color
        let title: String
        let description: String
    }

    private let steps: [Step] = [
        Step(
            icon: "viewfinder",
            iconColor: Color(red: 0.35, green: 0.78, blue: 1.0),
            title: "Frame",
            description: "Fit all four corners"
        ),
        Step(
            icon: "hand.raised.fill",
            iconColor: Color(red: 0.35, green: 0.78, blue: 1.0),
            title: "Hold steady",
            description: "Hold still for focus"
        ),
        Step(
            icon: "camera.fill",
            iconColor: .white,
            title: "Scan",
            description: "Tap shutter to identify"
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
                .frame(height: ScannerCardFrameLayout.sheetTopContentInset)

            Capsule()
                .fill(Color.white.opacity(0.22))
                .frame(width: 36, height: 5)
                .padding(.top, 10)

            VStack(spacing: 4) {
                Text("Ready to scan")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
            }
            .multilineTextAlignment(.center)
            .padding(.top, 18)
            .padding(.horizontal, 24)

            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    instructionStep(step)

                    if index < steps.count - 1 {
                        Rectangle()
                            .fill(Color.white.opacity(0.12))
                            .frame(width: 22, height: 1)
                            .padding(.top, 22)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 22)
            .padding(.bottom, 12)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 10)
        .onAppear {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { appeared = true }
        }
        .onDisappear { appeared = false }
    }

    @ViewBuilder
    private func instructionStep(_ step: Step) -> some View {
        VStack(spacing: 8) {
            Image(systemName: step.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(step.iconColor)
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.08), in: Circle())

            Text(step.title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)

            Text(step.description)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.48))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Results overlay

private struct ScannerResultsOverlay: View {
    @Environment(AppServices.self) private var services

    let results: [ScanResult]
    @Binding var currentResultIndex: Int
    @Binding var barDragOffset: CGFloat
    @Binding var selectedVariantsByResultID: [UUID: String]
    @Binding var selectedVariantQuantitiesByResultID: [UUID: [String: Int]]
    var onOpenDetails: () -> Void
    let onDeleteResult: (UUID) -> Void
    let onPickAlternative: (UUID, Card) -> Void

    private var safeBottom: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.bottom ?? 0
    }

    var body: some View {
        let count = results.count
        let screenWidth = UIScreen.main.bounds.width

        VStack(spacing: 0) {
            Color.clear
                .frame(height: ScannerCardFrameLayout.sheetTopContentInset)

            ZStack(alignment: .top) {
                ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                    resultPage(result: result, index: index, screenWidth: screenWidth)
                }
            }
            .frame(width: screenWidth)
            .frame(maxHeight: .infinity, alignment: .top)
            .clipped()
            .contentShape(Rectangle())
            .simultaneousGesture(horizontalPageGesture(count: count))

            pageIndicator(count: count)
                .padding(.top, 2)
                .padding(.bottom, max(safeBottom + 4, 8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func resultPage(result: ScanResult, index: Int, screenWidth: CGFloat) -> some View {
        let offset = CGFloat(index - currentResultIndex) * (screenWidth + 12) + barDragOffset
        let isCurrentPage = index == currentResultIndex
        let isAdjacentPage = abs(index - currentResultIndex) <= 1

        ScanResultBar(
            result: result,
            isCurrentPage: isCurrentPage,
            onPickAlternative: { picked in
                onPickAlternative(result.id, picked)
            },
            onOpenDetails: onOpenDetails,
            onDelete: { onDeleteResult(result.id) },
            selectedVariant: variantBinding(for: result),
            selectedVariantQuantities: variantQuantitiesBinding(for: result)
        )
        .frame(width: screenWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .offset(x: offset)
        .opacity(isAdjacentPage ? (isCurrentPage ? 1 : 0.55) : 0)
        .allowsHitTesting(isCurrentPage)
    }

    private func variantBinding(for result: ScanResult) -> Binding<String> {
        Binding(
            get: { selectedVariantsByResultID[result.id] ?? "" },
            set: { selectedVariantsByResultID[result.id] = $0 }
        )
    }

    private func variantQuantitiesBinding(for result: ScanResult) -> Binding<[String: Int]> {
        Binding(
            get: { selectedVariantQuantitiesByResultID[result.id] ?? [:] },
            set: { selectedVariantQuantitiesByResultID[result.id] = $0 }
        )
    }

    @ViewBuilder
    private func pageIndicator(count: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(
                        i == currentResultIndex
                            ? services.theme.accentColor
                            : Color.primary.opacity(0.22)
                    )
                    .frame(
                        width: i == currentResultIndex ? 7 : 5,
                        height: i == currentResultIndex ? 7 : 5
                    )
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.82), value: currentResultIndex)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Scanned card \(currentResultIndex + 1) of \(count)")
    }

    private func horizontalPageGesture(count: Int) -> some Gesture {
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
    }
}

// MARK: - Detail sheet (large, shown on swipe up)

private struct ScannerDetailSheet: View {
    let results: [ScanResult]
    @Binding var currentResultIndex: Int
    let selectedVariantsByResultID: [UUID: String]
    let onPickAlternative: (UUID, Card) -> Void

    var body: some View {
        CardDetailSheet(
            cards: results.map(\.card),
            startIndex: currentResultIndex
        )
    }
}

// MARK: - Undo below reticle

private struct ScannerUndoBelowFrameButton: View {
    var action: () -> Void

    var body: some View {
        GeometryReader { geo in
            let cardW = geo.size.width * ScannerCardFrameLayout.reticleWidthFraction
            let cardH = cardW * ScannerCardFrameLayout.cardAspectHeightOverWidth
            let cardY = (geo.size.height - cardH) / 2 - ScannerCardFrameLayout.verticalCenterBias
            let belowFrameTop = cardY + cardH + 34

            VStack(spacing: 0) {
                Spacer().frame(height: belowFrameTop)
                Button(action: action) {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.thinMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
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
    var alignmentTier: ScannerAlignmentTier
    var isCapturing: Bool
    var showsAlignmentLabel: Bool = true
    var onRectChanged: (CGRect) -> Void

    var body: some View {
        GeometryReader { geo in
            let cardW = geo.size.width * ScannerCardFrameLayout.reticleWidthFraction
            let cardH = cardW * ScannerCardFrameLayout.cardAspectHeightOverWidth
            let cardX = geo.size.width / 2
            let cardY = (geo.size.height - cardH) / 2 - ScannerCardFrameLayout.verticalCenterBias
            let cardCenterY = cardY + cardH / 2

            ZStack {
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

                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(borderColor.opacity(0.32), lineWidth: 1)
                    .frame(width: cardW, height: cardH)
                    .position(x: cardX, y: cardCenterY)

                ScannerReticleCorners(cornerLength: 30)
                    .stroke(
                        borderColor,
                        style: StrokeStyle(
                            lineWidth: isCapturing ? 4 : 3,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .frame(width: cardW, height: cardH)
                    .position(x: cardX, y: cardCenterY)
                    .shadow(color: borderColor.opacity(0.55), radius: isCapturing ? 8 : 5)
                    .animation(.easeInOut(duration: 0.35), value: alignmentTier)

                if showsAlignmentLabel {
                    VStack {
                        Spacer().frame(height: cardCenterY + cardH / 2 + 12)
                        qualityLabel
                            .position(x: cardX, y: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            .onAppear { reportNormalizedReticleRect(geo: geo, cardX: cardX, cardY: cardY, cardW: cardW, cardH: cardH) }
            .onChange(of: geo.size) { _, _ in
                reportNormalizedReticleRect(geo: geo, cardX: cardX, cardY: cardY, cardW: cardW, cardH: cardH)
            }
        }
    }

    private func reportNormalizedReticleRect(geo: GeometryProxy, cardX: CGFloat, cardY: CGFloat, cardW: CGFloat, cardH: CGFloat) {
        let screenW = geo.size.width, screenH = geo.size.height
        guard screenW > 0, screenH > 0 else { return }
        onRectChanged(CGRect(x: (cardX - cardW / 2) / screenW, y: cardY / screenH, width: cardW / screenW, height: cardH / screenH))
    }

    private var borderColor: Color {
        if isCapturing { return .white }
        switch alignmentTier {
        case .ready: return .green
        case .holdSteady: return Color.yellow.opacity(0.8)
        case .align: return Color.white.opacity(0.6)
        }
    }

    @ViewBuilder
    private var qualityLabel: some View {
        if isCapturing {
            Label("Capturing…", systemImage: "camera.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.thinMaterial, in: Capsule())
        } else {
            switch alignmentTier {
            case .ready:
                Label("Ready to scan", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.thinMaterial, in: Capsule())
            case .holdSteady:
                Label("Hold steady", systemImage: "viewfinder")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.yellow)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.thinMaterial, in: Capsule())
            case .align:
                Text("Align card in frame")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.3), in: Capsule())
            }
        }
    }

}

private struct ScannerReticleCorners: Shape {
    let cornerLength: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let length = min(cornerLength, min(rect.width, rect.height) * 0.25)

        path.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY))

        path.move(to: CGPoint(x: rect.maxX - length, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + length))

        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - length))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - length, y: rect.maxY))

        path.move(to: CGPoint(x: rect.minX + length, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - length))

        return path
    }
}
