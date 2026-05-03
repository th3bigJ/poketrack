import SwiftUI

struct TradeDetailView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    let tradeID: UUID

    @State private var tradeWithItems: TradeWithItems?
    @State private var myProfile: SocialProfile?
    @State private var theirProfile: SocialProfile?
    @State private var isLoading = false
    @State private var isMutating = false
    @State private var errorMessage: String?
    @State private var showConfirmDecline = false
    @State private var showConfirmCancel = false
    @State private var showConfirmComplete = false

    private var currentUserID: UUID? {
        if case .signedIn(let uid, _) = services.socialAuth.authState { return uid }
        return nil
    }

    private var trade: Trade? { tradeWithItems?.trade }

    private var isInitiator: Bool {
        guard let uid = currentUserID, let t = trade else { return false }
        return t.initiatorID == uid
    }

    var body: some View {
        Group {
            if isLoading && tradeWithItems == nil {
                ProgressView("Loading trade…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let tradeWithItems {
                tradeContent(tradeWithItems)
            } else {
                ContentUnavailableView(
                    "Trade Not Found",
                    systemImage: "exclamationmark.triangle",
                    description: Text("This trade could not be loaded.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .navigationTitle("Trade")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .alert("Error", isPresented: .constant(errorMessage != nil), actions: {
            Button("OK") { errorMessage = nil }
        }, message: {
            Text(errorMessage ?? "")
        })
        .confirmationDialog("Decline this trade?", isPresented: $showConfirmDecline, titleVisibility: .visible) {
            Button("Decline", role: .destructive) {
                Task { await performCancel() }
            }
        }
        .confirmationDialog("Cancel this trade?", isPresented: $showConfirmCancel, titleVisibility: .visible) {
            Button("Cancel Trade", role: .destructive) {
                Task { await performCancel() }
            }
        }
        .confirmationDialog("Mark this trade as complete?", isPresented: $showConfirmComplete, titleVisibility: .visible) {
            Button("Mark Complete") {
                Task { await performComplete() }
            }
        }
    }

    private func tradeContent(_ twi: TradeWithItems) -> some View {
        let resolvedUID = currentUserID ?? UUID()
        let myItems = twi.myItems(currentUserID: resolvedUID)
        let theirItems = twi.theirItems(currentUserID: resolvedUID)
        let myCash = twi.myCash(currentUserID: resolvedUID)
        let theirCash = twi.theirCash(currentUserID: resolvedUID)

        return ScrollView {
            VStack(spacing: 16) {
                statusBanner(twi.trade.status)

                HStack(alignment: .top, spacing: 12) {
                    tradeSideColumn(
                        label: "My Side",
                        profile: myProfile,
                        items: myItems,
                        cash: myCash
                    )

                    Rectangle()
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: 1)

                    tradeSideColumn(
                        label: "Their Side",
                        profile: theirProfile,
                        items: theirItems,
                        cash: theirCash
                    )
                }
                .padding(.horizontal, 16)

                actionButtons(twi)
                    .padding(.horizontal, 16)
            }
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
    }

    private func statusBanner(_ status: TradeStatus) -> some View {
        let (color, message) = statusBannerInfo(status)
        return HStack(spacing: 8) {
            TradeStatusBadge(status: status)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(color.opacity(0.1))
    }

    private func statusBannerInfo(_ status: TradeStatus) -> (Color, String) {
        switch status {
        case .pending:
            return (Color(hex: "E8B84B"), isInitiator ? "Waiting for their response" : "Awaiting your response")
        case .countered:
            return (Color(hex: "E8934B"), isInitiator ? "Review their counter-offer" : "Counter-offer sent")
        case .accepted:
            return (Color(hex: "52C97C"), "Trade accepted — mark complete when cards are exchanged")
        case .complete:
            return (Color(hex: "52C97C"), "Trade complete")
        case .cancelled:
            return (Color(hex: "E05252"), "Trade cancelled")
        }
    }

    private func tradeSideColumn(label: String, profile: SocialProfile?, items: [TradeItem], cash: Double) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(.secondary)
                if let profile {
                    Text(profile.displayName ?? "@\(profile.username)")
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }

            if items.isEmpty {
                Text("No cards")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                ForEach(items) { item in
                    TradeCardRow(item: item, cardLoader: { id in await services.cardData.loadCard(masterCardId: id) })
                }
            }

            if cash > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "sterlingsign.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "52C97C"))
                    Text("£\(cash, format: .number.precision(.fractionLength(2)))")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: "52C97C"))
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func actionButtons(_ twi: TradeWithItems) -> some View {
        let status = twi.trade.status

        VStack(spacing: 10) {
            if status == .pending && !isInitiator {
                // Receiver sees: Accept, Counter, Decline
                Button { Task { await performAccept() } } label: {
                    Label("Accept Trade", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(TradeActionButtonStyle(color: Color(hex: "52C97C"), isBusy: isMutating))

                NavigationLink(value: SocialDestination.tradeBuilder(
                    receiverID: twi.trade.initiatorID,
                    theirCards: twi.initiatorItems,
                    myCards: twi.receiverItems,
                    existingTradeID: twi.trade.id,
                    originalTrade: twi.trade
                )) {
                    Label("Counter Offer", systemImage: "arrow.left.arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(TradeActionButtonStyle(color: Color(hex: "E8B84B"), isBusy: false))

                Button { showConfirmDecline = true } label: {
                    Label("Decline", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(TradeActionButtonStyle(color: Color(hex: "E05252"), isBusy: isMutating))

            } else if status == .pending && isInitiator {
                Button { showConfirmCancel = true } label: {
                    Label("Cancel Trade", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(TradeActionButtonStyle(color: Color(hex: "E05252"), isBusy: isMutating))

            } else if status == .countered && !isInitiator {
                // Person who received the counter (original initiator) can accept, counter again, or decline
                Button { Task { await performAccept() } } label: {
                    Label("Accept Counter", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(TradeActionButtonStyle(color: Color(hex: "52C97C"), isBusy: isMutating))

                NavigationLink(value: SocialDestination.tradeBuilder(
                    receiverID: twi.trade.receiverID,
                    theirCards: twi.receiverItems,
                    myCards: twi.initiatorItems,
                    existingTradeID: twi.trade.id,
                    originalTrade: twi.trade
                )) {
                    Label("Counter Again", systemImage: "arrow.left.arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(TradeActionButtonStyle(color: Color(hex: "E8B84B"), isBusy: false))

                Button { showConfirmDecline = true } label: {
                    Label("Decline", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(TradeActionButtonStyle(color: Color(hex: "E05252"), isBusy: isMutating))

            } else if status == .countered && isInitiator {
                Button { showConfirmCancel = true } label: {
                    Label("Cancel Trade", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(TradeActionButtonStyle(color: Color(hex: "E05252"), isBusy: isMutating))

            } else if status == .accepted {
                Button { showConfirmComplete = true } label: {
                    Label("Mark Complete", systemImage: "checkmark.seal.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(TradeActionButtonStyle(color: Color(hex: "52C97C"), isBusy: isMutating))

                Button { showConfirmCancel = true } label: {
                    Label("Cancel Trade", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(TradeActionButtonStyle(color: Color(hex: "E05252"), isBusy: isMutating))
            }
        }
        .disabled(isMutating)
    }

    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            tradeWithItems = try await services.trade.fetchTrade(id: tradeID)
            if let twi = tradeWithItems, let uid = currentUserID {
                let theirID = twi.counterpartID(currentUserID: uid)
                async let theirFetch = services.socialProfile.fetchProfile(id: theirID)
                async let myFetch = services.socialProfile.fetchMyProfile()
                theirProfile = try await theirFetch
                myProfile = try await myFetch
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performAccept() async {
        isMutating = true
        defer { isMutating = false }
        do {
            try await services.trade.acceptTrade(id: tradeID)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performCancel() async {
        isMutating = true
        defer { isMutating = false }
        do {
            try await services.trade.cancelTrade(id: tradeID)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performComplete() async {
        isMutating = true
        defer { isMutating = false }
        do {
            try await services.trade.completeTrade(id: tradeID)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - TradeCardRow

private struct TradeCardRow: View {
    let item: TradeItem
    let cardLoader: (String) async -> Card?

    @State private var card: Card?

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                if let imageURLString = card?.imageLowSrc {
                    CachedAsyncImage(url: AppConfiguration.imageURL(relativePath: imageURLString)) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        shimmer
                    }
                } else {
                    shimmer
                }
            }
            .frame(width: 36, height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                Text(card?.cardName ?? item.cardID)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if item.variantKey != "normal" {
                    Text(item.variantKey)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                if item.quantity > 1 {
                    Text("×\(item.quantity)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(hex: "E8B84B"))
                }
            }
        }
        .task { card = await cardLoader(item.cardID) }
    }

    private var shimmer: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.white.opacity(0.05))
    }
}

// MARK: - Button Style

private struct TradeActionButtonStyle: ButtonStyle {
    let color: Color
    let isBusy: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(isBusy ? Color.secondary : color)
            .padding(.vertical, 12)
            .background(
                color.opacity(configuration.isPressed ? 0.18 : 0.12),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(color.opacity(0.3), lineWidth: 1)
            }
    }
}
