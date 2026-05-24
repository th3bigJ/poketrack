import SwiftUI
import UIKit

// MARK: - Data

struct LaunchProgressState: Equatable {
    var message: String
    var status: String
    var fraction: Double
    var downloadedBytes: Int64
    var totalBytes: Int64
    var hasByteProgress: Bool
}

// MARK: - CALayer shimmer bar (freeze-proof)

/// A horizontal progress bar whose fill animates via CALayer — runs on the render
/// server so it stays smooth even while @MainActor is blocked by CloudKit merges.
final class _CAProgressBarView: UIView {
    private let trackLayer = CALayer()
    private let fillLayer = CALayer()
    private let shimmerLayer = CAGradientLayer()

    var fillColor: UIColor = .systemBlue {
        didSet { fillLayer.backgroundColor = fillColor.cgColor }
    }
    var trackColor: UIColor = UIColor.tertiarySystemFill {
        didSet { trackLayer.backgroundColor = trackColor.cgColor }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        layer.addSublayer(trackLayer)
        trackLayer.addSublayer(fillLayer)
        fillLayer.addSublayer(shimmerLayer)

        shimmerLayer.colors = [
            UIColor.clear.cgColor,
            UIColor.white.withAlphaComponent(0.35).cgColor,
            UIColor.clear.cgColor,
        ]
        shimmerLayer.startPoint = CGPoint(x: 0, y: 0.5)
        shimmerLayer.endPoint   = CGPoint(x: 1, y: 0.5)
        shimmerLayer.locations  = [-0.5, -0.25, 0]
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let h = bounds.height
        let r = h / 2
        trackLayer.frame = bounds
        trackLayer.cornerRadius = r
        trackLayer.masksToBounds = true
        trackLayer.backgroundColor = trackColor.cgColor
        fillLayer.cornerRadius = r
        fillLayer.backgroundColor = fillColor.cgColor
        shimmerLayer.frame = CGRect(x: 0, y: 0, width: bounds.width * 2, height: h)
        startShimmer()
    }

    private var shimmerStarted = false
    private func startShimmer() {
        guard !shimmerStarted else { return }
        shimmerStarted = true
        let anim = CABasicAnimation(keyPath: "locations")
        anim.fromValue = [-0.5, -0.25, 0.0]
        anim.toValue   = [1.0,  1.25,  1.5]
        anim.duration  = 1.6
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        anim.repeatCount = .infinity
        shimmerLayer.add(anim, forKey: "shimmer")
    }

    func setFraction(_ fraction: Double, animated: Bool) {
        let clamped = min(max(fraction, 0), 1)
        let targetWidth = bounds.width * clamped
        if animated {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.4)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
            fillLayer.frame = CGRect(x: 0, y: 0, width: targetWidth, height: bounds.height)
            CATransaction.commit()
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            fillLayer.frame = CGRect(x: 0, y: 0, width: targetWidth, height: bounds.height)
            CATransaction.commit()
        }
    }
}

struct CAProgressBar: UIViewRepresentable {
    var fraction: Double
    var fillColor: Color
    var height: CGFloat = 6

    func makeUIView(context: Context) -> _CAProgressBarView {
        let v = _CAProgressBarView()
        v.setContentHuggingPriority(.defaultLow, for: .horizontal)
        v.setContentHuggingPriority(.required, for: .vertical)
        return v
    }

    func updateUIView(_ uiView: _CAProgressBarView, context: Context) {
        uiView.fillColor = UIColor(fillColor)
        uiView.trackColor = UIColor(Color(uiColor: .tertiarySystemFill))
        uiView.setFraction(fraction, animated: true)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: _CAProgressBarView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 280, height: height)
    }
}

// MARK: - CALayer pulse dot (freeze-proof)

final class _PulseDotsView: UIView {
    private var dotLayers: [CAShapeLayer] = []
    private let dotCount = 3
    private let dotSize: CGFloat = 5
    private let dotSpacing: CGFloat = 8

    var dotColor: UIColor = .systemBlue {
        didSet { dotLayers.forEach { $0.fillColor = dotColor.cgColor } }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        for i in 0..<dotCount {
            let dot = CAShapeLayer()
            dot.path = UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: dotSize, height: dotSize)).cgPath
            dot.fillColor = dotColor.cgColor
            dot.opacity = 0.25
            layer.addSublayer(dot)
            dotLayers.append(dot)

