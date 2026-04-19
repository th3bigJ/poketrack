import SwiftUI

struct MyProfileView: View {
    let profile: SocialProfile
    let onEditTapped: () -> Void
    let onSignOutTapped: () -> Void

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("@\(profile.username)")
                        .font(.headline)
                    if let displayName = profile.displayName, !displayName.isEmpty {
                        Text(displayName)
                            .font(.title3.weight(.semibold))
                    }
                    if let bio = profile.bio, !bio.isEmpty {
                        Text(bio)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            } header: {
                Text("Your Social Profile")
            }

            Section {
                Button("Edit Profile") {
                    onEditTapped()
                }
                Button("Sign Out", role: .destructive) {
                    onSignOutTapped()
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("My Profile")
        .navigationBarTitleDisplayMode(.inline)
    }
}
