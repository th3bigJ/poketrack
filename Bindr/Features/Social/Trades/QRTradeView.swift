import AVFoundation
import CoreImage.CIFilterBuiltins
import SwiftUI

struct QRTradeView: View {
    @Environment(AppServices.self) private var services
    let currentUsername: String
    let navigationPath: Binding<NavigationPath>

    @State private var isScannerPresented = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var deepLinkString: String {
        if let currentUserID {
            return "bindr://social/trade?user_id=\(currentUserID.uuidString)&username=\(currentUsername.lowercased())"
        }
        return "bindr://profile/@\(currentUsername.lowercased())"
    }

    private var currentUserID: UUID? {
        if case .signedIn(let id, _) = services.socialAuth.authState {
            return id
        }
        return nil
    }

    private var qrImage: UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(deepLinkString.utf8)
        filter.correctionLevel = "M"
        guard let outputImage = filter.outputImage else { return nil }
        let transformed = outputImage.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    var body: some View {
        List {
            Section("My Trade QR") {
                VStack(spacing: 14) {
                    if let qrImage {
                        Image(uiImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 220, height: 220)
                            .padding(16)
                            .background {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(Color(uiColor: .systemBackground))
                            }
                    } else {
                        ContentUnavailableView(
                            "QR Unavailable",
                            systemImage: "qrcode",
                            description: Text("Could not generate your QR code.")
                        )
                    }

                    Text("@\(currentUsername)")
                        .font(.headline)

                    Text(deepLinkString)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section {
                Button {
                    isScannerPresented = true
                } label: {
                    HStack {
                        Label("Scan QR to Trade", systemImage: "camera.viewfinder")
                        if isLoading {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isLoading)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("QR Trade")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isScannerPresented) {
            QRTradeScannerSheet { scannedURL in
                handleScan(scannedURL)
            }
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func handleScan(_ rawString: String) {
        guard let scannedIdentity = scannedTradeIdentity(from: rawString) else {
            errorMessage = "Invalid QR code. Make sure it's a valid Bindr trade QR."
            return
        }
        isScannerPresented = false
        isLoading = true
        Task {
            do {
                let profile: SocialProfile?
                switch scannedIdentity {
                case .userID(let id):
                    profile = try await services.socialProfile.fetchProfile(id: id)
                case .username(let username):
                    profile = try await services.socialFriend.fetchProfile(username: username)
                }

                guard let profile else {
                    errorMessage = "Could not find that Bindr user."
                    isLoading = false
                    return
                }
                guard profile.id != currentUserID else {
                    errorMessage = "Scan another user's QR code to start a trade."
                    isLoading = false
                    return
                }
                let session = try await services.tradeSession.createSession(participantID: profile.id)
                isLoading = false
                navigationPath.wrappedValue.append(SocialDestination.mutualTrade(
                    sessionID: session.id,
                    otherUserID: profile.id,
                    otherUsername: profile.username
                ))
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private enum ScannedTradeIdentity {
        case userID(UUID)
        case username(String)
    }

    private func scannedTradeIdentity(from rawString: String) -> ScannedTradeIdentity? {
        guard let url = URL(string: rawString) else { return nil }
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           url.scheme?.lowercased() == "bindr",
           url.host?.lowercased() == "social",
           url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased() == "trade",
           let rawUserID = components.queryItems?.first(where: { $0.name.lowercased() == "user_id" })?.value,
           let userID = UUID(uuidString: rawUserID) {
            return .userID(userID)
        }

        if let username = SocialFriendService.parseProfileUsername(from: url) {
            return .username(username)
        }
        return nil
    }
}

private struct QRTradeScannerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onScan: (String) -> Void

    @State private var message = "Point your camera at a Bindr QR code."

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                FriendQRScannerView { value in
                    onScan(value)
                } onError: { error in
                    message = error
                }
                .ignoresSafeArea()

                Text(message)
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.72), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(.bottom, 20)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationTitle("Scan QR")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
