import SwiftUI
import SwiftData

/// Root page for the More tab.
/// Styled using standard iOS grouped List elements with colorful glyph backdrops for a premium native look and feel.
struct MoreView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.bindrAccent) private var accent
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @Binding var navigationPath: NavigationPath

    @State private var showProfile = false
    @State private var showCreateBinder = false
    @State private var profilePath = NavigationPath()
    @State private var profile: SocialProfile? = nil
    @State private var acceptedFriendCount: Int? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                MoreBrandHeroCard()

                VStack(spacing: BindrSpacing.xl) {
                        MoreMenuSection(title: "Collection Tools") {
                            MoreMenuRow(
                                title: "Binders",
                                systemImage: "books.vertical.fill",
                                color: .blue,
                                destination: .binders
                            )
                            MoreMenuRow(
                                title: "Deck Builder",
                                systemImage: "rectangle.on.rectangle.angled",
                                color: .green,
                                destination: .decks
                            )
                            MoreMenuRow(
                                title: "Activity Ledger",
                                systemImage: "list.bullet.rectangle.fill",
                                color: .orange,
                                destination: .transactions
                            )
                            MoreMenuRow(
                                title: "Local Trade",
                                systemImage: "scalemass.fill",
                                color: BindrPalette.binderGold,
                                destination: .tradeCalculator
                            )
                            MoreMenuRow(
                                title: "Grading Opportunities",
                                systemImage: "chart.line.uptrend.xyaxis",
                                color: .red,
                                destination: .gradingOpportunities
                            )
                        }

                        MoreMenuSection(title: "App Preferences") {
                            MoreMenuRow(
                                title: "Themes & Colors",
                                systemImage: "paintpalette.fill",
                                color: .purple,
                                destination: .themes
                            )
                            MoreMenuRow(
                                title: "Settings",
                                systemImage: "gearshape.fill",
                                color: .gray,
                                destination: .account
                            )
                        }

                        MoreMenuSection(title: "Legal & Support") {
                            MoreMenuRow(
                                title: "Legal Disclaimer",
                                systemImage: "doc.text.magnifyingglass",
                                color: .gray,
                                destination: .legalDisclaimer
                            )

                            MoreMenuRow(
                                title: "Privacy Policy",
                                systemImage: "hand.raised.fill",
                                color: .blue,
                                destination: .privacyPolicy
                            )

                            MoreMenuActionRow(
                                title: "Contact Us",
                                systemImage: "envelope.fill",
                                color: .teal
                            ) {
                                openURL(BindrSupport.contactMailURL)
                            }
                        }

                        MoreMenuSection(title: "Connect with us") {
                            MoreSocialLinksRow()
                        }
                    }
                    .padding(.horizontal, BindrSpacing.lg)
                    .padding(.top, BindrSpacing.lg)
                }
                .padding(.bottom, 120)
        }
        .bindrPageBackground()
        .tint(.primary)
        .toolbar(.hidden, for: .navigationBar) // Hides native squircle toolbar entirely
        .task {
            await loadProfileIfPossible()
        }
        .onChange(of: services.socialAuth.authState) { _, _ in
            Task { await loadProfileIfPossible() }
        }
        .popover(isPresented: $showProfile) {
            NavigationStack(path: $profilePath) {
                AccountProfileView(
                    navigationPath: $profilePath,
                    isPresented: $showProfile,
                    externalProfile: $profile
                )
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .navigationDestination(for: SideMenuPage.self) { page in
            switch page {
            case .account:
                SettingsView()
                    .environment(services)
            case .social:
                SocialRootView()
                    .environment(services)
            case .binders:
                BindersRootView(showCreateSheet: $showCreateBinder)
            case .decks:
                DecksRootView()
            case .transactions:
                TransactionsView()
            case .tradeCalculator:
                TradeCalculatorView()
            case .themes:
                ThemesView()
            case .gradingOpportunities:
                GradingOpportunitiesView()
            case .myAccount:
                MyAccountPrivacyView()
                    .environment(services)
            case .subscription:
                PremiumSettingsPage()
                    .environment(services)
            case .backupRestore:
                BackupRestoreSettingsPage()
                    .environment(services)
            case .libraryStorage:
                LibraryStorageSettingsPage()
                    .environment(services)
            case .legalDisclaimer:
                DisclaimerView()
            case .privacyPolicy:
                PrivacyPolicyView()
            }
        }
    }

    private func loadProfileIfPossible() async {
        profile = services.socialProfile.currentProfile
        guard services.socialAuth.isSignedIn else {
            acceptedFriendCount = nil
            return
        }
        if profile == nil {
            profile = try? await services.socialProfile.fetchMyProfile()
        }
        if let profile {
            acceptedFriendCount = try? await services.socialFriend.fetchAcceptedFriendCount(for: profile.id)
        } else {
            acceptedFriendCount = nil
        }
    }
}

private struct MoreBrandHeroCard: View {
    var body: some View {
        BindrBrandLogoView(maxWidth: 190)
            .frame(maxWidth: .infinity)
            .padding(.top, BindrSpacing.sm)
            .padding(.bottom, BindrSpacing.md)
            .padding(.horizontal, BindrSpacing.lg)
    }
}

/// Themed hero card at the top of the More tab.
///
/// Pulls `themeColor` from `profile.avatarBackgroundColor` — the exact same
/// source used by `MyProfileView` and `FriendProfileView` — so changing the
/// profile's avatar background colour is reflected here automatically, keeping
/// the More tab in sync with the rest of the social UI.
private struct MoreProfileHeroCard: View {
    let profile: SocialProfile?
    let friendCountOverride: Int?

    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme

