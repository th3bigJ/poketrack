import SwiftUI
import UIKit

enum TransactionMarkAction: String, Identifiable, CaseIterable {
    case bought
    case sold
    case packed
    case tradedIn
    case tradedOut
    case giftedIn
    case giftedOut
    case adjustmentIn
    case adjustmentOut
    case opened

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bought: return "Bought"
        case .sold: return "Sold"
        case .packed: return "Packed"
        case .tradedIn: return "Trade In"
        case .tradedOut: return "Trade Out"
        case .giftedIn: return "Gift In"
        case .giftedOut: return "Gift Out"
        case .adjustmentIn: return "Adjustment In"
        case .adjustmentOut: return "Adjustment Out"
        case .opened: return "Opened"
        }
    }
}

struct TransactionDetailSheet: View {
    @Environment(AppServices.self) private var services
    let line: LedgerLine
    let title: String
    let subtitle: String?
    let imageURL: URL?
    let directionText: String
    let productKindText: String
    let variantText: String?
    let moneySummary: String?
    let amountColor: Color
    let availableMarkActions: [TransactionMarkAction]
    let onMarkAs: (TransactionMarkAction) -> Void
    let onEdit: () -> Void
    var onViewCard: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var showMarkAsPicker = false
    @State private var auraColors: [Color] = []

