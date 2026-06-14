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
    private let fillGradientLayer = CAGradientLayer()
    private let shimmerLayer = CAGradientLayer()

    var fillColor: UIColor = .systemBlue {
        didSet { updateFillColors() }
    }
    var fillGradientColors: [UIColor] = [] {
        didSet { updateFillColors() }
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
        fillLayer.addSublayer(fillGradientLayer)
        fillLayer.addSublayer(shimmerLayer)
        fillLayer.masksToBounds = true

        fillGradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        fillGradientLayer.endPoint = CGPoint(x: 1, y: 0.5)

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
        updateFillColors()
        fillGradientLayer.frame = fillLayer.bounds
        shimmerLayer.frame = CGRect(x: 0, y: 0, width: bounds.width * 2, height: h)
        startShimmer()
    }

    private func updateFillColors() {
        let colors = fillGradientColors.isEmpty ? [fillColor, fillColor] : fillGradientColors
        fillGradientLayer.colors = colors.map(\.cgColor)
        fillLayer.backgroundColor = colors.first?.cgColor ?? fillColor.cgColor
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
            fillGradientLayer.frame = fillLayer.bounds
            CATransaction.commit()
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            fillLayer.frame = CGRect(x: 0, y: 0, width: targetWidth, height: bounds.height)
            fillGradientLayer.frame = fillLayer.bounds
            CATransaction.commit()
        }
    }
}

struct CAProgressBar: UIViewRepresentable {
    var fraction: Double
    var fillColor: Color
    var fillGradientColors: [Color] = []
    var height: CGFloat = 6

    func makeUIView(context: Context) -> _CAProgressBarView {
        let v = _CAProgressBarView()
        v.setContentHuggingPriority(.defaultLow, for: .horizontal)
        v.setContentHuggingPriority(.required, for: .vertical)
        return v
    }

    func updateUIView(_ uiView: _CAProgressBarView, context: Context) {
        uiView.fillColor = UIColor(fillColor)
        uiView.fillGradientColors = fillGradientColors.map { UIColor($0) }
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

struct CYCyclingTitle: UIViewRepresentable {
    let messages: [String]
    let color: UIColor
    let font: UIFont

    func makeUIView(context: Context) -> _CYCyclingTitleView {
        let v = _CYCyclingTitleView()
        v.configure(messages: messages, color: color, font: font)
        return v
    }

    func updateUIView(_ uiView: _CYCyclingTitleView, context: Context) {
        uiView.configure(messages: messages, color: color, font: font)
    }
}

final class _CYCyclingTitleView: UIView {
    private var textLayers: [CATextLayer] = []
    private var appliedSignature: String = ""

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 24)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        for textLayer in textLayers {
            textLayer.frame = bounds
        }
    }

    func configure(messages: [String], color: UIColor, font: UIFont) {
        let signature = messages.joined(separator: "|") + "|\(font.pointSize)"
        guard signature != appliedSignature else { return }
        appliedSignature = signature
        let safeMessages = messages.isEmpty ? ["Syncing iCloud"] : messages

        textLayers.forEach { $0.removeFromSuperlayer() }
        textLayers.removeAll()

        for (index, message) in safeMessages.enumerated() {
            let textLayer = CATextLayer()
            textLayer.contentsScale = UIScreen.main.scale
            textLayer.alignmentMode = .center
            textLayer.truncationMode = .end
            textLayer.foregroundColor = color.cgColor
            textLayer.font = font
            textLayer.fontSize = font.pointSize
            textLayer.string = message
            textLayer.frame = bounds
            textLayer.opacity = index == 0 ? 1 : 0
            layer.addSublayer(textLayer)
            textLayers.append(textLayer)
        }

        let step: CFTimeInterval = 3.0
        let count = safeMessages.count
        let total = step * Double(count)

        for (index, textLayer) in textLayers.enumerated() {
            textLayer.removeAnimation(forKey: "cy_opacity_cycle")

            var values: [NSNumber] = []
            var keyTimes: [NSNumber] = []
            for slot in 0...count {
                let activeIndex = slot % count
                values.append(NSNumber(value: activeIndex == index ? 1.0 : 0.0))
                keyTimes.append(NSNumber(value: Double(slot) / Double(count)))
            }

            let anim = CAKeyframeAnimation(keyPath: "opacity")
            anim.values = values
            anim.keyTimes = keyTimes
            anim.calculationMode = .discrete
            anim.duration = total
            anim.repeatCount = .infinity
            anim.isRemovedOnCompletion = false
            anim.fillMode = .forwards
            textLayer.add(anim, forKey: "cy_opacity_cycle")
        }
    }
}

// MARK: - Launch wordmark view

struct LaunchWordmarkView: View {
    var progress: LaunchProgressState? = nil
    var isSyncingCloudKit: Bool = false
    var onRevealComplete: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme
    @State private var logoVisible = false
    @State private var statusVisible = false
    @State private var hasStartedAnimation = false
    @State private var hasFiredRevealComplete = false
    private let loadingStatusMessages = [
        "Syncing iCloud",
        "Loading Cards",
        "Updating Pricing",
        "Loading Dashboard"
    ]

