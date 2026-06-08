import SwiftUI

struct MutualTradeView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Binding var navigationPath: NavigationPath

    let sessionID: UUID
    let otherUserID: UUID
    let otherUsername: String

    @State private var session: TradeSession?
    @State private var otherProfile: SocialProfile?
    @State private var myRole: SessionRole?
    @State private var isLoading = true
    @State private var isSubmittingOffer = false
    @State private var isAccepting = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    @State private var myOfferingCards: [NewTradeItemInput] = []
    @State private var myWantingCards: [NewTradeItemInput] = []
    @State private var myCashText: String = ""
    @State private var isMyOfferingPickerPresented = false
    @State private var isMyWantingPickerPresented = false

    private var currentUserID: UUID {
        if case .signedIn(let id, _) = services.socialAuth.authState { return id }
        return UUID()
    }

    private var myOfferSubmitted: Bool {
        guard let session, let myRole else { return false }
        return myRole == .initiator ? session.initiatorOfferSubmitted : session.participantOfferSubmitted
    }

    private var theirOfferSubmitted: Bool {
        guard let session, let myRole else { return false }
        return myRole == .initiator ? session.participantOfferSubmitted : session.initiatorOfferSubmitted
    }

    private var myAccepted: Bool {
        guard let session, let myRole else { return false }
        return myRole == .initiator ? session.initiatorAccepted : session.participantAccepted
    }

    private var theirAccepted: Bool {
        guard let session, let myRole else { return false }
        return myRole == .initiator ? session.participantAccepted : session.initiatorAccepted
    }

    private var theirOfferData: SessionOfferData? {
        guard let session, let myRole else { return nil }
        return myRole == .initiator ? session.participantData : session.initiatorData
    }

    private var phase: TradePhase {
        guard let session else { return .loading }
        if session.status == "completed" { return .completed }
        if session.status == "cancelled" { return .cancelled }
        if session.status == "executing" || (myAccepted && theirAccepted) { return .executing }
        if myAccepted { return .acceptedWaiting }
        if myOfferSubmitted && theirOfferSubmitted { return .review }
        if myOfferSubmitted { return .waitingForThem }
        return .fillingOffer
    }

    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading trade session…")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                content
            }
        }
        .bindrPageBackground()
        .navigationTitle("Mutual Trade")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .task(id: session?.updatedAt) { await startPolling() }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .alert("Success", isPresented: .constant(successMessage != nil)) {
            Button("Done") {
                successMessage = nil
                if navigationPath.count > 1 {
                    navigationPath.removeLast(navigationPath.count)
                } else {
                    dismiss()
                }
            }
        } message: { Text(successMessage ?? "") }
        .sheet(isPresented: $isMyOfferingPickerPresented) {
            TradeCardPickerView(
                ownerUserID: currentUserID,
                navigationTitle: "Cards I'm Giving"
            ) { selected in
                for item in selected {
                    if !myOfferingCards.contains(where: { $0.cardID == item.cardID }) {
                        myOfferingCards.append(item)
                    }
                }
            }
            .environment(services)
        }
        .sheet(isPresented: $isMyWantingPickerPresented) {
            TradeCardPickerView(
                ownerUserID: otherUserID,
                navigationTitle: "Cards I Want"
            ) { selected in
                for item in selected {
                    if !myWantingCards.contains(where: { $0.cardID == item.cardID }) {
                        myWantingCards.append(item)
                    }
                }
            }
            .environment(services)
        }
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(spacing: 20) {
                profileHeader
                statusBanner
                if phase == .fillingOffer {
                    myOfferForm
                } else if phase == .waitingForThem {
                    myOfferSummary
                    Divider()
                    waitingForThemView
                } else if phase == .review {
                    myOfferSummary
                    Divider()
                    theirOfferSummary
                    Divider()
                    reviewAndAccept
                } else if phase == .acceptedWaiting {
                    myOfferSummary
                    Divider()
                    theirOfferSummary
                    Divider()
                    acceptedWaitingView
                } else if phase == .executing {
                    executingView
                } else if phase == .completed {
                    completedView
                } else if phase == .cancelled {
                    cancelledView
                }
            }
            .padding(.vertical, 16)
        }
    }

    // MARK: - Profile Header

    private var profileHeader: some View {
        VStack(spacing: 8) {
            if let otherProfile {
                ProfileAvatarView(profile: otherProfile, size: 64)
                    .overlay(Circle().stroke(Color.primary.opacity(0.10), lineWidth: 1))
                Text(otherProfile.displayName ?? otherProfile.username)
                    .font(.title3.weight(.bold))
                Text("@\(otherProfile.username)")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text("@\(otherUsername)")
                    .font(.title3.weight(.bold))
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Status Banner

    private var statusBanner: some View {
        let (icon, text, color): (String, String, Color) = {
            switch phase {
            case .loading: return ("arrow.triangle.2.circlepath", "Loading…", .gray)
            case .fillingOffer: return ("square.and.pencil", "Fill in your offer", .blue)
            case .waitingForThem: return ("clock", "Waiting for them to submit their offer…", .orange)
            case .review: return ("hand.raised", "Review the trade", .green)
            case .acceptedWaiting: return ("clock", "Waiting for them to accept…", .orange)
            case .executing: return ("arrow.triangle.2.circlepath", "Executing trade…", .blue)
            case .completed: return ("checkmark.circle.fill", "Trade completed!", .green)
            case .cancelled: return ("xmark.circle.fill", "Trade cancelled", .red)
            }
        }()
        return Label(text, systemImage: icon)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
    }

    // MARK: - My Offer Form

    private var myOfferForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Cards I'm Giving")
            if myOfferingCards.isEmpty {
                Text("No cards selected")
                    .font(.system(size: 13)).foregroundStyle(.secondary).italic()
            } else {
                ForEach(myOfferingCards) { item in
                    BuilderCardRow(item: item, cardLoader: { id in await services.cardData.loadCard(masterCardId: id) })
                }
                .onDelete { myOfferingCards.remove(atOffsets: $0) }
            }
            Button {
                isMyOfferingPickerPresented = true
            } label: {
                Label("Add Cards", systemImage: "plus.circle")
                    .font(.system(size: 14))
            }

            sectionTitle("Cards I Want")
            if myWantingCards.isEmpty {
                Text("No cards selected")
                    .font(.system(size: 13)).foregroundStyle(.secondary).italic()
            } else {
                ForEach(myWantingCards) { item in
                    BuilderCardRow(item: item, cardLoader: { id in await services.cardData.loadCard(masterCardId: id) })
                }
                .onDelete { myWantingCards.remove(atOffsets: $0) }
            }
            Button {
                isMyWantingPickerPresented = true
            } label: {
                Label("Add Their Available Cards", systemImage: "plus.circle")
                    .font(.system(size: 14))
            }

            HStack {
                Text("Cash I'm Adding")
                    .font(.system(size: 14))
                Spacer()
                HStack(spacing: 4) {
                    Text(services.priceDisplay.currency.symbol)
                        .font(.system(size: 14)).foregroundStyle(.secondary)
                    TextField("0.00", text: $myCashText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.system(size: 14))
                        .frame(width: 90)
                }
            }

            Button {
                Task { await submitMyOffer() }
            } label: {
                HStack {
                    if isSubmittingOffer { ProgressView().tint(.white) }
                    Text("Submit Offer")
                        .font(.system(size: 17, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(myOfferingCards.isEmpty && myWantingCards.isEmpty ? Color.gray : Color.primary)
                )
            }
            .disabled(isSubmittingOffer || (myOfferingCards.isEmpty && myWantingCards.isEmpty))
            .padding(.top, 8)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - My Offer Summary (read-only after submit)

    private var myOfferSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("My Offer")
            offerDataView(
                offering: myOfferingCards,
                wanting: myWantingCards,
                cash: parsedCash(myCashText)
            )
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Their Offer Summary

    private var theirOfferSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Their Offer")
            if let data = theirOfferData {
                offerDataView(
                    offering: data.offering.map { NewTradeItemInput(cardID: $0.cardID, variantKey: $0.variantKey, quantity: $0.quantity) },
                    wanting: data.wanting.map { NewTradeItemInput(cardID: $0.cardID, variantKey: $0.variantKey, quantity: $0.quantity) },
                    cash: data.cash
                )
            } else {
                Text("No offer data")
                    .font(.system(size: 13)).foregroundStyle(.secondary).italic()
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Waiting Views

    private var waitingForThemView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Waiting for @\(otherUsername) to submit their offer…")
                .font(.system(size: 14)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Cancel Trade", role: .destructive) {
                Task { await cancelTrade() }
            }
            .font(.system(size: 14, weight: .semibold))
            .padding(.top, 8)
        }
        .padding(.horizontal, 16)
    }

    private var acceptedWaitingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Waiting for @\(otherUsername) to accept…")
                .font(.system(size: 14)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 16)
    }

    private var executingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Finalizing trade…")
                .font(.system(size: 14)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
    }

    private var completedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("Trade Agreed!")
                .font(.title3.weight(.bold))
            Text("Confirm completion from Active trades once both sides have exchanged cards and cash.")
                .font(.system(size: 14)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 16)
    }

    private var cancelledView: some View {
        VStack(spacing: 12) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)
            Text("Trade Cancelled")
                .font(.title3.weight(.bold))
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Review + Accept

    private var reviewAndAccept: some View {
        VStack(spacing: 12) {
            Button {
                Task { await acceptTrade() }
            } label: {
                HStack {
                    if isAccepting { ProgressView().tint(.white) }
                    Text("Accept Trade")
                        .font(.system(size: 17, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.green))
            }
            .disabled(isAccepting)

            Button(role: .destructive) {
                Task { await cancelTrade() }
            } label: {
                Text("Deny Trade")
                    .font(.system(size: 15, weight: .semibold))
            }
            .disabled(isAccepting)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Shared Components

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 15, weight: .bold))
    }

    private func offerDataView(offering: [NewTradeItemInput], wanting: [NewTradeItemInput], cash: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if offering.isEmpty {
                Text("No cards offered").font(.system(size: 13)).foregroundStyle(.secondary).italic()
            } else {
                Text("Giving:").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                ForEach(offering) { item in
                    BuilderCardRow(item: item, cardLoader: { id in await services.cardData.loadCard(masterCardId: id) })
                }
            }
            if cash > 0 {
                Text("Cash: \(services.priceDisplay.currency.symbol)\(String(format: "%.2f", cash))")
                    .font(.system(size: 14, weight: .semibold))
            }
            if wanting.isEmpty {
                Text("No cards requested").font(.system(size: 13)).foregroundStyle(.secondary).italic()
            } else {
                Text("Wanting:").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                ForEach(wanting) { item in
                    BuilderCardRow(item: item, cardLoader: { id in await services.cardData.loadCard(masterCardId: id) })
                }
            }
        }
    }

    // MARK: - Actions

    private func submitMyOffer() async {
        isSubmittingOffer = true
        defer { isSubmittingOffer = false }
        do {
            let offering = myOfferingCards.map { SessionCardItem(cardID: $0.cardID, variantKey: $0.variantKey, quantity: $0.quantity) }
            let wanting = myWantingCards.map { SessionCardItem(cardID: $0.cardID, variantKey: $0.variantKey, quantity: $0.quantity) }
            session = try await services.tradeSession.submitOffer(
                sessionID: sessionID,
                offering: offering,
                wanting: wanting,
                cash: parsedCash(myCashText)
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func acceptTrade() async {
        isAccepting = true
        defer { isAccepting = false }
        do {
            session = try await services.tradeSession.acceptSession(sessionID: sessionID)
            // Check if both accepted now — if so, try to execute
            guard let session else { return }
            if session.isFullyAccepted {
                try await executeTrade()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func executeTrade() async throws {
        guard let currentSession = session, let myRole else { return }
        // Try to acquire the execution lock (only one client succeeds)
        guard try await services.tradeSession.acquireExecutionLock(sessionID: sessionID) else {
            // Other client got the lock — the poll will pick up the result
            return
        }

        let giveCards = myRole == .initiator ? currentSession.initiatorData.offering : currentSession.participantData.offering
        let receiveCards = myRole == .initiator ? currentSession.participantData.offering : currentSession.initiatorData.offering
        let giveCash = myRole == .initiator ? currentSession.initiatorData.cash : currentSession.participantData.cash
        let receiveCash = myRole == .initiator ? currentSession.participantData.cash : currentSession.initiatorData.cash

        // For the trade record: initiator = current user, receiver = other user
        // my give cards → initiatorCards (what I'm giving)
        // their give cards → receiverCards (what they're giving)
        let myGiveInputs = giveCards.map { NewTradeItemInput(cardID: $0.cardID, variantKey: $0.variantKey, quantity: $0.quantity) }
        let theirGiveInputs = receiveCards.map { NewTradeItemInput(cardID: $0.cardID, variantKey: $0.variantKey, quantity: $0.quantity) }

        let trade = try await services.trade.createTrade(
            receiverID: otherUserID,
            initiatorCards: myGiveInputs,
            receiverCards: theirGiveInputs,
            cashInitiator: giveCash,
            cashReceiver: receiveCash,
            initialStatus: .accepted
        )

        try await services.tradeSession.markCompleted(sessionID: sessionID, tradeRecordID: trade.id)
        session = try await services.tradeSession.fetchSession(id: sessionID)
        successMessage = "Trade agreed. Both traders still need to confirm completion after the exchange."
    }

    private func cancelTrade() async {
        do {
            try await services.tradeSession.cancelSession(sessionID: sessionID)
            session = try await services.tradeSession.fetchSession(id: sessionID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Load & Poll

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            session = try await services.tradeSession.fetchSession(id: sessionID)
            myRole = session?.myRole(userID: currentUserID)
            otherProfile = try await services.socialProfile.fetchProfile(id: otherUserID)
            // Pre-populate my offer data if I already submitted (e.g., returning from background)
            if let session, let myRole {
                let myData = myRole == .initiator ? session.initiatorData : session.participantData
                myOfferingCards = myData.offering.map { NewTradeItemInput(cardID: $0.cardID, variantKey: $0.variantKey, quantity: $0.quantity) }
                myWantingCards = myData.wanting.map { NewTradeItemInput(cardID: $0.cardID, variantKey: $0.variantKey, quantity: $0.quantity) }
                myCashText = myData.cash > 0 ? String(format: "%.2f", myData.cash) : ""
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startPolling() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !isLoading else { continue }
            do {
                if let refreshed = try await services.tradeSession.fetchSession(id: sessionID) {
                    let oldPhase = phase
                    session = refreshed
                    let newPhase = phase
                    // If we just came back from acceptedWaiting → both accepted, execute
                    if oldPhase == .acceptedWaiting, newPhase == .executing || (refreshed.isFullyAccepted) {
                        if refreshed.isFullyAccepted {
                            try await executeTrade()
                        }
                    }
                }
            } catch {
                // silent poll failure
            }
        }
    }

    private func parsedCash(_ text: String) -> Double {
        Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }
}

private enum TradePhase {
    case loading
    case fillingOffer
    case waitingForThem
    case review
    case acceptedWaiting
    case executing
    case completed
    case cancelled
}
