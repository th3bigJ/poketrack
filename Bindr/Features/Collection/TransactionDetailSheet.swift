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
            let colors = uiImage.bindrAuraColors(maxColors: 3)
            guard !colors.isEmpty else { return }
            await MainActor.run { self.auraColors = colors }
        }
    }

    private func cleaned(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}