    /// Identical derivation to `MyProfileView.themeColor` — single source of truth.
    private var themeColor: Color {
        if let hex = profile?.avatarBackgroundColor, !hex.isEmpty {
            return Color(hex: hex)
        }
        return Color(hex: "E8B84B") // gold — matches MyProfileView / FriendProfileView fallback
    }

    private var displayName: String {
        cleaned(profile?.displayName) ?? profile?.username ?? "Create your profile"
    }

    private var subtitle: String? {
        cleaned(profile?.bio)
            ?? (profile == nil
                ? (services.socialAuth.isSignedIn
                    ? "Tap to edit your profile"
                    : "Sign in to sync your social profile.")
                : nil)
    }

    private var roleTitles: [String] {
        (profile?.profileRoles ?? []).map { role in
            switch role {
            case "collector": return "Collector"
            case "tcg_player": return "TCG Player"
            default: return role.replacingOccurrences(of: "_", with: " ").capitalized
            }
        }
    }

    private var friendCount: Int { friendCountOverride ?? profile?.friendCount ?? 0 }
    private var cardCount: Int { profile?.collectionCardCount ?? 0 }
    private var deckCount: Int { profile?.collectionDeckCount ?? 0 }
    private var binderCount: Int { profile?.collectionBinderCount ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: BindrSpacing.md) {
            HStack(alignment: .top, spacing: BindrSpacing.md) {
                avatarView(size: 72)
 
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .center, spacing: BindrSpacing.sm) {
                        Text(displayName)
                            .font(.system(size: 20, weight: .black))
                            .tracking(-0.3)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if let profile {
                            PremiumBadgeView(profile: profile, size: 14)
                        }
                    }
                    if let profile {
                        Text("@\(profile.username)")
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.medium)
                            .foregroundStyle(Color.secondary.opacity(0.8))
                    }
                }
 
                Spacer()
            }
 
            if !roleTitles.isEmpty {
                HStack(spacing: BindrSpacing.sm) {
                    ForEach(roleTitles, id: \.self) { title in
                        rolePill(title)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let subtitle {
                if profile != nil {
                    Text(subtitle)
                        .font(.system(size: 13, weight: .regular))
                        .lineSpacing(4)
                        .foregroundStyle(Color.primary.opacity(0.85))
                } else {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .lineSpacing(3)
                        .foregroundStyle(.secondary)
                }
            }
 
            HStack(spacing: 0) {
                statBlock(value: "\(cardCount)", label: cardCount == 1 ? "Card" : "Cards")
                
                Divider()
                    .frame(height: 24)
                    .background(Color.primary.opacity(0.08))
                
                statBlock(value: "\(deckCount)", label: deckCount == 1 ? "Deck" : "Decks")
                
                Divider()
                    .frame(height: 24)
                    .background(Color.primary.opacity(0.08))
                
                statBlock(value: "\(binderCount)", label: binderCount == 1 ? "Binder" : "Binders")
                
                Divider()
                    .frame(height: 24)
                    .background(Color.primary.opacity(0.08))
                
                statBlock(value: "\(friendCount)", label: friendCount == 1 ? "Friend" : "Friends")
            }
            .padding(.vertical, 4)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
        }
        .padding(BindrSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(profileBackdrop)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.06), lineWidth: 1)
        }
        .overlay(alignment: .topTrailing) {
            favoriteCardPeek
        }
        .padding(.horizontal, BindrSpacing.lg)
    }

    private var profileBackdrop: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: themeColor.opacity(0.22), location: 0.30),
                    .init(color: themeColor.opacity(0.16), location: 0.50),
                    .init(color: themeColor.opacity(0.08), location: 0.72),
                    .init(color: themeColor.opacity(0.03), location: 0.88),
                    .init(color: .clear, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            LinearGradient(
                stops: [
                    .init(color: themeColor.opacity(0.18), location: 0.0),
                    .init(color: themeColor.opacity(0.06), location: 0.55),
                    .init(color: .clear, location: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    @ViewBuilder
    private var favoriteCardPeek: some View {
        if let profile, let url = profile.resolvedFavoriteCardImageURL {
            CachedAsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.gray.opacity(0.08)
            }
            .frame(width: 64, height: 90)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
            }
            .shadow(color: themeColor.opacity(0.45), radius: 10, x: 0, y: 6)
            .rotationEffect(.degrees(8))
            .opacity(0.85)
            .padding(.top, BindrSpacing.md)
            .padding(.trailing, BindrSpacing.lg)
            .allowsHitTesting(false)
        }
    }

    private func avatarView(size: CGFloat) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let profile {
                    ProfileAvatarView(profile: profile, size: size)
                } else {
                    Circle()
                        .fill(themeColor.gradient)
                        .frame(width: size, height: size)
                        .overlay {
                            Image(
                                systemName: services.socialAuth.isSignedIn
                                    ? "person.fill"
                                    : "person.crop.circle.badge.plus"
                            )
                            .font(.system(size: size * 0.40, weight: .semibold))
                            .foregroundStyle(.white)
                        }
                }
            }
            .clipShape(Circle())
            .shadow(color: themeColor.opacity(0.35), radius: 8, x: 0, y: 4)
            .overlay(Circle().stroke(themeColor, lineWidth: 2))
            .padding(2)
            .overlay(Circle().stroke(themeColor.opacity(0.2), lineWidth: 1))

            if services.socialAuth.isSignedIn {
                Circle()
                    .fill(Color(hex: "52C97C"))
                    .frame(width: 18, height: 18)
                    .overlay(Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 2.5))
                    .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
            }
        }
    }

    private func rolePill(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .bold))
            .tracking(1.0)
            .foregroundStyle(themeColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(themeColor.opacity(0.08))
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(themeColor.opacity(0.2), lineWidth: 1)
            }
    }

    private func statBlock(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 17, weight: .black))
                .foregroundStyle(.primary)
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(.secondary.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private func cleaned(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

private typealias MoreMenuSection = BindrMenuSection

private struct MoreMenuRow: View {
    let title: String
    let systemImage: String
    let color: Color
    let destination: SideMenuPage

    var body: some View {
        NavigationLink(value: destination) {
            MoreMenuRowLabel(title: title, systemImage: systemImage, color: color, trailingSymbol: "chevron.right")
        }
        .buttonStyle(.plain)
    }
}

private struct MoreMenuActionRow: View {
    let title: String
    let systemImage: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MoreMenuRowLabel(title: title, systemImage: systemImage, color: color, trailingSymbol: "arrow.up.right")
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens Mail to compose a message")
    }
}

private typealias MoreMenuRowLabel = BindrMenuRowLabel

private enum BindrSupport {
    static let email = "info@bindr-tcg.com"

    static var contactMailURL: URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Bindr Support")
        ]
        return components.url!
    }
}