    private var foreground: Color { colorScheme == .dark ? .white : Color(white: 0.08) }
    private var subtle: Color { foreground.opacity(0.38) }
    private var launchBrandPrimary: Color { Color(red: 0.93, green: 0.16, blue: 0.62) }
    private var launchBrandSecondary: Color { Color(red: 0.49, green: 0.34, blue: 1.00) }
    private var launchBrandCyan: Color { Color(red: 0.08, green: 0.78, blue: 0.94) }
    private var launchBrandGradient: LinearGradient {
        LinearGradient(
            colors: [launchBrandCyan, launchBrandSecondary, launchBrandPrimary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

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
                    launchBrandPrimary.opacity(colorScheme == .dark ? 0.18 : 0.10),
                    launchBrandSecondary.opacity(colorScheme == .dark ? 0.06 : 0.04),
                    .clear
                ],
                center: .init(x: 0.5, y: 0.35),
                startRadius: 0,
                endRadius: 380
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [
                    launchBrandCyan.opacity(colorScheme == .dark ? 0.10 : 0.06),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 400
            )
            .offset(x: 60, y: -60)
            .ignoresSafeArea()

            VStack(spacing: 10) {
                BindrBrandLogoView(maxWidth: 300)
                    .scaleEffect(logoVisible ? 1 : 0.92)
                    .opacity(logoVisible ? 1 : 0)
            }
            .padding(.horizontal, 40)
            .offset(y: -58)

            VStack {
                Spacer()
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    statusArea
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(height: 112, alignment: .center)
                        .opacity(statusVisible ? 1 : 0)
                        .offset(y: statusVisible ? 0 : 12)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 52)
            }
            .allowsHitTesting(false)
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
        launchStatusPanel(
            title: loadingStatusMessages.first ?? "Syncing iCloud",
            status: "Preparing data…",
            icon: "icloud.and.arrow.down.fill",
            progress: nil
        )
    }

    // MARK: Catalog download progress

    @ViewBuilder
    private func catalogProgressView(_ p: LaunchProgressState) -> some View {
        launchStatusPanel(
            title: p.message,
            status: p.status,
            icon: p.hasByteProgress ? "sparkles" : "square.grid.2x2.fill",
            progress: p
        )
    }

    private func launchStatusPanel(
        title: String,
        status: String,
        icon: String,
        progress: LaunchProgressState?
    ) -> some View {
        VStack(spacing: 10) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(launchBrandGradient.opacity(colorScheme == .dark ? 0.58 : 0.48))
                    )
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.18 : 0.42), lineWidth: 0.8)
                    }
                if progress == nil {
                    PulseDots(color: launchBrandPrimary.opacity(0.78))
                }
            }
            .frame(width: 36, alignment: .center)

            VStack(alignment: .center, spacing: 4) {
                if progress == nil {
                    CYCyclingTitle(
                        messages: loadingStatusMessages,
                        color: UIColor(foreground.opacity(0.92)),
                        font: .systemFont(ofSize: 16, weight: .bold)
                    )
                    .frame(height: 24)
                    .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    Text(title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(foreground.opacity(0.92))
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .multilineTextAlignment(.center)
                }

                Text(status)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(subtle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.center)

                if let progress {
                    VStack(spacing: 7) {
                        CAProgressBar(
                            fraction: progress.fraction,
                            fillColor: launchBrandPrimary,
                            fillGradientColors: [launchBrandCyan, launchBrandSecondary, launchBrandPrimary],
                            height: 4
                        )
                            .frame(width: 220)
                            .clipShape(Capsule())

                        HStack(spacing: 6) {
                            Text("\(Int((min(max(progress.fraction, 0), 1) * 100).rounded()))%")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(foreground.opacity(0.70))
                            if !byteProgressText.isEmpty {
                                Text("·")
                                    .foregroundStyle(subtle)
                                Text(byteProgressText)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(subtle)
                            }
                        }
                        .frame(width: 220, alignment: .center)
                    }
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 10)
        .frame(width: 320, alignment: .center)
    }

    // MARK: Animation sequence

    private func runRevealAnimation() async {
        withAnimation(.spring(response: 0.62, dampingFraction: 0.78)) {
            logoVisible = true
        }

        try? await Task.sleep(nanoseconds: 520_000_000)

        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            statusVisible = true
        }

        try? await Task.sleep(nanoseconds: 150_000_000)

        if !hasFiredRevealComplete {
            hasFiredRevealComplete = true
            Haptics.premiumPulse()
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

    var body: some View {
        LaunchWordmarkView(
            progress: LaunchProgressState(
                message: message,
                status: status,
                fraction: progress,
                downloadedBytes: downloadedBytes,
                totalBytes: totalBytes,
                hasByteProgress: totalBytes > 0
            )
        )
        .environment(\.bindrAccent, bindrAccent)
    }
}

#Preview("Idle") {
    LaunchWordmarkView()
        .environment(\.bindrAccent, Color(hex: "4f46e5"))
}

#Preview("CloudKit syncing") {
    LaunchWordmarkView(isSyncingCloudKit: true)
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
        )
    )
    .environment(\.bindrAccent, Color(hex: "4f46e5"))
}
