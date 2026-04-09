import SwiftUI
import UIKit

/// Full-height drawer: icon + title + subtitle rows, Account section. Close via the leading search-bar control.
struct SideMenuView: View {
    @Binding var isPresented: Bool
    @Binding var selectedTab: AppTab
    /// Must match `RootView` search row: `safeAreaTop + 8` (same as `UniversalSearchBar` vertical padding).
    var headerTopPadding: CGFloat
    var onPickSearch: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Same horizontal inset as search bar (16). Row height 48 matches `UniversalSearchBar` leading control frames (48×48). Drawer uses `ignoresSafeArea(.top)` so `headerTopPadding` (safeArea + 8) isn’t stacked with an extra safe-area inset — that was pushing “Menu” lower than the X.
            HStack(alignment: .center) {
                Text("Menu")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .frame(height: 48, alignment: .center)
            .padding(.horizontal, 16)
            .padding(.top, headerTopPadding)
            .padding(.bottom, 12)

            ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        SideMenuRow(
                            systemImage: "magnifyingglass",
                            title: "Search",
                            subtitle: "Cards, sets, and products"
                        ) {
                            close()
                            selectedTab = .browse
                            onPickSearch()
                        }

                        SideMenuRow(
                            systemImage: "rectangle.grid.2x2",
                            title: "Cards",
                            subtitle: "Browse all cards"
                        ) {
                            close()
                            selectedTab = .browse
                        }

                        SideMenuRow(
                            systemImage: "star",
                            title: "Wishlist",
                            subtitle: "Cards you want to collect"
                        ) {
                            close()
                            selectedTab = .wishlist
                        }

                        Divider()
                            .padding(.vertical, 12)
                            .padding(.horizontal, 4)

                        Text("Account")
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 4)
                            .padding(.bottom, 8)

                        SideMenuRow(
                            systemImage: "person.crop.circle",
                            title: "Account",
                            subtitle: "Profile and app preferences"
                        ) {
                            close()
                            selectedTab = .account
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(uiColor: .systemGroupedBackground))
        // Align with `UniversalSearchBar`: main column is safe-area–inset; without this, the system adds safe area again and the title sits below the close control.
        .ignoresSafeArea(edges: .top)
    }

    private func close() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            isPresented = false
        }
    }
}

private struct SideMenuRow: View {
    let systemImage: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 28, alignment: .center)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
