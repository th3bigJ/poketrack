import SwiftUI
import SwiftData

/// Root page for the More tab.
/// Styled using standard iOS grouped List elements with colorful glyph backdrops for a premium native look and feel.
struct MoreView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.bindrAccent) private var accent
    @Environment(\.colorScheme) private var colorScheme
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
                                title: "Trade Calculator",
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

                        MoreMenuSection(title: "Account & Privacy") {
                            MoreMenuRow(
                                title: "Account & Privacy",
                                systemImage: "person.crop.circle.badge.checkmark",
                                color: .gray,
                                destination: .myAccount
                            )
                        }

                        MoreMenuSection(title: "Data") {
                            MoreMenuRow(
                                title: "Backup and Restore",
                                systemImage: "arrow.triangle.2.circlepath.icloud",
                                color: .blue,
                                destination: .backupRestore
                            )
                            MoreMenuRow(
                                title: "Export Data",
                                systemImage: "square.and.arrow.up",
                                color: .green,
                                destination: .dataExport
                            )
                            MoreMenuRow(
                                title: "Library Storage",
                                systemImage: "internaldrive.fill",
                                color: .orange,
                                destination: .libraryStorage
                            )
                        }

                        MoreLegalDisclaimerCard()
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
            case .backupRestore:
                BackupRestoreSettingsPage()
                    .environment(services)
            case .dataExport:
                DataExportView()
                    .environment(services)
            case .libraryStorage:
                LibraryStorageSettingsPage()
                    .environment(services)
            case .legalDisclaimer:
                DisclaimerView()
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

private struct MoreLegalDisclaimerCard: View {
    var body: some View {
        NavigationLink(value: SideMenuPage.legalDisclaimer) {
            VStack(alignment: .leading, spacing: BindrSpacing.sm) {
                HStack(spacing: 10) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color.secondary.opacity(0.10), in: Circle())

                    Text("Legal Disclaimer")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.secondary.opacity(0.45))
                }

                Text("Bindr is an independent app and is not affiliated with or endorsed by The Pokemon Company, Nintendo, Creatures Inc. or GAME FREAK.")
                    .font(.system(size: 12, weight: .regular))
                    .lineSpacing(3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
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
        if let imageURL = profile?.favoriteCardImageURL,
           let url = URL(string: imageURL) {
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

private struct MoreMenuSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BindrSpacing.sm) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.secondary)
                .padding(.horizontal, BindrSpacing.md)

            VStack(spacing: 0) {
                content
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}

private struct MoreMenuRow: View {
    let title: String
    let systemImage: String
    let color: Color
    let destination: SideMenuPage

    var body: some View {
        NavigationLink(value: destination) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 30, height: 30)
                    .background(color.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.secondary.opacity(0.45))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Trade Calculator

private struct TradeCalculatorView: View {
    private enum CashField: Hashable {
        case mine
        case theirs
    }

    @Environment(AppServices.self) private var services
    @Environment(\.bindrAccent) private var bindrAccent
    @Environment(\.colorScheme) private var colorScheme

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

    private var balanceUSD: Double {
        theirTotalUSD - myTotalUSD
    }

    private var hasAnyTradeValue: Bool {
        myTotalUSD > 0 || theirTotalUSD > 0 || !myCards.isEmpty || !theirCards.isEmpty
    }

    private var fairnessTitle: String {
        guard hasAnyTradeValue else { return "Build a trade" }
        if abs(balanceUSD) < 0.01 { return "Looks even" }
        return balanceUSD > 0 ? "You receive more value" : "They receive more value"
    }

    private var fairnessSubtitle: String {
        guard hasAnyTradeValue else {
            return "Add your cards from collection, then search the catalogue for what they are offering."
        }
        if abs(balanceUSD) < 0.01 {
            return "Both sides are currently balanced."
        }
        return "\(formattedDisplayAmountUSD(abs(balanceUSD))) difference"
    }

    private var fairnessColor: Color {
        guard hasAnyTradeValue else { return BindrPalette.deckBlue }
        if abs(balanceUSD) < 0.01 { return BindrPalette.ownedGreen }
        return balanceUSD > 0 ? BindrPalette.ownedGreen : BindrPalette.alertRed
    }