    private var resolvedAuraColors: [Color] {
        if auraColors.count >= 3 { return Array(auraColors.prefix(3)) }
        if let first = auraColors.first { return [first, first.opacity(0.74), first.opacity(0.52)] }
        return [Color(red: 0.50, green: 0.60, blue: 0.74), Color(red: 0.63, green: 0.52, blue: 0.76), Color(red: 0.72, green: 0.60, blue: 0.68)]
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                heroSection
                actionButtonsRow
                overviewCard
                metadataCard
            }
            .padding(.horizontal, 12)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .background(sheetBackground)
        .scrollContentBackground(.hidden)
        .presentationCornerRadius(20)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .confirmationDialog("Mark Transaction As", isPresented: $showMarkAsPicker, titleVisibility: .visible) {
            ForEach(availableMarkActions) { action in
                Button(action.title) { onMarkAs(action) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var sheetBackground: some View {
        ZStack {
            (colorScheme == .dark ? Color.black : Color.white)
            resolvedAuraColors[0].opacity(colorScheme == .dark ? 0.30 : 0.16)
            LinearGradient(
                colors: [
                    resolvedAuraColors[1].opacity(colorScheme == .dark ? 0.24 : 0.14),
                    .clear,
                    resolvedAuraColors[2].opacity(colorScheme == .dark ? 0.24 : 0.14),
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
        }
        .ignoresSafeArea()
    }

    private var heroSection: some View {
        VStack(spacing: 10) {
            imageHero
                .padding(.top, 4)
                .padding(.horizontal, 6)
            titleBlock
        }
    }

    private var imageHero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(LinearGradient(
                    colors: resolvedAuraColors.map { $0.opacity(colorScheme == .dark ? 0.52 : 0.36) },
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .frame(maxWidth: .infinity)
                .frame(height: 280)
                .blur(radius: colorScheme == .dark ? 40 : 32)
                .scaleEffect(1.05)

            Group {
                if let imageURL {
                    CachedAsyncImage(url: imageURL, targetSize: CGSize(width: 360, height: 500)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .onAppear { extractAuraColors(from: image) }
                    } placeholder: {
                        placeholderArtwork
                    }
                } else {
                    placeholderArtwork
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 280)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.16 : 0.22), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity)
    }

    private var placeholderArtwork: some View {
        Color(uiColor: .tertiarySystemFill)
            .overlay {
                Image(systemName: "photo")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
    }

    private var titleBlock: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                detailChip(text: directionText)
                detailChip(text: "Qty \(line.quantity)")
                if let variantText, !variantText.isEmpty {
                    detailChip(text: variantText)
                }
            }
            if let moneySummary, !moneySummary.isEmpty {
                Text(moneySummary)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(amountColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassCardStyle(cornerRadius: 20, interactive: false)
    }

    private var metadataCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            detailRow(label: "Date", value: line.occurredAt.formatted(date: .abbreviated, time: .omitted))
            detailRow(label: "Item", value: productKindText)
            if let unitPrice = line.unitPrice {
                let unit = unitPrice.formatted(.currency(code: line.currencyCode).precision(.fractionLength(2)))
                detailRow(label: "Unit Price", value: unit)
            }
            if let counterparty = cleaned(line.counterparty) {
                detailRow(label: "Counterparty", value: counterparty)
            }
            if let notes = cleaned(line.lineDescription), notes != title {
                detailRow(label: "Notes", value: notes)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassCardStyle(cornerRadius: 20, interactive: false)
    }

    private var actionButtonsRow: some View {
        HStack(spacing: 10) {
            Button { showMarkAsPicker = true } label: {
                actionBody(title: "Mark As", systemImage: "tag", tint: services.theme.accentColor)
            }
            .buttonStyle(.plain)

            Button(action: onEdit) {
                actionBody(title: "Edit", systemImage: "pencil", tint: Color(red: 0.36, green: 0.61, blue: 0.97))
            }
            .buttonStyle(.plain)

            if let onViewCard {
                Button(action: onViewCard) {
                    actionBody(title: "View Card", systemImage: "rectangle.portrait.on.rectangle.portrait.fill", tint: Color(red: 0.95, green: 0.62, blue: 0.04))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func actionBody(title: String, systemImage: String, tint: Color) -> some View {
        VStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .glassCardStyle(cornerRadius: 14, interactive: false)
        .accessibilityLabel(title)
    }

    private func detailChip(text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule(style: .continuous).fill(Color.secondary.opacity(colorScheme == .dark ? 0.16 : 0.12)))
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
    }

    @MainActor
    private func extractAuraColors(from image: Image) {
        guard auraColors.isEmpty else { return }
        let renderer = ImageRenderer(content: image.resizable().frame(width: 44, height: 62))
        renderer.scale = 1
        guard let uiImage = renderer.uiImage else { return }
        Task.detached(priority: .utility) {
            let colors = uiImage.transactionAuraColors(maxColors: 3)
            guard !colors.isEmpty else { return }
            await MainActor.run { self.auraColors = colors }
        }
    }

    private func cleaned(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

private extension UIImage {
    func transactionAuraColors(maxColors: Int) -> [Color] {
        guard maxColors > 0, let cgImage else { return [] }
        let sampleWidth = 44, sampleHeight = 62, bytesPerPixel = 4
        let bytesPerRow = sampleWidth * bytesPerPixel
        var raw = [UInt8](repeating: 0, count: sampleHeight * bytesPerRow)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: &raw, width: sampleWidth, height: sampleHeight,
                                     bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return [] }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))
        struct AuraBin: Hashable { let r, g, b: Int }
        var histogram: [AuraBin: Double] = [:]
        let step = 32.0
        for y in 0..<sampleHeight {
            for x in 0..<sampleWidth {
                let i = y * bytesPerRow + x * bytesPerPixel
                let r = Double(raw[i]), g = Double(raw[i+1]), b = Double(raw[i+2]), a = Double(raw[i+3]) / 255.0
                guard a > 0.6 else { continue }
                let maxC = max(r, g, b) / 255.0, minC = min(r, g, b) / 255.0
                let saturation = maxC == 0 ? 0.0 : (maxC - minC) / maxC
                let brightness = maxC
                guard saturation >= 0.22, brightness >= 0.18, brightness <= 0.94 else { continue }
                let bin = AuraBin(r: Int(floor(r/step)), g: Int(floor(g/step)), b: Int(floor(b/step)))
                histogram[bin, default: 0] += 0.3 + saturation * 1.6 + brightness * 0.2
            }
        }
        let sortedBins = histogram.sorted { $0.value > $1.value }.map(\.key)
        guard !sortedBins.isEmpty else { return [] }
        var selected: [SIMD3<Double>] = []
        for bin in sortedBins {
            let c = SIMD3<Double>((Double(bin.r)+0.5)*step/255, (Double(bin.g)+0.5)*step/255, (Double(bin.b)+0.5)*step/255)
            if selected.allSatisfy({ existing in let d = c - existing; return sqrt(d.x*d.x+d.y*d.y+d.z*d.z) > 0.22 }) {
                selected.append(c)
            }
            if selected.count == maxColors { break }
        }
        if selected.isEmpty, let f = sortedBins.first {
            selected = [SIMD3<Double>((Double(f.r)+0.5)*step/255, (Double(f.g)+0.5)*step/255, (Double(f.b)+0.5)*step/255)]
        }
        if selected.count == 1, let f = selected.first { selected += [f*0.86, f*0.72] }
        else if selected.count == 2 { selected.append(selected[1]*0.7 + selected[0]*0.3) }
        return selected.prefix(maxColors).map { Color(red: $0.x, green: $0.y, blue: $0.z) }
    }
}
