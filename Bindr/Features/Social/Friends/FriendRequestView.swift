import SwiftUI

struct FriendRequestView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    let request: SocialFriendService.IncomingFriendRequest
    let onHandled: () -> Void

    @State private var isProcessing = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section("Request") {
                HStack(spacing: 12) {
                    avatar(urlString: request.requester.avatarURL)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(request.requester.displayName ?? request.requester.username)
                            .font(.headline)
                        Text("@\(request.requester.username)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            if let bio = request.requester.bio, !bio.isEmpty {
                Section("Bio") {
                    Text(bio)
                        .font(.body)
                }
            }

            Section {
                Button("Accept") {
                    Task { await respond(accepted: true) }
                }
                .disabled(isProcessing)

                Button("Decline", role: .destructive) {
                    Task { await respond(accepted: false) }
                }
                .disabled(isProcessing)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Friend Request")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func avatar(urlString: String?) -> some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                CachedAsyncImage(url: url, targetSize: CGSize(width: 48, height: 48)) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle().fill(Color.secondary.opacity(0.18))
                }
            } else {
                Circle()
                    .fill(Color.secondary.opacity(0.18))
                    .overlay {
                        Image(systemName: "person.fill")
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(Circle())
    }

    private func respond(accepted: Bool) async {
        isProcessing = true
        defer { isProcessing = false }
        do {
            try await services.socialFriend.respond(to: request.friendship.id, accepted: accepted)
            onHandled()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
