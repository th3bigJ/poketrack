import SwiftUI

struct NotificationPreferencesView: View {
    @Environment(AppServices.self) private var services

    @State private var preferences: NotificationPreferences?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if isLoading && preferences == nil {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading notification settings…")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let preferences {
                Section("Social Updates") {
                    toggleRow("Friend requests", isOn: preferences.friendRequests) { updated in
                        await save(preferences, friendRequests: updated)
                    }
                    toggleRow("Friend accepts", isOn: preferences.friendAccepts) { updated in
                        await save(preferences, friendAccepts: updated)
                    }
                    toggleRow("Shared content posts", isOn: preferences.sharedContentPosts) { updated in
                        await save(preferences, sharedContentPosts: updated)
                    }
                    toggleRow("Comments", isOn: preferences.comments) { updated in
                        await save(preferences, comments: updated)
                    }
                    toggleRow("Wishlist matches", isOn: preferences.wishlistMatches) { updated in
                        await save(preferences, wishlistMatches: updated)
                    }
                    toggleRow("Trade updates", isOn: preferences.tradeUpdates) { updated in
                        await save(preferences, tradeUpdates: updated)
                    }
                }

                Section("Marketing") {
                    toggleRow("Product updates", isOn: preferences.marketing) { updated in
                        await save(preferences, marketing: updated)
                    }
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Notification Preferences")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadPreferences()
        }
    }

    @ViewBuilder
    private func toggleRow(_ title: String, isOn: Bool, onToggle: @escaping @Sendable (Bool) async -> Void) -> some View {
        Toggle(isOn: Binding(
            get: { isOn },
            set: { updated in
                Task { await onToggle(updated) }
            }
        )) {
            Text(title)
        }
    }

    private func loadPreferences() async {
        isLoading = true
        defer { isLoading = false }
        do {
            preferences = try await services.socialProfile.fetchNotificationPreferences()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save(
        _ existing: NotificationPreferences,
        friendRequests: Bool? = nil,
        friendAccepts: Bool? = nil,
        sharedContentPosts: Bool? = nil,
        comments: Bool? = nil,
        wishlistMatches: Bool? = nil,
        tradeUpdates: Bool? = nil,
        marketing: Bool? = nil
    ) async {
        do {
            let updated = try await services.socialProfile.updateNotificationPreferences(
                friendRequests: friendRequests ?? existing.friendRequests,
                friendAccepts: friendAccepts ?? existing.friendAccepts,
                sharedContentPosts: sharedContentPosts ?? existing.sharedContentPosts,
                comments: comments ?? existing.comments,
                wishlistMatches: wishlistMatches ?? existing.wishlistMatches,
                tradeUpdates: tradeUpdates ?? existing.tradeUpdates,
                marketing: marketing ?? existing.marketing
            )
            preferences = updated
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
