import SwiftUI
import AVFoundation

private enum ScannerCardFrameLayout {
    static let verticalCenterBias: CGFloat = 8
    /// Fraction of total screen height used by the camera preview.
    static let cameraHeightFraction: CGFloat = 0.70
    /// Alignment frame width as a fraction of preview width. Slightly smaller than full-card fill helps autofocus lock on the subject.
    static let reticleWidthFraction: CGFloat = 0.58
    /// Pokémon TCG–style aspect (tall card).
    static let cardAspectHeightOverWidth: CGFloat = 1.395
}

struct CardScannerView: View {
    @Environment(AppServices.self) private var services
    var onMatch: (Card) -> Void
    var onDismiss: () -> Void

    @State private var viewModel = CardScannerViewModel()
    @State private var permissionDenied = false

    @State private var currentResultIndex = 0
    @State private var barDragOffset: CGFloat = 0
    @State private var showDetailSheet = false
    @State private var showBulkAddSheet = false
    @State private var isCameraPaused = false
    /// Variant selected in the overlay bar at the moment the user swiped up, keyed by ScanResult.id.
    @State private var selectedVariantsByResultID: [UUID: String] = [:]
    /// Set when the user must pick Pokémon vs ONE PIECE (`nil` = not chosen yet, only when multiple brands enabled).
    @State private var scanBrandChoice: TCGBrand? = nil
    @State private var showOnePieceDebugSheet = false

    private var enabledScanBrands: [TCGBrand] {
        services.brandsManifest.sortBrands(services.brandSettings.enabledBrands)
    }

    private var needsScanBrandPick: Bool {
        enabledScanBrands.count > 1 && scanBrandChoice == nil
    }

    /// Show ONE PIECE debug affordance after a franchise is chosen (including single-brand OP).
    private var showOnePieceDebugButton: Bool {
        viewModel.scanBrand == .onePiece && !needsScanBrandPick
    }