    var body: some View {
        List {
            summarySection
            theirSideSection
            mySideSection
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Trade Calculator")
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
        .task(id: valuationSignature) {
            await refreshTradeValues()
        }
    }

    private var summarySection: some View {
        Section {
            HStack(spacing: 0) {
                // My Side (Left)
                VStack(spacing: 8) {
                    Text("YOU")
                        .font(.system(size: 10, weight: .black))
                        .tracking(1.5)
                        .foregroundStyle(bindrAccent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(bindrAccent.opacity(0.12), in: Capsule())
                    
                    Text(formattedDisplayAmountUSD(myTotalUSD))
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(bindrAccent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
                
                // Middle VS + Difference
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: [Color.cyan, Color.purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 38, height: 38)
                            .shadow(color: Color.purple.opacity(0.35), radius: 6, x: 0, y: 3)
                        
                        Text("VS")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(.white)
                    }
                    
                    if hasAnyTradeValue {
                        Text(differenceBadgeText)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(differenceColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(differenceColor.opacity(0.12), in: Capsule())
                            .overlay {
                                Capsule()
                                    .stroke(differenceColor.opacity(0.24), lineWidth: 1)
                            }
                    }
                }
                .frame(width: 100)
                
                // Their Side (Right)
                VStack(spacing: 8) {
                    Text("THEM")
                        .font(.system(size: 10, weight: .black))
                        .tracking(1.5)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                    
                    Text(formattedDisplayAmountUSD(theirTotalUSD))
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 10)
        } footer: {
            Text(fairnessTitle + " · " + fairnessSubtitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(fairnessColor)
        }
    }

    private var differenceBadgeText: String {
        if abs(balanceUSD) < 0.01 { return "EVEN" }
        return formattedDisplayAmountUSD(abs(balanceUSD))
    }

    private var differenceColor: Color {
        if abs(balanceUSD) < 0.01 { return BindrPalette.ownedGreen }
        return balanceUSD > 0 ? BindrPalette.ownedGreen : BindrPalette.alertRed
    }

    private var mySideFill: Color {
        bindrAccent.opacity(colorScheme == .dark ? 0.28 : 0.14)
    }

    private var theirSideSection: some View {
        calculatorSideSection(
            title: "Their Side",
            footer: "Search the catalogue for cards they are offering, even if they do not use Bindr.",
            cards: $theirCards,
            cashText: $theirCashText,
            cashLabel: "They add cash",
            totalLabel: "Their total",
            focusedField: .theirs,
            addTitle: "Add Their Cards",
            addAction: { isTheirCardPickerPresented = true },
            scanAction: { activeScannerSide = .theirs }
        )
    }

    private var mySideSection: some View {
        calculatorSideSection(
            title: "My Side",
            footer: "Cards are selected from your collection.",
            cards: $myCards,
            cashText: $myCashText,
            cashLabel: "I add cash",
            totalLabel: "My total",
            focusedField: .mine,
            addTitle: "Add My Cards",
            addAction: { isMyCardPickerPresented = true },
            scanAction: { activeScannerSide = .mine }
        )
    }

    private func calculatorSideSection(
        title: String,
        footer: String,
        cards: Binding<[NewTradeItemInput]>,
        cashText: Binding<String>,
        cashLabel: String,
        totalLabel: String,
        focusedField: CashField,
        addTitle: String,
        addAction: @escaping () -> Void,
        scanAction: @escaping () -> Void
    ) -> some View {
        Section {
            if cards.wrappedValue.isEmpty {
                Text("No cards selected")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                ForEach(cards.wrappedValue) { item in
                    TradeCalculatorCardRow(
                        item: item,
                        onQuantityChange: { quantity in
                            updateQuantity(for: item, in: cards, quantity: quantity)
                        },
                        onRemove: {
                            remove(item, from: cards)
                        }
                    )
                }
            }

            HStack(spacing: 12) {
                Button(action: addAction) {
                    Label(addTitle, systemImage: "plus.circle")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                Button(action: scanAction) {
                    Group {
                        if #available(iOS 26.0, *) {
                            Image(systemName: "camera")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 32, height: 32)
                                .glassEffect(.clear.tint(nil).interactive(), in: Circle())
                        } else {
                            Image(systemName: "camera")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 32, height: 32)
                                .background(.thinMaterial, in: Circle())
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Scan cards for \(title.lowercased())")
            }

            cashRow(label: cashLabel, text: cashText, focusedField: focusedField)
        } header: {
            Text(title)
        } footer: {
            Text(footer)
        }
    }

    private func cashRow(label: String, text: Binding<String>, focusedField: CashField) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
            Spacer()
            HStack(spacing: 4) {
                Text(services.priceDisplay.currency.symbol)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                TextField("0.00", text: text)
                    .keyboardType(.decimalPad)
                    .focused($focusedCashField, equals: focusedField)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 14))
                    .frame(width: 90)
            }
        }
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
}

private struct TradeCalculatorCardRow: View {
    @Environment(AppServices.self) private var services

    let item: NewTradeItemInput
    let onQuantityChange: (Int) -> Void
    let onRemove: () -> Void

    @State private var card: Card?
    @State private var rowValueUSD: Double?

    var body: some View {
        HStack(spacing: 12) {
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
            .frame(width: 36, height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            Text(card?.cardName ?? item.cardID)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 8) {
                Text(rowValueText)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                HStack(spacing: 8) {
                    quantityButton(systemImage: "minus", isDisabled: item.quantity <= 1) {
                        onQuantityChange(max(item.quantity - 1, 1))
                    }

                    Text("Qty \(item.quantity)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .frame(minWidth: 42)

                    quantityButton(systemImage: "plus") {
                        onQuantityChange(item.quantity + 1)
                    }

                    Button(role: .destructive, action: onRemove) {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 26, height: 26)
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
    @State private var selectedCardIDs: Set<String> = []
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
                    Button("Add (\(selectedCardIDs.count))") {
                        let selected = results
                            .filter { selectedCardIDs.contains($0.masterCardId) }
                            .map { NewTradeItemInput(cardID: $0.masterCardId) }
                        onConfirm(selected)
                        dismiss()
                    }
                    .disabled(selectedCardIDs.isEmpty)
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
                if selectedCardIDs.contains(card.masterCardId) {
                    selectedCardIDs.remove(card.masterCardId)
                } else {
                    selectedCardIDs.insert(card.masterCardId)
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

                    Image(systemName: selectedCardIDs.contains(card.masterCardId) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(selectedCardIDs.contains(card.masterCardId) ? BindrPalette.binderGold : Color.secondary.opacity(0.45))
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
            selectedCardIDs = []
            return
        }

        isSearching = true
        defer { isSearching = false }
        let found = await services.cardData.search(query: query)
        guard !Task.isCancelled else { return }
        results = Array(found.prefix(80))
        selectedCardIDs = selectedCardIDs.intersection(Set(results.map(\.masterCardId)))
    }
}
