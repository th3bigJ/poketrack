import SwiftUI

/// Root page for the More tab.
/// Contains quick access grid (glass icons) and Account section.
struct MoreView: View {
    @Environment(AppServices.self) private var services

    @Binding var navigationPath: NavigationPath

    @State private var showProfile = false
    @State private var showSettings = false
    @State private var showCreateBinder = false
    @State private var profilePath = NavigationPath()
    @State private var profile: SocialProfile? = nil

    var body: some View {
        List {
            // MARK: - Quick Access Grid
            Section {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    QuickAccessNavigationButton(
                        icon: "books.vertical.fill",
                        title: "Binders",
                        action: { navigationPath.append(SideMenuPage.binders) }
                    )
                    QuickAccessNavigationButton(
                        icon: "rectangle.on.rectangle.angled",
                        title: "Deck Builder",
                        action: { navigationPath.append(SideMenuPage.decks) }
                    )
                    QuickAccessNavigationButton(
                        icon: "list.bullet.rectangle",
                        title: "Activity",
                        action: { navigationPath.append(SideMenuPage.transactions) }
                    )
                }
                .padding(.vertical, 8)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: SideMenuPage.self) { page in
            switch page {
            case .account:
                NavigationStack {
                    SettingsView()
                        .environment(services)
                }
            case .social:
                SocialRootView()
                    .environment(services)
            case .binders:
                BindersRootView(showCreateSheet: $showCreateBinder)
            case .decks:
                DecksRootView()
            case .transactions:
                TransactionsView()
            }
        }
        .safeAreaInset(edge: .top) {
            moreHeader
        }
    }

    private var moreHeader: some View {
        ZStack {
            Text("More")
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)

            HStack {
                ChromeGlassCircleButton(accessibilityLabel: "Settings") {
                    Haptics.lightImpact()
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.primary)
                }
                .popover(isPresented: $showSettings) {
                    NavigationStack {
                        SettingsView()
                            .environment(services)
                    }
                }

                Spacer(minLength: 0)

                ChromeGlassCircleButton(accessibilityLabel: "Profile") {
                    Haptics.lightImpact()
                    showProfile = true
                } label: {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.primary)
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
                                }
                            }
                    }
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - Quick Access Button
private struct QuickAccessButton: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundStyle(.primary)
                    .frame(width: 56, height: 56)
                    .background(
                        glassBackground
                    )
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    /// Matches the chrome-button glass treatment in `UniversalSearchBar` — ultra-thin material with a hairline stroke, Liquid Glass on iOS 26+. No colour tint.
    @ViewBuilder
    private var glassBackground: some View {
        if #available(iOS 26.0, *) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                )
        }
    }
}

private struct QuickAccessNavigationButton: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundStyle(.primary)
                    .frame(width: 56, height: 56)
                    .background(glassBackground)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var glassBackground: some View {
        if #available(iOS 26.0, *) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                )
        }
    }
}
