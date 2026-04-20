import SwiftUI

struct FeedView: View {
    @Environment(AppServices.self) private var services

    @State private var isInitialLoading = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isInitialLoading && services.socialFeed.items.isEmpty {
                loadingState
            } else if services.socialFeed.items.isEmpty {
                emptyState
            } else {
                feedList
            }
        }
        .navigationTitle("Feed")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await initialLoadIfNeeded()
        }
        .onAppear {
            services.socialFeed.clearUnreadState()
            services.socialPush.clearAppBadgeCount()
        }
    }

    private var loadingState: some View {
        List {
            ForEach(0..<5, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: 88)
                    .redacted(reason: .placeholder)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Feed Activity Yet",
            systemImage: "sparkles.rectangle.stack",
            description: Text("When friends share decks, binders, reactions, and comments, activity shows up here.")
        )
    }

    private var feedList: some View {
        List {
            ForEach(services.socialFeed.items) { item in
                FeedItemView(item: item)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .onAppear {
                        guard item.id == services.socialFeed.items.last?.id else { return }
                        Task { await loadMore() }
                    }
            }

            if isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .refreshable {
            await refresh()
        }
    }

    private func initialLoadIfNeeded() async {
        guard services.socialFeed.items.isEmpty else { return }
        await refresh()
    }

    private func refresh() async {
        isInitialLoading = true
        defer { isInitialLoading = false }
        do {
            _ = try await services.socialFeed.fetchFeed(refresh: true, pageSize: 20)
            services.socialFeed.clearUnreadState()
            services.socialPush.clearAppBadgeCount()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadMore() async {
        guard !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            _ = try await services.socialFeed.loadMore(pageSize: 20)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
