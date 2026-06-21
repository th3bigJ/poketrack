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
                    ProfileAvatarView(profile: request.requester, size: 48)
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

    private func respond(accepted: Bool) async {
        Haptics.mediumImpact()
        isProcessing = true
        defer { isProcessing = false }
        do {
            try await services.socialFriend.respond(to: request.friendship.id, accepted: accepted)
            if accepted { Haptics.success() }
            onHandled()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            Haptics.error()
        }
    }
}
