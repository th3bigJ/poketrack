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
        List {
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
                Text("App Preferences")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bindrPageBackground()
        .navigationTitle("More")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                ChromeGlassCircleButton(accessibilityLabel: "Settings") {
                    navigationPath.append(SideMenuPage.account)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(accent)
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                ChromeGlassCircleButton(accessibilityLabel: "Profile") {
                    showProfile = true
                } label: {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(accent)
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
            }
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
}

