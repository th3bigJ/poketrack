import AVFoundation
import CoreImage.CIFilterBuiltins
import SwiftUI

struct QRProfileView: View {
    let username: String
    let onScannedUsername: (String) -> Void

    @State private var isScannerPresented = false
    @State private var copyFeedback: String?

    private var deepLinkString: String {
        "bindr://profile/@\(username.lowercased())"
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
            Section("My Friend QR") {
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
                            description: Text("Could not generate your profile QR code.")
                        )
                    }

                    Text("@\(username)")
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
                    UIPasteboard.general.string = deepLinkString
                    withAnimation(.easeInOut(duration: 0.2)) {
                        copyFeedback = "Copied link"
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            copyFeedback = nil
                        }
                    }
                } label: {
                    Label("Copy Profile Link", systemImage: "doc.on.doc")
                }

                Button {
                    isScannerPresented = true
                } label: {
                    Label("Scan Friend QR", systemImage: "camera.viewfinder")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("QR Profile")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isScannerPresented) {
            FriendQRScannerSheet { scannedURL in
                guard let url = URL(string: scannedURL),
                      let parsed = SocialFriendService.parseProfileUsername(from: url)
                else {
                    return
                }
                isScannerPresented = false
                onScannedUsername(parsed)
            }
        }
        .overlay(alignment: .bottom) {
            if let copyFeedback {
                Text(copyFeedback)
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.78), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(.bottom, 12)
            }
        }
    }
}

private struct FriendQRScannerSheet: View {
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

private struct FriendQRScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void
    let onError: (String) -> Void

    func makeUIViewController(context: Context) -> FriendQRScannerController {
        FriendQRScannerController(onScan: onScan, onError: onError)
    }

    func updateUIViewController(_ uiViewController: FriendQRScannerController, context: Context) {}
}

private final class FriendQRScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let onScan: (String) -> Void
    private let onError: (String) -> Void
    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var didEmitResult = false

    init(onScan: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
        self.onScan = onScan
        self.onError = onError
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        Task { @MainActor in
            await setupSession()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.stopRunning()
        }
    }

    private func setupSession() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
        }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            onError("Camera permission is required to scan QR codes.")
            return
        }

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            onError("No camera available.")
            return
        }
        guard let input = try? AVCaptureDeviceInput(device: camera) else {
            onError("Could not configure camera input.")
            return
        }

        let output = AVCaptureMetadataOutput()
        session.beginConfiguration()
        if session.canAddInput(input) {
            session.addInput(input)
        }
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            output.metadataObjectTypes = [.qr]
        }
        session.commitConfiguration()

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
        self.previewLayer = previewLayer
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !didEmitResult else { return }
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              object.type == .qr,
              let value = object.stringValue
        else {
            return
        }

        didEmitResult = true
        onScan(value)
    }
}
