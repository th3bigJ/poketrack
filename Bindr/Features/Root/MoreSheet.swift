import SwiftUI

/// Bottom sheet triggered from top-left menu button.
/// Contains quick access grid (glass icons) and Account section.
struct MoreSheet: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var onSelectTab: (AppTab) -> Void
    var onSelectPage: (SideMenuPage) -> Void
    /// Switches to the Collect tab and selects its Wishlist segment.
    var onSelectWishlist: () -> Void

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Quick Access Grid
                Section {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        QuickAccessButton(
                            icon: "star",
                            title: "Wishlist",
                            action: {
                                dismiss()
                                onSelectWishlist()
                            }
                        )
                        QuickAccessButton(
                            icon: "books.vertical",
                            title: "Bindrs",
                            action: {
                                dismiss()
                                onSelectTab(.bindrs)
                            }
                        )
                        QuickAccessButton(
                            icon: "rectangle.on.rectangle.angled",
                            title: "Deck Builder",
                            action: {
                                dismiss()
                                onSelectPage(.decks)
                            }
                        )
                        QuickAccessButton(
                            icon: "list.bullet.rectangle",
                            title: "Transactions",
                            action: {
                                dismiss()
                                onSelectPage(.transactions)
                            }
                        )
                        QuickAccessButton(
                            icon: "person.2",
                            title: "Social",
                            action: {
                                dismiss()
                                onSelectPage(.social)
                            }
                        )
                        QuickAccessButton(
                            icon: "chart.line.uptrend.xyaxis",
                            title: "Price Tracker",
                            action: {
                                dismiss()
                                // TODO: Navigate to price tracker
                            }
                        )
                        QuickAccessButton(
                            icon: "checklist",
                            title: "Set Tracker",
                            action: {
                                dismiss()
                                // TODO: Navigate to set tracker
                            }
                        )
                    }
                    .padding(.vertical, 8)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } header: {
                    Text("Quick Access")
                        .font(.subheadline)
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                }

                // MARK: - Account Section
                Section {
                    NavigationLink {
                        AccountView()
                            .environment(services)
                    } label: {
                        HStack {
                            Image(systemName: "person.crop.circle")
                                .font(.title3)
                                .foregroundStyle(.primary)
                                .frame(width: 32, height: 32)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            Text("Profile")
                                .font(.body)
                        }
                    }

                    NavigationLink {
                        AccountView()
                            .environment(services)
                    } label: {
                        HStack {
                            Image(systemName: "gearshape")
                                .font(.title3)
                                .foregroundStyle(.primary)
                                .frame(width: 32, height: 32)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            Text("Settings")
                                .font(.body)
                        }
                    }
                } header: {
                    Text("Account")
                        .font(.subheadline)
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
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
