import SwiftUI

struct EditProfileView: View {
    let existingProfile: SocialProfile?
    let onSave: (_ username: String, _ displayName: String, _ bio: String) async throws -> Void

    @State private var username: String
    @State private var displayName: String
    @State private var bio: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        existingProfile: SocialProfile?,
        onSave: @escaping (_ username: String, _ displayName: String, _ bio: String) async throws -> Void
    ) {
        self.existingProfile = existingProfile
        self.onSave = onSave
        _username = State(initialValue: existingProfile?.username ?? "")
        _displayName = State(initialValue: existingProfile?.displayName ?? "")
        _bio = State(initialValue: existingProfile?.bio ?? "")
    }

    private var isUsernameLocked: Bool {
        existingProfile != nil
    }

    private var canSave: Bool {
        if isSaving { return false }
        if isUsernameLocked { return true }
        return !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section {
                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(isUsernameLocked)

                TextField("Display name", text: $displayName)

                TextField("Bio", text: $bio, axis: .vertical)
                    .lineLimit(3...6)
            } header: {
                Text("Profile")
            } footer: {
                Text(isUsernameLocked
                     ? "Username is locked after first save."
                     : "Choose your public username. You cannot change it later.")
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    save()
                } label: {
                    if isSaving {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Saving…")
                        }
                    } else {
                        Text("Save Profile")
                    }
                }
                .disabled(!canSave)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(existingProfile == nil ? "Create Profile" : "Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func save() {
        guard !isSaving else { return }
        errorMessage = nil
        isSaving = true
        let resolvedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                try await onSave(resolvedUsername, displayName, bio)
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
            await MainActor.run {
                isSaving = false
            }
        }
    }
}
