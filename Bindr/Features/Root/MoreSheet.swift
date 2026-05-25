import SwiftUI

/// Root page for the More tab.
/// Styled using standard iOS grouped List elements with colorful glyph backdrops for a premium native look and feel.
struct MoreView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.bindrAccent) private var accent

    @Binding var navigationPath: NavigationPath

    @State private var showProfile = false
    @State private var showCreateBinder = false
    @State private var profilePath = NavigationPath()
    @State private var profile: SocialProfile? = nil

    var body: some View {
        ZStack(alignment: .top) {
            List {
                Section {
                    Button {
                        showProfile = true
                    } label: {
                        MoreProfileHeroCard(profile: profile)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 18, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                // MARK: - Core Features Section
                Section {
                    NavigationLink(value: SideMenuPage.binders) {
                        Label {
                            Text("Binders")
                                .font(.body)
                                .foregroundStyle(.primary)
                        } icon: {
                            Image(systemName: "books.vertical.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 30, height: 30)
                                .background(Color.blue.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                    
                    NavigationLink(value: SideMenuPage.decks) {
                        Label {
                            Text("Deck Builder")
                                .font(.body)
                                .foregroundStyle(.primary)
                        } icon: {
                            Image(systemName: "rectangle.on.rectangle.angled")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 30, height: 30)
                                .background(Color.green.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                    
                    NavigationLink(value: SideMenuPage.transactions) {
                        Label {
                            Text("Activity Ledger")
                                .font(.body)
                                .foregroundStyle(.primary)
                        } icon: {
                            Image(systemName: "list.bullet.rectangle.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 30, height: 30)
                                .background(Color.orange.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }

                    NavigationLink(value: SideMenuPage.gradingOpportunities) {
                        Label {
                            Text("Grading Opportunities")
                                .font(.body)
                                .foregroundStyle(.primary)
                        } icon: {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 30, height: 30)
                                .background(Color.red.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                } header: {
                    Text("Collection Tools")
                }

                // MARK: - Settings & Utility Section
                Section {
                    NavigationLink(value: SideMenuPage.themes) {
                        Label {
                            Text("Themes & Colors")
                                .font(.body)
                                .foregroundStyle(.primary)
                        } icon: {
                            Image(systemName: "paintpalette.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 30, height: 30)
                                .background(Color.purple.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                } header: {
                    Text("App Preferences")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .safeAreaInset(edge: .top) {
                Color.clear.frame(height: 54)
            }
            
            // Clean, perfect glassmorphic header matching all other main tabs
            BindrPageHeader(
                title: "More",
                leading: {
                    ChromeGlassCircleButton(accessibilityLabel: "Settings") {
                        navigationPath.append(SideMenuPage.account)
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
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

    private var subtitle: String {
        cleaned(profile?.bio)
            ?? (services.socialAuth.isSignedIn
                ? "Tap to edit your profile"
                : "Sign in to sync your social profile.")
    }

    private var roles: [String] {
        let raw = profile?.profileRoles ?? []
        let values = raw.compactMap { cleaned($0) }
        return values.isEmpty && profile != nil ? ["collector"] : values
    }

    private var friendCount: Int { profile?.friendCount ?? 0 }
    private var cardCount: Int { profile?.collectionCardCount ?? 0 }
    private var deckCount: Int { profile?.collectionDeckCount ?? 0 }
    private var binderCount: Int { profile?.collectionBinderCount ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                avatarView(size: 64)

                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .center, spacing: 6) {
                        Text(displayName)
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if let profile {
                            PremiumBadgeView(profile: profile, size: 14)
                        }
                    }

                    if !roles.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(roles.prefix(2), id: \.self) { role in
                                rolePill(roleDisplayName(role))
                            }
                        }
                    }
                }

                Spacer(minLength: 72)
            }

            Text(subtitle)
                .font(.system(size: 13))
                .lineSpacing(3)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 0) {
                statPill(value: "\(cardCount)", label: cardCount == 1 ? "Card" : "Cards")
                statDivider
                statPill(value: "\(deckCount)", label: deckCount == 1 ? "Deck" : "Decks")
                statDivider
                statPill(value: "\(binderCount)", label: binderCount == 1 ? "Binder" : "Binders")
                statDivider
                statPill(value: "\(friendCount)", label: friendCount == 1 ? "Friend" : "Friends")
            }
            .padding(.vertical, 12)
            .glassCardStyle(cornerRadius: 12, interactive: false)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(profileBackdrop)
        .overlay(alignment: .topTrailing) {
            favoriteCardPeek
        }
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 24)
                .padding(.trailing, 20)
        }
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
        .background(Color(uiColor: .systemGroupedBackground).opacity(colorScheme == .dark ? 0.30 : 0.35))
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
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
            }
            .shadow(color: themeColor.opacity(0.45), radius: 10, x: 0, y: 6)
            .rotationEffect(.degrees(8))
            .opacity(0.85)
            .padding(.top, 14)
            .padding(.trailing, 24)
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
            .font(.system(size: 10, weight: .heavy))
            .tracking(0.5)
            .foregroundStyle(themeColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(themeColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(themeColor.opacity(0.22), lineWidth: 1)
            }
    }

    private func statPill(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Divider()
            .frame(height: 30)
            .opacity(0.25)
    }

    private func roleDisplayName(_ role: String) -> String {
        role
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    private func cleaned(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
