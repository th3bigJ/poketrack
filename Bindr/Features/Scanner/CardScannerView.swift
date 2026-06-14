import SwiftUI
import AVFoundation

private enum ScannerCardFrameLayout {
    static let verticalCenterBias: CGFloat = 8
    /// Fraction of total screen height used by the camera preview.
    static let cameraHeightFraction: CGFloat = 0.66
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
            let cameraHeight = geo.size.height * ScannerCardFrameLayout.cameraHeightFraction

            VStack(spacing: 0) {
                // Top 70% — camera preview + reticle
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
                            isCapturing: false
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

                    VStack {
                        Spacer(minLength: 0)
                        Button {
                            guard canTriggerCapture else { return }
                            viewModel.capturePhoto()
                            HapticManager.impact(.medium)
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(.white.opacity(0.92))
                                    .frame(width: 68, height: 68)
                                Circle()
                                    .stroke(Color.black.opacity(0.28), lineWidth: 3)
                                    .frame(width: 56, height: 56)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!canTriggerCapture)
                        .accessibilityLabel("Take photo")
                        .padding(.bottom, 14)
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

                // Bottom 30% — results overlay or idle instructions
                ZStack {
                    Color.black

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
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
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
            viewModel.onMatch = { _ in
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

    private let steps: [(icon: String, iconColor: Color, iconBackground: Color, title: String, subtitle: String)] = [
        ("viewfinder.rectangular", Color.blue.opacity(0.9), Color.blue.opacity(0.28), "Align card to the frame above", "Position the card within the frame"),
        ("camera.circle.fill", Color.orange.opacity(0.9), Color.orange.opacity(0.28), "Tap the shutter to scan", "Wait for the green frame, then capture"),
        ("square.on.square",       Color.green.opacity(0.9), Color.green.opacity(0.28), "Select variant and add to collection", "Choose the correct card and save"),
    ]

    var body: some View {
        let safeBottom = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.bottom ?? 0

        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(step.iconBackground)
                                .frame(width: 54, height: 54)
                            Image(systemName: step.icon)
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(step.iconColor)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(step.title)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(Color.white.opacity(0.95))
                            Text(step.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(Color.white.opacity(0.65))
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.clear)
                    .overlay(alignment: .bottom) {
                        if i < steps.count - 1 {
                            Rectangle()
                                .fill(Color.white.opacity(0.08))
                                .frame(height: 1)
                                .padding(.leading, 84)
                        }
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
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, max(safeBottom, 12))
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: appeared)
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
    @Binding var selectedVariantQuantitiesByResultID: [UUID: [String: Int]]
    var onOpenDetails: () -> Void
    let onDeleteResult: (UUID) -> Void
    let onPickAlternative: (UUID, Card) -> Void

    var body: some View {
        let count = results.count
        let screenWidth = UIScreen.main.bounds.width

        VStack(spacing: 8) {
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
                        onDelete: { onDeleteResult(result.id) },
                        selectedVariant: Binding(
                            get: { selectedVariantsByResultID[result.id] ?? "" },
                            set: { selectedVariantsByResultID[result.id] = $0 }
                        ),
                        selectedVariantQuantities: Binding(
                            get: { selectedVariantQuantitiesByResultID[result.id] ?? [:] },
                            set: { selectedVariantQuantitiesByResultID[result.id] = $0 }
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
            .padding(.bottom, 2)
        }
        .frame(width: screenWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            Rectangle()
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
    private static let qualityGood: Double = 0.45
    private static let qualityWarming: Double = 0.2

    var frameQuality: Double
    var isCapturing: Bool
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

}