private enum MoreSocialLink: String, CaseIterable, Identifiable {
    case email
    case instagram
    case x
    case tiktok
    case youtube

    var id: String { rawValue }

    var accessibilityLabel: String {
        switch self {
        case .email: return "Email"
        case .instagram: return "Instagram"
        case .x: return "X"
        case .tiktok: return "TikTok"
        case .youtube: return "YouTube"
        }
    }

    /// Social profile URLs for Bindr's official accounts.
    var destination: URL? {
        switch self {
        case .email:
            return BindrSupport.contactMailURL
        case .instagram:
            return URL(string: "https://www.instagram.com/Bindr_tcg")
        case .x:
            return URL(string: "https://x.com/Bindr_tcg")
        case .tiktok:
            return URL(string: "https://www.tiktok.com/@Bindr_tcg")
        case .youtube:
            return URL(string: "https://www.youtube.com/@Bindr_tcg")
        }
    }
}

private struct MoreSocialBrandIcon: View {
    let link: MoreSocialLink

    @Environment(\.bindrAccent) private var accent

    var body: some View {
        switch link {
        case .email:
            Circle()
                .fill(accent.gradient)
                .overlay {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                }
        case .instagram:
            Circle()
                .fill(
                    AngularGradient(
                        colors: [
                            Color(hex: "833AB4"),
                            Color(hex: "FD1D1D"),
                            Color(hex: "F77737"),
                            Color(hex: "FCAF45"),
                            Color(hex: "833AB4")
                        ],
                        center: .center
                    )
                )
                .overlay { InstagramGlyph() }
        case .x:
            Circle()
                .fill(.black)
                .overlay {
                    Text("X")
                        .font(.system(size: 17, weight: .black))
                        .foregroundStyle(.white)
                }
        case .tiktok:
            Circle()
                .fill(.black)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                }
        case .youtube:
            Circle()
                .fill(.white)
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color(hex: "FF0000"))
                        .frame(width: 26, height: 18)
                        .overlay {
                            Image(systemName: "play.fill")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white)
                                .offset(x: 1)
                        }
                }
                .overlay {
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                }
        }
    }
}

private struct InstagramGlyph: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(.white, lineWidth: 2)
                .frame(width: 22, height: 22)
            Circle()
                .strokeBorder(.white, lineWidth: 2)
                .frame(width: 8, height: 8)
            Circle()
                .fill(.white)
                .frame(width: 3, height: 3)
                .offset(x: 7, y: -7)
        }
    }
}