    var body: some View {
        GeometryReader { geo in
            let cameraHeight = geo.size.height * ScannerCardFrameLayout.cameraHeightFraction

            VStack(spacing: 0) {
                // Top 70% — camera preview + reticle
                ZStack(alignment: .top) {
                    CameraPreviewView(session: viewModel.session)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if case .idle = viewModel.scanState {
                        CardScannerReticle(
                            frameQuality: viewModel.frameQuality,
                            isCapturing: viewModel.isCapturing,
                            hideQualityPill: viewModel.requiresBrandSelection
                        ) { rect in
                            viewModel.cardNormalizedRect = rect
                        }
                    } else if case .scanning = viewModel.scanState {
                        CardScannerReticle(
                            frameQuality: viewModel.frameQuality,
                            isCapturing: true,
                            hideQualityPill: false
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

                    if let err = viewModel.lastErrorMessage {
                        Text(err)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .padding(.horizontal, 24)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .padding(.top, ScannerSheetLayout.statusBarHeight + 8)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    scannerScanningOverlay(geo: geo)

                    if permissionDenied { permissionDeniedOverlay }

                    // Value scanned label — bottom-leading of camera area
                    if !viewModel.scanResults.isEmpty {
                        ScannerValueLabel(
                            results: viewModel.scanResults,
                            selectedVariantsByResultID: selectedVariantsByResultID
                        )
                        .transition(AnyTransition.opacity.combined(with: AnyTransition.move(edge: .bottom)))
                    }

                    // Pause / resume button — bottom-trailing of camera area
                    VStack {
                        Spacer(minLength: 0)
                        HStack {
                            Spacer(minLength: 0)
                            HStack(spacing: 12) {
                                if showOnePieceDebugButton {
                                    Button {
                                        if !isCameraPaused {
                                            isCameraPaused = true
                                            viewModel.stopSession()
                                        }
                                        showOnePieceDebugSheet = true
                                    } label: {
                                        Image(systemName: "info.circle")
                                            .font(.system(size: 30))
                                            .foregroundStyle(.white, .black.opacity(0.45))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("ONE PIECE scan debug")
                                }

                                Button {
                                    isCameraPaused.toggle()
                                    if isCameraPaused {
                                        viewModel.stopSession()
                                    } else {
                                        viewModel.startSession()
                                    }
                                    HapticManager.impact(.light)
                                } label: {
                                    Image(systemName: isCameraPaused ? "play.circle.fill" : "pause.circle.fill")
                                        .font(.system(size: 30))
                                        .foregroundStyle(.white, .black.opacity(0.45))
                                        .animation(.easeInOut(duration: 0.2), value: isCameraPaused)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(isCameraPaused ? "Resume camera" : "Pause camera")
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

                // Bottom 30% — results overlay or idle instructions
                ZStack {
                    Color.black

                    if viewModel.scanResults.isEmpty {
                        if needsScanBrandPick {
                            ScannerBrandPickPanel(brands: enabledScanBrands) { brand in
                                HapticManager.selection()
                                scanBrandChoice = brand
                                viewModel.scanBrand = brand
                                viewModel.requiresBrandSelection = false
                            }
                            .transition(AnyTransition.opacity)
                        } else {
                            ScannerIdleInstructions()
                                .transition(AnyTransition.opacity)
                        }
                    } else {
                        ScannerResultsOverlay(
                            results: viewModel.scanResults,
                            currentResultIndex: $currentResultIndex,
                            barDragOffset: $barDragOffset,
                            selectedVariantsByResultID: $selectedVariantsByResultID,
                            onSwipeUp: { showDetailSheet = true },
                            onOpenDetails: { showDetailSheet = true },
                            onAddAllToCollection: { showBulkAddSheet = true },
                            onPickAlternative: { id, picked in
                                viewModel.replaceScanResult(id: id, with: picked)
                            }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .overlay(alignment: .topTrailing) {
                if case .scanning = viewModel.scanState {
                    EmptyView()
                } else {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.white, .black.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close scanner")
                    .padding(.top, ScannerSheetLayout.statusBarHeight + 8)
                    .padding(.trailing, 16)
                }
            }
            .sheet(isPresented: $showDetailSheet, onDismiss: {
                if !isCameraPaused { viewModel.startSession() }
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
                if isShowing { viewModel.stopSession() }
            }
            .onChange(of: showBulkAddSheet) { _, isShowing in
                if isShowing { viewModel.stopSession() }
            }
            .onChange(of: showOnePieceDebugSheet) { _, isShowing in
                if isShowing {
                    if !isCameraPaused { isCameraPaused = true }
                    viewModel.stopSession()
                }
            }
            .sheet(isPresented: $showOnePieceDebugSheet) {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if let debugImage = viewModel.onePieceDebugImage {
                                OnePieceDebugPreviewCard(
                                    image: debugImage,
                                    ocrFraction: viewModel.onePieceOCRFraction,
                                    effectBandStart: viewModel.onePieceEffectBandStart,
                                    effectBandEnd: viewModel.onePieceEffectBandEnd
                                )
                            }

                            Text(viewModel.onePieceDebugText)
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding()
                    }
                    .navigationTitle("ONE PIECE debug")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showOnePieceDebugSheet = false }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showBulkAddSheet, onDismiss: {
                if !isCameraPaused { viewModel.startSession() }
            }) {
                ScannerBulkAddSheet(
                    results: viewModel.scanResults,
                    selectedVariantsByResultID: $selectedVariantsByResultID,
                    onSuccessClearSession: {
                        viewModel.clearAllScanResults()
                        selectedVariantsByResultID = [:]
                        currentResultIndex = 0
                    }
                )
                .environment(services)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(24)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            viewModel.configure(cardDataService: services.cardData)
            let brands = enabledScanBrands
            if brands.count <= 1 {
                let b = brands.first ?? .pokemon
                scanBrandChoice = b
                viewModel.scanBrand = b
                viewModel.requiresBrandSelection = false
            } else {
                scanBrandChoice = nil
                viewModel.requiresBrandSelection = true
            }
            viewModel.onMatch = { _ in
                HapticManager.impact(.medium)
                currentResultIndex = 0
            }
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            if status == .denied || status == .restricted {
                permissionDenied = true
            } else {
                viewModel.startSession()
            }
        }
        .onDisappear { viewModel.stopSession() }
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: viewModel.scanResults.isEmpty)
        .animation(.easeOut(duration: 0.2), value: viewModel.lastErrorMessage)
        .background(Color.black.ignoresSafeArea())
        .interactiveDismissDisabled(true)
    }

    @ViewBuilder
    private func scannerScanningOverlay(geo: GeometryProxy) -> some View {
        if case .scanning = viewModel.scanState {
            VStack {
                HStack {
                    Spacer(minLength: 0)
                    HStack(spacing: 6) {
                        ProgressView().tint(.white).scaleEffect(0.8)
                        Text("Identifying…")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    Spacer(minLength: 0)
                }
                .padding(.top, geo.safeAreaInsets.top + 8)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(false)
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

private struct OnePieceDebugPreviewCard: View {
    let image: UIImage
    let ocrFraction: CGFloat
    let effectBandStart: CGFloat
    let effectBandEnd: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Captured image with OCR area")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            GeometryReader { geo in
                let width = geo.size.width
                let imageAspect = max(image.size.width, 1) / max(image.size.height, 1)
                let height = width / imageAspect
                let footerHeight = height * ocrFraction
                let effectY = height * effectBandStart
                let effectHeight = height * (effectBandEnd - effectBandStart)

                ZStack(alignment: .top) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: width, height: height)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    Rectangle()
                        .fill(Color.cyan.opacity(0.16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 0, style: .continuous)
                                .stroke(Color.cyan, lineWidth: 2)
                        )
                        .frame(width: width, height: effectHeight)
                        .offset(y: effectY)

                    Text("OCR ranks with this 60-82% effect band")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.6), in: Capsule())
                        .offset(y: max(effectY + 8, 8))

                    VStack {
                        Spacer(minLength: 0)

                        Rectangle()
                            .fill(Color.orange.opacity(0.18))
                            .overlay(
                                RoundedRectangle(cornerRadius: 0, style: .continuous)
                                    .stroke(Color.orange, lineWidth: 2)
                            )
                            .frame(width: width, height: footerHeight)
                            .overlay(alignment: .top) {
                                Text("OCR filters with this bottom 18% strip")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(.black.opacity(0.6), in: Capsule())
                                    .padding(.top, 8)
                            }
                    }
                }
                .frame(width: width, height: height)
            }
            .aspectRatio(max(image.size.width, 1) / max(image.size.height, 1), contentMode: .fit)
        }
    }
}

// MARK: - Layout constants

private enum ScannerSheetLayout {
    static var statusBarHeight: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.top ?? 54
    }
    static let deviceCornerRadius: CGFloat = (UIScreen.main.value(forKey: "displayCornerRadius") as? CGFloat) ?? 44
}

// MARK: - Value scanned label

private struct ScannerValueLabel: View {
    @Environment(AppServices.self) private var services

    let results: [ScanResult]
    let selectedVariantsByResultID: [UUID: String]

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
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            let v = selectedVariantsByResultID[r.id] ?? r.card.pricingVariants?.first ?? "normal"
            return "\(r.card.masterCardId)_\(v)"
        }.joined(separator: ",")
        + "_\(services.priceDisplay.currency.rawValue)_\(services.pricing.usdToGbp)"
    }

    private func refreshTotal() async {
        var total: Double = 0
        for result in results {
            let variantKey = selectedVariantsByResultID[result.id]
                ?? result.card.pricingVariants?.first
                ?? "normal"
            if let usd = await services.pricing.usdPriceForVariantAndGrade(
                for: result.card, variantKey: variantKey, grade: "raw"
            ) {
                total += usd
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

    var body: some View {
        let safeBottom = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.bottom ?? 0

        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 18) {
                Text("Select a brand to scan")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .multilineTextAlignment(.center)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 8)

                HStack(spacing: 20) {
                    ForEach(brands) { brand in
                        Button {
                            onSelect(brand)
                        } label: {
                            scannerBrandLogo(brand)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Scan \(brand.displayTitle) cards")
                    }
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 10)
            }
            .padding(.horizontal, 24)

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

    private func scannerBrandLogo(_ brand: TCGBrand) -> some View {
        brandPickerImage(brand)
            .resizable()
            .renderingMode(.original)
            .interpolation(.high)
            .scaledToFill()
            .frame(width: 140, height: 40)
            .clipped()
            .contentShape(Rectangle())
    }

    private func brandPickerImage(_ brand: TCGBrand) -> Image {
        switch brand {
        case .pokemon: Image("BrandPokemonLogo")
        case .onePiece: Image("BrandOnePieceLogo")
        case .lorcana: Image("lorcana")
        }
    }
}

// MARK: - Idle instructions panel

private struct ScannerIdleInstructions: View {
    @State private var appeared = false

    private let steps: [(icon: String, text: String)] = [
        ("viewfinder.rectangular", "Align card to the frame above"),
        ("square.on.square",       "Select variant and add to collection"),
        ("arrow.up",               "Swipe up to view full card details"),
    ]

    var body: some View {
        let safeBottom = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.bottom ?? 0

        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 20) {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.08))
                                .frame(width: 36, height: 36)
                            Image(systemName: step.icon)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.75))
                        }
                        Text(step.text)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.white.opacity(0.65))
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 10)
                    .animation(
                        .spring(response: 0.5, dampingFraction: 0.8)
                            .delay(Double(i) * 0.08),
                        value: appeared
                    )
                }
            }
            .padding(.horizontal, 28)

            Spacer(minLength: 0)

            // Subtle divider hint at top
            Capsule()
                .fill(Color.white.opacity(0.15))
                .frame(width: 36, height: 4)
                .padding(.bottom, max(safeBottom, 16))
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.4).delay(0.25), value: appeared)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { appeared = true }
        .onDisappear { appeared = false }
    }
}