            let anim = CAKeyframeAnimation(keyPath: "opacity")
            anim.values = [0.25, 1.0, 0.25]
            anim.keyTimes = [0, 0.5, 1]
            anim.duration = 1.4
            anim.beginTime = CACurrentMediaTime() + Double(i) * 0.22
            anim.repeatCount = .infinity
            anim.timingFunctions = [
                CAMediaTimingFunction(name: .easeInEaseOut),
                CAMediaTimingFunction(name: .easeInEaseOut),
            ]
            dot.add(anim, forKey: "pulse")
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let totalWidth = CGFloat(dotCount) * dotSize + CGFloat(dotCount - 1) * dotSpacing
        let startX = (bounds.width - totalWidth) / 2
        let startY = (bounds.height - dotSize) / 2
        for (i, dot) in dotLayers.enumerated() {
            dot.frame = CGRect(
                x: startX + CGFloat(i) * (dotSize + dotSpacing),
                y: startY,
                width: dotSize,
                height: dotSize
            )
            dot.path = UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: dotSize, height: dotSize)).cgPath
        }
    }

    override var intrinsicContentSize: CGSize {
        let w = CGFloat(dotCount) * dotSize + CGFloat(dotCount - 1) * dotSpacing
        return CGSize(width: w, height: dotSize)
    }
}

struct PulseDots: UIViewRepresentable {
    var color: Color

    func makeUIView(context: Context) -> _PulseDotsView { _PulseDotsView() }

    func updateUIView(_ uiView: _PulseDotsView, context: Context) {
        uiView.dotColor = UIColor(color)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: _PulseDotsView, context: Context) -> CGSize? {
        uiView.intrinsicContentSize
    }
}

// MARK: - Launch wordmark view

struct LaunchWordmarkView: View {
    var progress: LaunchProgressState? = nil
    var isSyncingCloudKit: Bool = false
    var onRevealComplete: () -> Void = {}
    var elapsedLabel: String = "0.0s"

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.bindrAccent) private var bindrAccent
    @State private var animStates: [Bool] = [false, false, false, false, false]
    @State private var taglineVisible = false
    @State private var statusVisible = false
    @State private var hasStartedAnimation = false
    @State private var hasFiredRevealComplete = false
    private let fullWord = "BINDR"

    private var foreground: Color { colorScheme == .dark ? .white : Color(white: 0.08) }
    private var subtle: Color { foreground.opacity(0.38) }

    private var byteProgressText: String {
        guard let p = progress, p.totalBytes > 0 else { return "" }
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB]
        f.countStyle = .file
        f.includesUnit = true
        return "\(f.string(fromByteCount: p.downloadedBytes)) / \(f.string(fromByteCount: p.totalBytes))"
    }

    var body: some View {
        ZStack {
            // Background — same radial glow as BindrPageBackground
            Color(uiColor: .systemBackground).ignoresSafeArea()

            RadialGradient(
                colors: [
                    bindrAccent.opacity(colorScheme == .dark ? 0.18 : 0.10),
                    bindrAccent.opacity(colorScheme == .dark ? 0.06 : 0.04),
                    .clear
                ],
                center: .init(x: 0.5, y: 0.35),
                startRadius: 0,
                endRadius: 380
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [
                    bindrAccent.opacity(colorScheme == .dark ? 0.10 : 0.06),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 400
            )
            .offset(x: 60, y: -60)
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Wordmark
                wordmarkView
                    .padding(.bottom, 10)

                // Tagline
                Text("Share your Collection")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(subtle)
                    .tracking(3.5)
                    .textCase(.uppercase)
                    .opacity(taglineVisible ? 1 : 0)
                    .offset(y: taglineVisible ? 0 : 6)

                // Elapsed (dev only)
                Text(elapsedLabel)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(foreground.opacity(0.18))
                    .padding(.top, 6)

                Spacer()
                Spacer()

                // Status area — pinned near bottom
                statusArea
                    .frame(height: 80)
                    .opacity(statusVisible ? 1 : 0)
                    .offset(y: statusVisible ? 0 : 12)
                    .padding(.bottom, 56)
            }
            .padding(.horizontal, 40)
        }
        .task {
            guard !hasStartedAnimation else { return }
            hasStartedAnimation = true
            await runRevealAnimation()
        }
        .onChange(of: isSyncingCloudKit) { _, syncing in
            if syncing && statusVisible {
                // Already visible — content swap handled by statusArea's own transition
            }
        }
    }

    // MARK: Wordmark

    private var wordmarkView: some View {
        HStack(spacing: 0) {
            ForEach(0..<fullWord.count, id: \.self) { i in
                Text(String(fullWord[fullWord.index(fullWord.startIndex, offsetBy: i)]))
                    .font(.custom("BebasNeue-Regular", size: 80))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                foreground.opacity(0.96),
                                foreground.opacity(0.78),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .offset(y: animStates[i] ? 0 : 20)
                    .opacity(animStates[i] ? 1 : 0)
                    .blur(radius: animStates[i] ? 0 : 4)
                    .animation(
                        .spring(response: 0.50, dampingFraction: 0.70)
                            .delay(Double(i) * 0.08),
                        value: animStates[i]
                    )
            }
        }
    }

    // MARK: Status area

    @ViewBuilder
    private var statusArea: some View {
        if let p = progress {
            catalogProgressView(p)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        } else if isSyncingCloudKit {
            cloudKitSyncView
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    // MARK: CloudKit sync indicator

    private var cloudKitSyncView: some View {
        VStack(spacing: 10) {
            // Pill badge
            HStack(spacing: 7) {
                Image(systemName: "icloud.and.arrow.down.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(bindrAccent)
                Text("Syncing iCloud")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(foreground.opacity(0.75))
                    .tracking(0.3)
                PulseDots(color: bindrAccent.opacity(0.7))
                    .padding(.leading, 2)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        bindrAccent.opacity(0.35),
                                        bindrAccent.opacity(0.10),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.75
                            )
                    }
            }

            Text("Loading your cards from iCloud…")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(subtle)
        }
    }

    // MARK: Catalog download progress

    @ViewBuilder
    private func catalogProgressView(_ p: LaunchProgressState) -> some View {
        VStack(spacing: 12) {
            // Label
            VStack(spacing: 3) {
                Text(p.message)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(foreground.opacity(0.88))
                    .multilineTextAlignment(.center)
                Text(p.status)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(subtle)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }

            if p.hasByteProgress {
                VStack(spacing: 7) {
                    // Track
                    CAProgressBar(fraction: p.fraction, fillColor: bindrAccent, height: 3)
                        .frame(maxWidth: 220)
                        .clipShape(Capsule())

                    HStack(spacing: 6) {
                        Text("\(Int((min(max(p.fraction, 0), 1) * 100).rounded()))%")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(foreground.opacity(0.65))
                        if !byteProgressText.isEmpty {
                            Text("·")
                                .foregroundStyle(subtle)
                            Text(byteProgressText)
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(subtle)
                        }
                    }
                }
            } else {
                PulseDots(color: bindrAccent.opacity(0.55))
            }
        }
    }

    // MARK: Animation sequence

    private func runRevealAnimation() async {
        // Stagger all letters simultaneously (spring handles individual delays)
        for i in 0..<fullWord.count {
            animStates[i] = true
        }

        try? await Task.sleep(nanoseconds: 380_000_000)

        withAnimation(.easeOut(duration: 0.45)) {
            taglineVisible = true
        }

        try? await Task.sleep(nanoseconds: 300_000_000)

        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            statusVisible = true
        }

        try? await Task.sleep(nanoseconds: 150_000_000)

        if !hasFiredRevealComplete {
            hasFiredRevealComplete = true
            onRevealComplete()
        }
    }
}