private struct MoreSocialLinksRow: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MoreSocialLink.allCases) { link in
                socialButton(link)
            }
        }
        .padding(.horizontal, BindrSpacing.md)
        .padding(.vertical, BindrSpacing.lg)
    }

    @ViewBuilder
    private func socialButton(_ link: MoreSocialLink) -> some View {
        let isEnabled = link.destination != nil

        Button {
            guard let url = link.destination else { return }
            openURL(url)
        } label: {
            VStack(spacing: 8) {
                MoreSocialBrandIcon(link: link)
                    .frame(width: 44, height: 44)

                Text(link.accessibilityLabel)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
        .disabled(!isEnabled)
        .accessibilityLabel(link.accessibilityLabel)
        .accessibilityHint(isEnabled ? "Opens \(link.accessibilityLabel)" : "Coming soon")
    }
}

// MARK: - Local Trade

private struct TradeCalculatorView: View {
    private enum CashField: Hashable {
        case mine
        case theirs
    }

    private enum TradeCalculatorAlert: Identifiable {
        case confirmation
        case result(title: String, message: String)

        var id: String {
            switch self {
            case .confirmation:
                return "confirmation"
            case .result(let title, let message):
                return "result|\(title)|\(message)"
            }
        }
    }

    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.bindrAccent) private var bindrAccent
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \CollectionItem.dateAcquired, order: .reverse) private var collectionItems: [CollectionItem]

    @State private var theirCards: [NewTradeItemInput] = []
    @State private var myCards: [NewTradeItemInput] = []
    @State private var theirCashText = ""
    @State private var myCashText = ""
    @State private var isMyCardPickerPresented = false
    @State private var isTheirCardPickerPresented = false
    @State private var activeScannerSide: TradeCalculatorSide?
    @State private var valuationCardCacheByID: [String: Card] = [:]
    @State private var myCardsValueUSD: Double = 0
    @State private var theirCardsValueUSD: Double = 0
    @State private var isValuationLoading = false
    @State private var isCompletingTrade = false
    @State private var activeAlert: TradeCalculatorAlert?
    @State private var completedTradeWishlistCandidates: [WishlistRemovalCandidate] = []
    @FocusState private var focusedCashField: CashField?

    private var valuationSignature: String {
        let myKey = myCards
            .map { "\($0.cardID)|\($0.variantKey)|\($0.quantity)" }
            .sorted()
            .joined(separator: ";")
        let theirKey = theirCards
            .map { "\($0.cardID)|\($0.variantKey)|\($0.quantity)" }
            .sorted()
            .joined(separator: ";")
        return "\(myKey)__\(theirKey)__\(services.priceDisplay.currency.rawValue)__\(services.pricing.usdToGbp)"
    }

    private var myTotalUSD: Double {
        myCardsValueUSD + displayAmountToUSD(parsedCash(myCashText))
    }

    private var theirTotalUSD: Double {
        theirCardsValueUSD + displayAmountToUSD(parsedCash(theirCashText))
    }

    private var hasAnyTradeValue: Bool {
        myTotalUSD > 0 || theirTotalUSD > 0 || !myCards.isEmpty || !theirCards.isEmpty
    }

    private var canCompleteTrade: Bool {
        hasAnyTradeValue && !isCompletingTrade
    }

    private var tradeAdvantageUSD: Double {
        theirTotalUSD - myTotalUSD
    }

    private var tradeBalanceTint: Color {
        if abs(tradeAdvantageUSD) < 0.01 { return bindrAccent }
        return tradeAdvantageUSD > 0 ? BindrPalette.ownedGreen : BindrPalette.alertRed
    }

    private var tradeBalanceText: String {
        if abs(tradeAdvantageUSD) < 0.01 {
            return "Balanced"
        }
        let amount = formattedDisplayAmountUSD(abs(tradeAdvantageUSD))
        return tradeAdvantageUSD > 0 ? "+\(amount)" : "-\(amount)"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                tradeSummarySection
                theirSideSection
                mySideSection
                if canCompleteTrade || isCompletingTrade {
                    completeTradeSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .bindrPageBackground()
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Local Trade")
        .navigationBarTitleDisplayMode(.inline)
        .tint(.primary)
        .sheet(isPresented: $isMyCardPickerPresented) {
            TradeCardPickerView(
                ownerUserID: currentUserID,
                navigationTitle: "My Collection"
            ) { selected in
                append(selected, to: .mine)
            }
            .environment(services)
        }
        .sheet(isPresented: $isTheirCardPickerPresented) {
            ManualTradeCardPickerView { selected in
                append(selected, to: .theirs)
            }
            .environment(services)
        }
        .fullScreenCover(item: $activeScannerSide) { side in
            CardScannerView(
                purpose: .trade { items in
                    append(items, to: side)
                },
                onMatch: { _ in },
                onDismiss: {
                    activeScannerSide = nil
                }
            )
            .environment(services)
        }
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .confirmation:
                return Alert(
                    title: Text("Complete this local trade?"),
                    message: Text("Your collection will be updated. Only cash entered above is recorded as a monetary transaction — card value changes are reflected in your collection value."),
                    primaryButton: .default(Text("Complete")) {
                        activeAlert = nil
                        Task {
                            await Task.yield()
                            try? await Task.sleep(for: .milliseconds(250))
                            guard !Task.isCancelled else { return }
                            await completeLocalTrade()
                        }
                    },
                    secondaryButton: .cancel()
                )
            case .result(let title, let message):
                return Alert(
                    title: Text(title),
                    message: Text(message),
                    dismissButton: .default(Text("OK")) {
                        guard !completedTradeWishlistCandidates.isEmpty else { return }
                        services.requestWishlistRemovalPrompt(for: completedTradeWishlistCandidates)
                        completedTradeWishlistCandidates = []
                    }
                )
            }
        }
        .task(id: valuationSignature) {
            await refreshTradeValues()
        }
    }

    private var tradeSummarySection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                tradeValuePill(
                    title: "Receive",
                    amountUSD: theirTotalUSD,
                    tint: BindrPalette.ownedGreen
                )
                tradeBalancePill
                tradeValuePill(
                    title: "Give",
                    amountUSD: myTotalUSD,
                    tint: BindrPalette.alertRed
                )
            }
        }
        .padding(12)
        .glassInsetStyle(cornerRadius: 16)
    }

    private func tradeValuePill(title: String, amountUSD: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)

            if isValuationLoading {
                ProgressView()
                    .tint(tint)
                    .scaleEffect(0.8)
                    .frame(height: 20, alignment: .leading)
            } else {
                Text(formattedDisplayAmountUSD(amountUSD))
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(colorScheme == .dark ? 0.07 : 0.04), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var tradeBalancePill: some View {
        VStack(spacing: 4) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
            Text(tradeBalanceText)
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(tradeBalanceTint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: 70)
        .padding(.vertical, 10)
        .background(tradeBalanceTint.opacity(colorScheme == .dark ? 0.12 : 0.07), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var completeTradeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                activeAlert = .confirmation
            } label: {
                HStack(spacing: 8) {
                    if isCompletingTrade {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15, weight: .bold))
                    }
                    Text(isCompletingTrade ? "Completing..." : "Complete Trade")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background {
                    Capsule()
                        .bindrAccentFill(bindrAccent, logoOpacity: 0.96)
                }
                .shadow(color: bindrAccent.opacity(0.25), radius: 12, x: 0, y: 6)
            }
            .buttonStyle(.plain)
            .disabled(isCompletingTrade)

            Text("Completing updates your card inventory. Cash is logged separately in Activity only when you enter an amount above.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 2)
    }

    private var theirSideSection: some View {
        calculatorSideSection(
            title: "Receive",
            subtitle: tradeSideDetail(cards: theirCards, cashText: theirCashText),
            cards: $theirCards,
            cashText: $theirCashText,
            cashLabel: "They add cash",
            tint: BindrPalette.ownedGreen,
            focusedField: .theirs,
            addTitle: "Add cards",
            addAction: { isTheirCardPickerPresented = true },
            scanAction: { activeScannerSide = .theirs }
        )
    }

    private var mySideSection: some View {
        calculatorSideSection(
            title: "Give",
            subtitle: tradeSideDetail(cards: myCards, cashText: myCashText),
            cards: $myCards,
            cashText: $myCashText,
            cashLabel: "I add cash",
            tint: BindrPalette.alertRed,
            focusedField: .mine,
            addTitle: "Add cards",
            addAction: { isMyCardPickerPresented = true },
            scanAction: { activeScannerSide = .mine }
        )
    }

    private func calculatorSideSection(
        title: String,
        subtitle: String,
        cards: Binding<[NewTradeItemInput]>,
        cashText: Binding<String>,
        cashLabel: String,
        tint: Color,
        focusedField: CashField,
        addTitle: String,
        addAction: @escaping () -> Void,
        scanAction: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                sideActionButton(systemImage: "plus", tint: tint, action: addAction)
                    .accessibilityLabel(addTitle)

                sideActionButton(systemImage: "camera.fill", tint: tint, action: scanAction)
                    .accessibilityLabel("Scan cards for \(title.lowercased())")
            }

            VStack(spacing: 12) {
                if cards.wrappedValue.isEmpty {
                    VStack(spacing: 8) {
                        Text("No cards selected")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                } else {
                    ForEach(cards.wrappedValue) { item in
                        TradeCalculatorCardRow(
                            item: item,
                            tint: tint,
                            onQuantityChange: { quantity in
                                updateQuantity(for: item, in: cards, quantity: quantity)
                            },
                            onRemove: {
                                remove(item, from: cards)
                            }
                        )
                        if item.id != cards.wrappedValue.last?.id {
                            Divider()
                                .overlay(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08))
                        }
                    }
                }
            }
            .padding(12)
            .glassInsetStyle(cornerRadius: 16)

            cashRow(label: cashLabel, text: cashText, tint: tint, focusedField: focusedField)
        }
        .padding(14)
        .glassCardStyle(cornerRadius: 18, interactive: false)
    }

    private func sideActionButton(systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func cashRow(label: String, text: Binding<String>, tint: Color, focusedField: CashField) -> some View {
        HStack {
            Label {
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemName: "banknote.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tint)
            }
            Spacer()
            HStack(spacing: 4) {
                Text(services.priceDisplay.currency.symbol)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(tint.opacity(0.85))
                TextField("0.00", text: text)
                    .keyboardType(.decimalPad)
                    .focused($focusedCashField, equals: focusedField)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 70)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(colorScheme == .dark ? 0.07 : 0.04), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
        }
    }

    private func tradeSideDetail(cards: [NewTradeItemInput], cashText: String) -> String {
        let quantity = cards.reduce(0) { $0 + max($1.quantity, 1) }
        let cash = parsedCash(cashText)
        var parts: [String] = []
        if quantity > 0 {
            parts.append("\(quantity) card\(quantity == 1 ? "" : "s")")
        }
        if cash > 0 {
            parts.append("\(services.priceDisplay.currency.symbol)\(String(format: "%.2f", cash)) cash")
        }
        return parts.isEmpty ? "No items yet" : parts.joined(separator: " + ")
    }

    private enum TradeCalculatorSide: String, Identifiable {
        case mine
        case theirs

        var id: String { rawValue }
    }

    private func append(_ selected: [NewTradeItemInput], to side: TradeCalculatorSide) {
        switch side {
        case .mine:
            for item in selected {
                appendOrIncrement(item, in: &myCards)
            }
        case .theirs:
            for item in selected {
                appendOrIncrement(item, in: &theirCards)
            }
        }
    }

    private func appendOrIncrement(_ item: NewTradeItemInput, in cards: inout [NewTradeItemInput]) {
        if let index = cards.firstIndex(where: { $0.cardID == item.cardID && $0.variantKey == item.variantKey }) {
            let existing = cards[index]
            cards[index] = NewTradeItemInput(
                cardID: existing.cardID,
                variantKey: existing.variantKey,
                quantity: existing.quantity + max(item.quantity, 1)
            )
        } else {
            cards.append(item)
        }
    }

    private func updateQuantity(
        for item: NewTradeItemInput,
        in cards: Binding<[NewTradeItemInput]>,
        quantity: Int
    ) {
        guard let index = cards.wrappedValue.firstIndex(where: { $0.id == item.id }) else { return }
        cards.wrappedValue[index] = NewTradeItemInput(
            cardID: item.cardID,
            variantKey: item.variantKey,
            quantity: max(quantity, 1)
        )
    }

    private func remove(_ item: NewTradeItemInput, from cards: Binding<[NewTradeItemInput]>) {
        cards.wrappedValue.removeAll { $0.id == item.id }
    }

    private var currentUserID: UUID {
        if case .signedIn(let id, _) = services.socialAuth.authState {
            return id
        }
        return UUID()
    }

    private func refreshTradeValues() async {
        isValuationLoading = true
        defer { isValuationLoading = false }

        var nextMyValueUSD: Double = 0
        var nextTheirValueUSD: Double = 0

        for item in myCards {
            guard let usd = await usdValue(for: item) else { continue }
            nextMyValueUSD += usd * Double(max(item.quantity, 1))
        }
        for item in theirCards {
            guard let usd = await usdValue(for: item) else { continue }
            nextTheirValueUSD += usd * Double(max(item.quantity, 1))
        }

        myCardsValueUSD = nextMyValueUSD
        theirCardsValueUSD = nextTheirValueUSD
    }

    private func usdValue(for item: NewTradeItemInput) async -> Double? {
        guard let card = await loadCardForValuation(id: item.cardID) else { return nil }
        if let exactVariant = await services.pricing.usdPriceForVariant(for: card, variantKey: item.variantKey) {
            return exactVariant
        }
        return await services.pricing.usdPrice(for: card, printing: item.variantKey)
    }

    private func loadCardForValuation(id: String) async -> Card? {
        if let cached = valuationCardCacheByID[id] {
            return cached
        }
        guard let loaded = await services.cardData.loadCard(masterCardId: id) else {
            return nil
        }
        valuationCardCacheByID[id] = loaded
        return loaded
    }

    private func parsedCash(_ text: String) -> Double {
        Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private func displayAmountToUSD(_ amount: Double) -> Double {
        switch services.priceDisplay.currency {
        case .usd:
            return amount
        case .gbp:
            let fx = max(services.pricing.usdToGbp, 0.0001)
            return amount / fx
        }
    }

    private func formattedDisplayAmountUSD(_ amountUSD: Double) -> String {
        services.priceDisplay.currency.format(amountUSD: amountUSD, usdToGbp: services.pricing.usdToGbp)
    }

    private var currencyCode: String {
        services.priceDisplay.currency == .gbp ? "GBP" : "USD"
    }

    private func completeLocalTrade() async {
        focusedCashField = nil
        activeAlert = nil
        completedTradeWishlistCandidates = []

        guard hasAnyTradeValue else {
            activeAlert = .result(
                title: "Local Trade",
                message: "Add cards or cash before completing the trade."
            )
            return
        }
        let hasCardChanges = !myCards.isEmpty || !theirCards.isEmpty
        let ledger = services.collectionLedger
        if hasCardChanges, ledger == nil {
            activeAlert = .result(
                title: "Local Trade",
                message: "Collection isn't ready. Try again."
            )
            return
        }

        isCompletingTrade = true
        var acquiredWishlistCandidates: [WishlistRemovalCandidate] = []
        defer {
            isCompletingTrade = false
            focusedCashField = nil
            isMyCardPickerPresented = false
            isTheirCardPickerPresented = false
            activeScannerSide = nil
        }

        do {
            let outgoing = try await resolvedOutgoingItems()
            try validateProjectedCollectionCapacity(outgoing: outgoing)
            let theirNames = await tradeSummaryNames(for: theirCards)
            let myNames = await tradeSummaryNames(for: myCards)
            let occurredAt = Date()
            let transactionGroupID = UUID()

            if let ledger {
                for (item, quantity, card) in outgoing {
                    try ledger.recordSingleCardDisposition(
                        item: item,
                        kind: .traded,
                        quantity: quantity,
                        currencyCode: currencyCode,
                        cardDisplayName: card.cardName,
                        unitPrice: nil,
                        counterparty: "Local trade",
                        notes: theirNames.isEmpty ? nil : "Received \(theirNames)",
                        transactionGroupId: transactionGroupID
                    )
                }

                for tradeItem in theirCards {
                    guard let card = await loadCardForValuation(id: tradeItem.cardID) else { continue }
                    try ledger.recordSingleCardAcquisition(
                        cardID: tradeItem.cardID,
                        variantKey: tradeItem.variantKey,
                        kind: .trade,
                        quantity: max(tradeItem.quantity, 1),
                        occurredAt: occurredAt,
                        currencyCode: currencyCode,
                        cardDisplayName: card.cardName,
                        unitPrice: nil,
                        gradingCompany: nil,
                        grade: nil,
                        packedOpenedFrom: nil,
                        tradeCounterparty: "Local trade",
                        tradeGaveAway: myNames.isEmpty ? nil : myNames,
                        giftFrom: nil,
                        boughtFrom: nil,
                        transactionGroupId: transactionGroupID
                    )
                    acquiredWishlistCandidates.append(
                        WishlistRemovalCandidate(cardID: tradeItem.cardID, cardName: card.cardName)
                    )
                }
            }
            try recordLocalTradeCashActivity(occurredAt: occurredAt, transactionGroupID: transactionGroupID)

            myCards = []
            theirCards = []
            myCashText = ""
            theirCashText = ""
            myCardsValueUSD = 0
            theirCardsValueUSD = 0
            completedTradeWishlistCandidates = acquiredWishlistCandidates
            Haptics.success()
            activeAlert = .result(
                title: "Trade Complete",
                message: hasCardChanges
                    ? "Your collection has been updated."
                    : "Trade completed."
            )
        } catch {
            completedTradeWishlistCandidates = []
            activeAlert = .result(
                title: "Local Trade",
                message: error.localizedDescription
            )
        }
    }

    private func recordLocalTradeCashActivity(occurredAt: Date, transactionGroupID: UUID) throws {
        let theirCash = parsedCash(theirCashText)
        let myCash = parsedCash(myCashText)
        guard theirCash > 0 || myCash > 0 else { return }

        let reference = "local-trade-\(transactionGroupID.uuidString)"
        if theirCash > 0 {
            modelContext.insert(
                LedgerLine(
                    occurredAt: occurredAt,
                    direction: LedgerDirection.sold.rawValue,
                    productKind: ProductKind.other.rawValue,
                    lineDescription: "Local trade cash received",
                    quantity: 1,
                    unitPrice: theirCash,
                    currencyCode: currencyCode,
                    counterparty: "Local trade",
                    channel: "trade",
                    externalRef: reference,
                    transactionGroupId: transactionGroupID
                )
            )
        }
        if myCash > 0 {
            modelContext.insert(
                LedgerLine(
                    occurredAt: occurredAt,
                    direction: LedgerDirection.bought.rawValue,
                    productKind: ProductKind.other.rawValue,
                    lineDescription: "Local trade cash paid",
                    quantity: 1,
                    unitPrice: myCash,
                    currencyCode: currencyCode,
                    counterparty: "Local trade",
                    channel: "trade",
                    externalRef: "\(reference)-out",
                    transactionGroupId: transactionGroupID
                )
            )
        }
        try modelContext.save()
    }

    private func resolvedOutgoingItems() async throws -> [(item: CollectionItem, quantity: Int, card: Card)] {
        var resolved: [(CollectionItem, Int, Card)] = []
        for tradeItem in myCards {
            guard let item = collectionItem(for: tradeItem) else {
                throw LocalTradeError.missingOwnedCard(cardID: tradeItem.cardID)
            }
            let quantity = max(tradeItem.quantity, 1)
            guard let card = await loadCardForValuation(id: tradeItem.cardID) else {
                throw LocalTradeError.missingCardData
            }
            guard item.quantity >= quantity else {
                throw LocalTradeError.insufficientQuantity(cardName: card.cardName, available: item.quantity, requested: quantity)
            }
            resolved.append((item, quantity, card))
        }
        return resolved
    }

    private func validateProjectedCollectionCapacity(outgoing: [(item: CollectionItem, quantity: Int, card: Card)]) throws {
        guard !services.store.isPremium else { return }

        var projectedCount = collectionItems.count
        for row in outgoing where row.quantity >= row.item.quantity {
            projectedCount -= 1
        }

        for item in theirCards {
            let alreadyExists = collectionItems.contains { existing in
                existing.cardID == item.cardID
                    && existing.variantKey == item.variantKey
                    && existing.itemKind == ProductKind.singleCard.rawValue
            }
            let depletedOutgoingSameStack = outgoing.contains { row in
                row.quantity >= row.item.quantity
                    && row.item.cardID == item.cardID
                    && row.item.variantKey == item.variantKey
                    && row.item.itemKind == ProductKind.singleCard.rawValue
            }
            if !alreadyExists || depletedOutgoingSameStack {
                projectedCount += 1
            }
        }

        if projectedCount > CollectionFreeTier.maxItems {
            throw CollectionLedgerError.freeTierLimitReached
        }
    }

    private func collectionItem(for tradeItem: NewTradeItemInput) -> CollectionItem? {
        let ownedStacks = collectionItems.filter { item in
            item.itemKind == ProductKind.singleCard.rawValue
                && item.cardID == tradeItem.cardID
                && item.quantity > 0
        }
        if let exact = ownedStacks.first(where: { $0.variantKey == tradeItem.variantKey }) {
            return exact
        }
        // If the user only owns one stack for this card, use it even when an older
        // trade row still has a stale/default variant key.
        if ownedStacks.count == 1 {
            return ownedStacks[0]
        }
        return nil
    }

    private func tradeSummaryNames(for items: [NewTradeItemInput]) async -> String {
        var names: [String] = []
        for item in items {
            guard let card = await loadCardForValuation(id: item.cardID) else { continue }
            let quantity = max(item.quantity, 1)
            names.append(quantity > 1 ? "\(quantity)x \(card.cardName)" : card.cardName)
        }
        return names.joined(separator: ", ")
    }
}

private enum LocalTradeError: LocalizedError {
    case missingOwnedCard(cardID: String)
    case insufficientQuantity(cardName: String, available: Int, requested: Int)
    case missingCardData

    var errorDescription: String? {
        switch self {
        case .missingOwnedCard:
            return "One of your selected cards is no longer in your collection."
        case .insufficientQuantity(let cardName, let available, let requested):
            return "You only have \(available) of \(cardName), but this trade needs \(requested)."
        case .missingCardData:
            return "Card data is still loading. Try again in a moment."
        }
    }
}

private struct TradeCalculatorCardRow: View {
    @Environment(AppServices.self) private var services

    let item: NewTradeItemInput
    let tint: Color
    let onQuantityChange: (Int) -> Void
    let onRemove: () -> Void

    @State private var card: Card?
    @State private var rowValueUSD: Double?

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                if let imageURLString = card?.displayImageSrc {
                    CachedAsyncImage(url: AppConfiguration.imageURL(relativePath: imageURLString)) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        shimmer
                    }
                } else {
                    shimmer
                }
            }
            .frame(width: 42, height: 58)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(card?.cardName ?? item.cardID)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    if item.variantKey != "normal" {
                        Text(item.variantKey)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Text("Qty \(item.quantity)")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(tint.opacity(0.12), in: Capsule())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 8) {
                Text(rowValueText)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(tint)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                HStack(spacing: 6) {
                    quantityButton(systemImage: "minus", isDisabled: item.quantity <= 1) {
                        onQuantityChange(max(item.quantity - 1, 1))
                    }

                    quantityButton(systemImage: "plus") {
                        onQuantityChange(item.quantity + 1)
                    }

                    Button(role: .destructive, action: onRemove) {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(BindrPalette.alertRed)
                            .frame(width: 26, height: 26)
                            .background(BindrPalette.alertRed.opacity(0.10), in: Circle())
                    }
                    .buttonStyle(.borderless)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .task(id: valueLookupSignature) {
            if card == nil {
                card = await services.cardData.loadCard(masterCardId: item.cardID)
            }
            await refreshRowValue()
        }
    }

    private func quantityButton(
        systemImage: String,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(isDisabled ? Color.secondary.opacity(0.45) : Color.primary)
                .frame(width: 26, height: 26)
                .background(Color.primary.opacity(0.08), in: Circle())
        }
        .buttonStyle(.borderless)
        .disabled(isDisabled)
    }

    private var shimmer: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.white.opacity(0.05))
    }

    private var valueLookupSignature: String {
        "\(item.cardID)|\(item.variantKey)|\(item.quantity)|\(services.priceDisplay.currency.rawValue)|\(services.pricing.usdToGbp)"
    }

    private var rowValueText: String {
        guard let rowValueUSD else { return "-" }
        return services.priceDisplay.currency.format(amountUSD: rowValueUSD, usdToGbp: services.pricing.usdToGbp)
    }

    private func refreshRowValue() async {
        guard let card else {
            rowValueUSD = nil
            return
        }
        let variantUSD = await services.pricing.usdPriceForVariant(for: card, variantKey: item.variantKey)
        let unitUSD: Double?
        if let variantUSD {
            unitUSD = variantUSD
        } else {
            unitUSD = await services.pricing.usdPrice(for: card, printing: item.variantKey)
        }
        if let unitUSD {
            rowValueUSD = unitUSD * Double(max(item.quantity, 1))
        } else {
            rowValueUSD = nil
        }
    }
}

