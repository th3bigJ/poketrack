import SwiftUI

/// Root page for the More tab.
/// Styled using standard iOS grouped List elements with colorful glyph backdrops for a premium native look and feel.
struct MoreView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.bindrAccent) private var accent
    @Environment(\.rootFloatingChromeInset) private var rootFloatingChromeInset

    @Binding var navigationPath: NavigationPath

    @State private var showProfile = false
    @State private var showCreateBinder = false
    @State private var profilePath = NavigationPath()
    @State private var profile: SocialProfile? = nil

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(spacing: BindrSpacing.lg) {
                    Color.clear.frame(height: rootFloatingChromeInset)

                    Button {
                        showProfile = true
                    } label: {
                        MoreProfileHeroCard(profile: profile)
                    }
                    .buttonStyle(.plain)

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
                            Divider()
                                .padding(.leading, 60)
                            MoreMenuRow(
                                title: "Settings",
                                systemImage: "gearshape.fill",
                                color: .gray,
                                destination: .account
                            )
                        }
                    }
                    .padding(.horizontal, BindrSpacing.lg)
                }
                .padding(.bottom, 120)
            }
            
            // Clean, perfect glassmorphic header matching all other main tabs
            BindrPageHeader(
                title: "More"
            )
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
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") {
                            showProfile = false
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(accent)
                    }
                }
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
            case .themes:
                ThemesView()
            case .gradingOpportunities:
                GradingOpportunitiesView()
            }
        }
    }

    private func loadProfileIfPossible() async {
        profile = services.socialProfile.currentProfile
        guard services.socialAuth.isSignedIn else { return }
        if profile == nil {
            profile = try? await services.socialProfile.fetchMyProfile()
        }
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

    private var friendCount: Int { profile?.friendCount ?? 0 }
    private var cardCount: Int { profile?.collectionCardCount ?? 0 }
    private var deckCount: Int { profile?.collectionDeckCount ?? 0 }
    private var binderCount: Int { profile?.collectionBinderCount ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: BindrSpacing.md) {
            HStack(alignment: .top, spacing: BindrSpacing.md) {
                avatarView(size: 64)

                VStack(alignment: .leading, spacing: BindrSpacing.sm) {
                    HStack(alignment: .center, spacing: BindrSpacing.sm) {
                        Text(displayName)
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if let profile {
                            PremiumBadgeView(profile: profile, size: 14)
                        }
                    }

                    if !roleTitles.isEmpty {
                        HStack(spacing: BindrSpacing.sm) {
                            ForEach(roleTitles, id: \.self) { title in
                                rolePill(title)
                            }
                        }
                    }
                }

                Spacer()
            }

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 0) {
                statColumn(value: "\(cardCount)", label: cardCount == 1 ? "Card" : "Cards")
                statColumn(value: "\(deckCount)", label: deckCount == 1 ? "Deck" : "Decks")
                statColumn(value: "\(binderCount)", label: binderCount == 1 ? "Binder" : "Binders")
                statColumn(value: "\(friendCount)", label: friendCount == 1 ? "Friend" : "Friends")
            }
            .padding(.vertical, BindrSpacing.md)
            .glassCardStyle(cornerRadius: 12, interactive: false)
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
            .overlay(Circle().stroke(themeColor, lineWidth: 3))

            if services.socialAuth.isSignedIn {
                Circle()
                    .fill(Color(hex: "52C97C"))
                    .frame(width: 18, height: 18)
                    .overlay(Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 3))
            }
        }
    }

    private func rolePill(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(0.4)
            .foregroundStyle(themeColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(themeColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(themeColor.opacity(0.19), lineWidth: 1)
            }
    }

    private func statColumn(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Color.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
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