// MARK: - Other loading screens (unchanged API)

struct StartupBusyView: View {
    let message: String
    let status: String

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            VStack(spacing: 24) {
                ProgressView().controlSize(.large)
                VStack(spacing: 8) {
                    Text(message).font(.headline).foregroundStyle(.primary).multilineTextAlignment(.center)
                    Text(status).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: 420)
        }
    }
}

struct CatalogEnablingBusyView: View {
    let message: String
    let status: String

    var body: some View {
        VStack(spacing: 24) {
            ProgressView().controlSize(.large).tint(.white)
            VStack(spacing: 8) {
                Text(message).font(.headline).foregroundStyle(.white).multilineTextAlignment(.center)
                Text(status).font(.subheadline).foregroundStyle(.white.opacity(0.85)).multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: 420)
    }
}

struct LoadingScreen: View {
    let message: String
    let status: String
    let progress: Double
    let downloadedBytes: Int64
    let totalBytes: Int64

    @Environment(\.bindrAccent) private var bindrAccent
    @Environment(\.colorScheme) private var colorScheme
    private var foreground: Color { colorScheme == .dark ? .white : Color(white: 0.08) }

    private var byteProgressText: String {
        guard totalBytes > 0 else { return "Calculating download size…" }
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB]
        f.countStyle = .file
        f.includesUnit = true
        return "\(f.string(fromByteCount: downloadedBytes)) / \(f.string(fromByteCount: totalBytes))"
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text(message).font(.headline).foregroundStyle(.primary).multilineTextAlignment(.center)
                    Text(status).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                VStack(spacing: 10) {
                    CAProgressBar(fraction: progress, fillColor: bindrAccent, height: 3)
                        .frame(width: min(UIScreen.main.bounds.width - 64, 320))
                    Text("\(Int((min(max(progress, 0), 1) * 100).rounded()))% complete")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text(byteProgressText).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: 420)
        }
    }
}

#Preview("Idle") {
    LaunchWordmarkView(elapsedLabel: "0.8s")
        .environment(\.bindrAccent, Color(hex: "4f46e5"))
}

#Preview("CloudKit syncing") {
    LaunchWordmarkView(isSyncingCloudKit: true, elapsedLabel: "3.2s")
        .environment(\.bindrAccent, Color(hex: "4f46e5"))
}

#Preview("Catalog download") {
    LaunchWordmarkView(
        progress: LaunchProgressState(
            message: "Downloading card data",
            status: "Pokémon TCG · 12,400 cards",
            fraction: 0.62,
            downloadedBytes: 3_200_000,
            totalBytes: 5_100_000,
            hasByteProgress: true
        ),
        elapsedLabel: "7.1s"
    )
    .environment(\.bindrAccent, Color(hex: "4f46e5"))
}