private struct ManualTradeCardPickerView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    let onConfirm: ([NewTradeItemInput]) -> Void

    @State private var searchText = ""
    @State private var results: [Card] = []
    /// Persists across search changes so backspacing to find the next card does not drop prior picks.
    @State private var selectedCardsByID: [String: Card] = [:]
    @State private var isSearching = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                Group {
                    if isSearching {
                        ProgressView("Searching cards...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ContentUnavailableView(
                            "Search Catalogue",
                            systemImage: "magnifyingglass",
                            description: Text("Find the cards the other trader is offering.")
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if results.isEmpty {
                        ContentUnavailableView(
                            "No Cards Found",
                            systemImage: "rectangle.stack",
                            description: Text("Try a card name, set code, or card number.")
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        resultList
                    }
                }
            }
            .navigationTitle("Their Cards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add (\(selectedCardsByID.count))") {
                        let selected = selectedCardsByID.values.map { NewTradeItemInput(cardID: $0.masterCardId) }
                        onConfirm(selected)
                        dismiss()
                    }
                    .disabled(selectedCardsByID.isEmpty)
                }
            }
        }
        .tint(.primary)
        .task(id: searchText) {
            await search()
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.secondary.opacity(0.5))
            TextField("Search cards...", text: $searchText)
                .font(.system(size: 13))
                .foregroundStyle(Color.primary)
                .tint(BindrPalette.binderGold)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .inlineSearchFieldChrome(cornerRadius: 14)
    }

    private var resultList: some View {
        List(results) { card in
            Button {
                if selectedCardsByID[card.masterCardId] != nil {
                    selectedCardsByID.removeValue(forKey: card.masterCardId)
                } else {
                    selectedCardsByID[card.masterCardId] = card
                }
            } label: {
                HStack(spacing: 12) {
                    CachedAsyncImage(url: AppConfiguration.imageURL(relativePath: card.displayImageSrc)) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.white.opacity(0.05))
                    }
                    .frame(width: 38, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 5))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(card.cardName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Text("\(card.setCode) #\(card.cardNumber)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: selectedCardsByID[card.masterCardId] != nil ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(selectedCardsByID[card.masterCardId] != nil ? BindrPalette.binderGold : Color.secondary.opacity(0.45))
                }
            }
            .buttonStyle(.plain)
        }
        .listStyle(.plain)
    }

    private func search() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            results = []
            return
        }

        isSearching = true
        defer { isSearching = false }
        let found = await services.cardData.search(query: query)
        guard !Task.isCancelled else { return }
        results = Array(found.prefix(80))
    }
}
