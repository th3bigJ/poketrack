import SwiftUI

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

    @Environment(\.colorScheme) private var colorScheme
    @State private var showMarkAsPicker = false

    private var cardBackground: Color {
        colorScheme == .dark ? Color.black : Color(uiColor: .systemBackground)
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }

    private var imageSurfaceBackground: Color {
        colorScheme == .dark ? .black : .white
    }

    private var glassButtonBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04)
    }

    private var glassButtonBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                imageCard
                actionButtonsRow
                overviewCard
                metadataCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .background(cardBackground.ignoresSafeArea())
        .presentationBackground(cardBackground)
        .presentationCornerRadius(20)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .confirmationDialog("Mark Transaction As", isPresented: $showMarkAsPicker, titleVisibility: .visible) {
            ForEach(availableMarkActions) { action in
                Button(action.title) {
                    onMarkAs(action)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var imageCard: some View {
        Group {
            if let imageURL {
                CachedAsyncImage(url: imageURL, targetSize: CGSize(width: 360, height: 500)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } placeholder: {
                    placeholderArtwork
                }
            } else {
                placeholderArtwork
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 320)
        .background(imageSurfaceBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var placeholderArtwork: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(.thinMaterial)
            .overlay {
                Image(systemName: "photo")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
    }

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

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
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
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
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    private var actionButtonsRow: some View {
        HStack(spacing: 10) {
            Button {
                showMarkAsPicker = true
            } label: {
                transactionActionBody(
                    title: "Mark As",
                    systemImage: "tag",
                    tint: services.theme.accentColor
                )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)

            Button(action: onEdit) {
                transactionActionBody(
                    title: "Edit",
                    systemImage: "pencil",
                    tint: Color(red: 0.36, green: 0.61, blue: 0.97)
                )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
        }
    }

    private func transactionActionBody(title: String, systemImage: String, tint: Color) -> some View {
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
        .frame(height: 72)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(glassButtonBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(glassButtonBorder, lineWidth: 1)
                )
        }
        .accessibilityLabel(title)
    }

    private func detailChip(text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(colorScheme == .dark ? 0.16 : 0.12))
            )
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

    private func cleaned(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}
