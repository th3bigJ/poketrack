import AuthenticationServices
import SwiftUI

struct AccountView: View {
    @Environment(AppServices.self) private var services
    @State private var appleUserId: String? = KeychainStorage.readAppleUserIdentifier()
    @State private var signInError: String?
    @State private var showPaywall = false

    var body: some View {
        List {
            Section("Sign in with Apple") {
                if let appleUserId {
                    Text("Signed in")
                        .font(.headline)
                    Text(appleUserId)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Button("Sign out (local)") {
                        KeychainStorage.deleteAppleUserIdentifier()
                        self.appleUserId = nil
                    }
                } else {
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        switch result {
                        case .success(let authorization):
                            if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
                                let id = credential.user
                                KeychainStorage.saveAppleUserIdentifier(id)
                                appleUserId = id
                            }
                        case .failure(let error):
                            signInError = error.localizedDescription
                        }
                    }
                    .frame(height: 44)
                    if let signInError {
                        Text(signInError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            Section("Premium") {
                if services.store.isPremium {
                    Label("Premium active", systemImage: "checkmark.seal.fill")
                } else {
                    Button("Unlock Premium") {
                        showPaywall = true
                    }
                }
                Button("Restore purchases") {
                    Task {
                        try? await services.store.restore()
                    }
                }
            }

            Section("Premium tools") {
                NavigationLink {
                    CardScannerView()
                } label: {
                    Label("Card scanner", systemImage: "camera.viewfinder")
                }
                NavigationLink {
                    SealedProductsView()
                } label: {
                    Label("Sealed inventory", systemImage: "shippingbox")
                }
                NavigationLink {
                    TransactionsListView()
                } label: {
                    Label("Transactions", systemImage: "list.bullet.rectangle")
                }
                NavigationLink {
                    SharingPlaceholderView()
                } label: {
                    Label("Shared collections", systemImage: "person.2")
                }
            }

            Section("About") {
                LabeledContent("R2 base URL") {
                    Text(AppConfiguration.r2BaseURL.absoluteString)
                        .font(.caption2)
                        .lineLimit(2)
                }
                LabeledContent("Catalog prefix") {
                    Text(AppConfiguration.r2CatalogPathPrefix.isEmpty ? "(root)" : AppConfiguration.r2CatalogPathPrefix)
                        .font(.caption2)
                }
                LabeledContent("Pricing prefix") {
                    Text(AppConfiguration.r2PricingPathPrefix.isEmpty ? "(root)" : AppConfiguration.r2PricingPathPrefix)
                        .font(.caption2)
                }
                LabeledContent("Sets JSON") {
                    Text(AppConfiguration.r2CatalogURL(path: "sets.json").absoluteString)
                        .font(.caption2)
                        .lineLimit(3)
                }
                LabeledContent("Sample pricing") {
                    Text(AppConfiguration.r2PricingURL(path: "pricing/sv01.json").absoluteString)
                        .font(.caption2)
                        .lineLimit(3)
                }
            }
        }
        .navigationTitle("Account")
        .sheet(isPresented: $showPaywall) {
            PaywallSheet()
                .environment(services)
        }
    }
}