// MARK: - Results overlay (no sheet, drawn directly over camera)

private struct ScannerResultsOverlay: View {
    @Environment(AppServices.self) private var services

    let results: [ScanResult]
    @Binding var currentResultIndex: Int
    @Binding var barDragOffset: CGFloat
    @Binding var selectedVariantsByResultID: [UUID: String]
    var onSwipeUp: () -> Void
    var onOpenDetails: () -> Void
    var onAddAllToCollection: () -> Void
    let onPickAlternative: (UUID, Card) -> Void

    var body: some View {
        let count = results.count
        let screenWidth = UIScreen.main.bounds.width
        let safeBottom = (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.bottom ?? 0)

        VStack(spacing: 8) {
            // Drag indicator — also the swipe-up target
            Capsule()
                .fill(Color.primary.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 4)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle().inset(by: -20))
                .gesture(
                    DragGesture(minimumDistance: 10)
                        .onEnded { value in
                            guard abs(value.translation.height) > abs(value.translation.width) else { return }
                            if value.translation.height < -20 || value.predictedEndTranslation.height < -60 {
                                HapticManager.impact(.light)
                                onSwipeUp()
                            }
                        }
                )

            ZStack {
                ForEach(Array(results.enumerated()), id: \.element.id) { i, result in
                    let offset = CGFloat(i - currentResultIndex) * (screenWidth + 12) + barDragOffset
                    ScanResultBar(
                        result: result,
                        isCurrentPage: i == currentResultIndex,
                        onPickAlternative: { picked in
                            onPickAlternative(result.id, picked)
                        },
                        onOpenDetails: onOpenDetails,
                        onAddAllToCollection: onAddAllToCollection,
                        selectedVariant: Binding(
                            get: { selectedVariantsByResultID[result.id] ?? result.card.pricingVariants?.first ?? "normal" },
                            set: { selectedVariantsByResultID[result.id] = $0 }
                        )
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: screenWidth)
                    .offset(x: offset)
                    .scaleEffect(i == currentResultIndex ? 1.0 : 0.95)
                    .opacity(abs(i - currentResultIndex) <= 1 ? (i == currentResultIndex ? 1 : 0.6) : 0)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: screenWidth)
            .contentShape(Rectangle())
            .simultaneousGesture(horizontalPageGesture(count: count))

            // Page dots
            HStack(spacing: 5) {
                ForEach(0..<count, id: \.self) { i in
                    Circle()
                        .fill(i == currentResultIndex ? Color.primary : Color.primary.opacity(0.3))
                        .frame(width: i == currentResultIndex ? 6 : 4,
                               height: i == currentResultIndex ? 6 : 4)
                        .animation(.spring(response: 0.2), value: currentResultIndex)
                }
            }
            .padding(.bottom, safeBottom > 0 ? safeBottom : 16)
        }
        .frame(width: screenWidth)
        .simultaneousGesture(
            DragGesture(minimumDistance: 10)
                .onEnded { value in
                    guard value.translation.height < 0 else { return }
                    guard abs(value.translation.height) > abs(value.translation.width) else { return }
                    if value.translation.height < -20 || value.predictedEndTranslation.height < -60 {
                        HapticManager.impact(.light)
                        onSwipeUp()
                    }
                }
        )
        .background {
            UnevenRoundedRectangle(
                topLeadingRadius: 20,
                bottomLeadingRadius: ScannerSheetLayout.deviceCornerRadius,
                bottomTrailingRadius: ScannerSheetLayout.deviceCornerRadius,
                topTrailingRadius: 20,
                style: .continuous
            )
            .fill(.regularMaterial)
            .ignoresSafeArea(edges: .bottom)
        }
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
    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme

    let results: [ScanResult]
    @Binding var currentResultIndex: Int
    let selectedVariantsByResultID: [UUID: String]
    let onPickAlternative: (UUID, Card) -> Void

    var body: some View {
        let count = results.count
        let currentCard = results.indices.contains(currentResultIndex) ? results[currentResultIndex].card : results.first?.card
        let currentSet = currentCard.flatMap { card in
            services.cardData.sets.first { $0.setCode == card.setCode }
        }
        let headerHeight = RootChromeEnvironment.searchBarStackHeight

        ZStack(alignment: .top) {
            // Scroll content fills the full frame and flows behind the glass header
            TabView(selection: $currentResultIndex) {
                ForEach(Array(results.enumerated()), id: \.element.id) { i, result in
                    ScannerDetailPage(
                        card: result.card,
                        initialVariant: selectedVariantsByResultID[result.id],
                        headerHeight: headerHeight
                    )
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: count > 1 ? .always : .never))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(edges: .top)
            .onChange(of: currentResultIndex) { _, _ in HapticManager.selection() }

            // Glass header overlaid on top
            HStack(alignment: .center, spacing: 10) {
                Group {
                    if let set = currentSet, currentCard != nil {
                        SetLogoAsyncImage(
                            logoSrc: set.logoSrc,
                            height: 26,
                            brand: services.brandSettings.selectedCatalogBrand
                        )
                            .frame(maxWidth: 72, maxHeight: headerHeight - 14)
                    } else {
                        Color.clear.frame(width: 0, height: 1)
                    }
                }
                .frame(minHeight: 32, alignment: .center)

                Text(currentCard?.cardName ?? "")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(.easeInOut(duration: 0.15), value: currentCard?.cardName)
            }
            .padding(.horizontal, 16)
            .frame(height: headerHeight, alignment: .center)
            .frame(maxWidth: .infinity)
            .background { CardDetailStyleGlassBarBackground() }
            .ignoresSafeArea(edges: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colorScheme == .dark ? Color.black : Color(uiColor: .systemBackground))
    }
}

// MARK: - Large detail single page

private struct ScannerDetailPage: View {
    let card: Card
    var initialVariant: String? = nil
    var headerHeight: CGFloat = RootChromeEnvironment.searchBarStackHeight
    @State private var imageAppeared = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ProgressiveAsyncImage(
                    lowResURL: AppConfiguration.imageURL(relativePath: card.imageLowSrc),
                    highResURL: card.imageHighSrc.map { AppConfiguration.imageURL(relativePath: $0) }
                ) {
                    Color(uiColor: .tertiarySystemFill).aspectRatio(5/7, contentMode: .fit)
                }
                .padding(.horizontal, 16)
                .padding(.top, headerHeight + 6)
                .scaleEffect(imageAppeared ? 1.0 : 0.94)
                .onAppear {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { imageAppeared = true }
                }
                .onDisappear { imageAppeared = false }

                CardPricingPanel(card: card, initialVariant: initialVariant)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
            }
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            let belowFrameTop = cardY + cardH + 48

            VStack(spacing: 0) {
                Spacer().frame(height: belowFrameTop)
                Button(action: action) {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
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
    private static let qualityGood: Double = 0.45
    private static let qualityWarming: Double = 0.2

    var frameQuality: Double
    var isCapturing: Bool
    /// Hides the lower pill until a scan brand is chosen (multi-brand flow).
    var hideQualityPill: Bool = false
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
                    .strokeBorder(borderColor, lineWidth: isCapturing ? 2.5 : 2)
                    .frame(width: cardW, height: cardH)
                    .position(x: cardX, y: cardCenterY)
                    .animation(.easeInOut(duration: 0.25), value: frameQuality)

                VStack {
                    Spacer().frame(height: cardCenterY + cardH / 2 + 12)
                    if !hideQualityPill {
                        qualityLabel.position(x: cardX, y: 0)
                    }
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
        let screenW = geo.size.width, screenH = geo.size.height
        guard screenW > 0, screenH > 0 else { return }
        onRectChanged(CGRect(x: (cardX - cardW / 2) / screenW, y: cardY / screenH, width: cardW / screenW, height: cardH / screenH))
    }

    private var borderColor: Color {
        if isCapturing { return .white }
        if frameQuality >= Self.qualityGood { return .green }
        if frameQuality >= Self.qualityWarming { return Color.yellow.opacity(0.8) }
        return Color.white.opacity(0.6)
    }

    @ViewBuilder
    private var qualityLabel: some View {
        if isCapturing {
            Label("Capturing…", systemImage: "camera.fill")
                .font(.caption.weight(.semibold)).foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
        } else if frameQuality >= Self.qualityGood {
            Label("Hold steady", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold)).foregroundStyle(.green)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
        } else {
            Text("Align card in frame")
                .font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.black.opacity(0.3), in: Capsule())
        }
    }
}
