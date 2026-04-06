import AuthenticationServices
import SwiftUI

struct AccountView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.rootFloatingChromeInset) private var rootFloatingChromeInset
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

            Section("Pricing") {
                Picker(
                    "Show prices in",
                    selection: Binding(
                        get: { services.priceDisplay.currency },
                        set: { services.priceDisplay.currency = $0 }
                    )
                ) {
                    ForEach(PriceDisplayCurrency.allCases) { c in
                        Text(c.pickerTitle).tag(c)
                    }
                }
                Text("Catalog and history values from the server are in US dollars. Pounds use a daily exchange rate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        }
        .toolbar(.hidden, for: .navigationBar)
        .contentMargins(.top, rootFloatingChromeInset, for: .scrollContent)
        .sheet(isPresented: $showPaywall) {
            PaywallSheet()
                .environment(services)
        }
    }
}
