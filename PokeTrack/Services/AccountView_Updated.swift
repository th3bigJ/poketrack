import AuthenticationServices
import SwiftUI

/// Updated AccountView with iCloud status and clarified Sign in with Apple usage
struct AccountView_Updated: View {
    @Environment(AppServices.self) private var services
    @Environment(\.rootFloatingChromeInset) private var rootFloatingChromeInset
    @State private var appleUserId: String? = KeychainStorage.readAppleUserIdentifier()
    @State private var signInError: String?
    @State private var showPaywall = false

    var body: some View {
        List {
            // MARK: - iCloud Sync Status (NEW)
            Section {
                if services.cloudSettings.isICloudAvailable {
                    Label("iCloud connected", systemImage: "checkmark.icloud")
                        .foregroundStyle(.green)
                    
                    Text("Your wishlists and collections sync automatically across all your devices signed into iCloud.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.icloud")
                            .font(.title2)
                            .foregroundStyle(.orange)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("iCloud not available")
                                .font(.headline)
                            
                            Text("Sign into iCloud in Settings to sync your data across devices.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.caption)
                }
            } header: {
                Text("Data Sync")
            } footer: {
                Text("Your data is stored in your personal iCloud account. No account creation required.")
                    .font(.caption)
            }
            
            // MARK: - Pricing
            Section("Pricing") {
                Picker(
                    "Show prices in",
                    selection: Binding(
                        get: { services.priceDisplay.currency },
                        set: { 
                            services.priceDisplay.currency = $0
                            // Optionally sync to iCloud
                            services.cloudSettings.saveCurrency($0)
                        }
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

            // MARK: - Premium
            Section {
                if services.store.isPremium {
                    Label("Premium active", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    
                    Text("Unlimited wishlists and premium features unlocked.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Upgrade to Premium")
                                .font(.headline)
                            Text("Unlock unlimited wishlists and more")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Button("Upgrade") {
                            showPaywall = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                
                Button("Restore purchases") {
                    Task {
                        try? await services.store.restore()
                    }
                }
            } header: {
                Text("Premium")
            }
            
            // MARK: - Sign in with Apple (Optional - Can Remove)
            // This section is optional and can be removed if not using a custom backend
            // Keeping it here for future use when/if you add a web portal or custom backend
            /*
            Section {
                if let appleUserId {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Signed in", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.headline)
                        
                        Text(appleUserId)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        
                        Text("Currently not used - reserved for future web portal.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Button("Sign out") {
                            KeychainStorage.deleteAppleUserIdentifier()
                            self.appleUserId = nil
                        }
                        .font(.caption)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Sign in with Apple is optional and currently not required for any features.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text("Your data syncs automatically via iCloud without signing in here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
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
            } header: {
                Text("Sign in with Apple (Optional)")
            } footer: {
                Text("Reserved for future features like web portal access.")
            }
            */
        }
        .toolbar(.hidden, for: .navigationBar)
        .contentMargins(.top, rootFloatingChromeInset, for: .scrollContent)
        .sheet(isPresented: $showPaywall) {
            PaywallSheet()
                .environment(services)
        }
    }
}

// MARK: - Alternative: Minimal Version (Recommended)

/// Simplified AccountView without Sign in with Apple (recommended for now)
struct AccountView_Minimal: View {
    @Environment(AppServices.self) private var services
    @Environment(\.rootFloatingChromeInset) private var rootFloatingChromeInset
    @State private var showPaywall = false

    var body: some View {
        List {
            // iCloud Status
            Section {
                if services.cloudSettings.isICloudAvailable {
                    Label("iCloud connected", systemImage: "checkmark.icloud")
                        .foregroundStyle(.green)
                } else {
                    Label("iCloud not available", systemImage: "exclamationmark.icloud")
                        .foregroundStyle(.orange)
                    
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            } header: {
                Text("Data Sync")
            } footer: {
                if services.cloudSettings.isICloudAvailable {
                    Text("Your wishlists and collections sync across all devices signed into your iCloud account.")
                } else {
                    Text("Sign into iCloud in Settings to sync your data across devices.")
                }
            }
            
            // Pricing
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
            } footer: {
                Text("Catalog and history values from the server are in US dollars. Pounds use a daily exchange rate.")
            }

            // Premium
            Section("Premium") {
                if services.store.isPremium {
                    Label("Premium active", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
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

#Preview("Updated with iCloud Status") {
    NavigationStack {
        AccountView_Updated()
            .environment(AppServices())
    }
}

#Preview("Minimal Version") {
    NavigationStack {
        AccountView_Minimal()
            .environment(AppServices())
    }
}
