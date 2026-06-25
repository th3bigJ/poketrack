import SwiftUI
import UIKit

/// Shared mutable handle that RootView holds as a @State so it can
/// imperatively trigger the fade from an onChange handler without waiting
/// for SwiftUI's updateUIView to be scheduled on @MainActor.
final class LaunchFadeHandle {
    private(set) weak var containerView: _FadeContainerView?

    func register(_ view: _FadeContainerView) {
        containerView = view
    }

    /// Start the fade immediately, bypassing SwiftUI's update cycle.
    /// Safe to call multiple times — no-ops after the first successful trigger.
    func triggerFadeIfNeeded(duration: Double, completion: @escaping () -> Void) {
        guard let view = containerView, !view.hasFaded else { return }
        view.hasFaded = true
        view.fadeOut(duration: duration, completion: completion)
    }
}

/// Wraps its SwiftUI content in a UIView whose opacity is animated via CALayer,
/// which runs on the render server and is immune to @MainActor blocking.
/// Use this for the launch overlay so CloudKit/SwiftData @MainActor work
/// cannot stall the fade animation.
struct RenderThreadFadeContainer<Content: View>: UIViewRepresentable {
    let content: Content
    /// When flipped to false the view fades out using a CALayer animation.
    /// Also used as a fallback: if the parent already called handle.triggerFadeIfNeeded
    /// before updateUIView fires, hasFaded will be true and updateUIView skips.
    let isVisible: Bool
    let duration: Double
    let onFadeComplete: () -> Void
    /// Shared handle so the parent can trigger the fade imperatively from an
    /// onChange handler, avoiding @MainActor scheduling delays.
    let handle: LaunchFadeHandle

    func makeUIView(context: Context) -> _FadeContainerView {
        let view = _FadeContainerView()
        let hc = context.coordinator.hostingController
        hc.view.backgroundColor = .clear
        view.addSubview(hc.view)
        hc.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hc.view.topAnchor.constraint(equalTo: view.topAnchor),
            hc.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hc.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hc.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        handle.register(view)
        return view
    }

    func updateUIView(_ uiView: _FadeContainerView, context: Context) {
        context.coordinator.hostingController.rootView = content
        if !isVisible && !uiView.hasFaded {
            uiView.hasFaded = true
            uiView.fadeOut(duration: duration, completion: onFadeComplete)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(content: content) }

    static func dismantleUIView(_ uiView: _FadeContainerView, coordinator: Coordinator) {
        uiView.stopAnimationsRecursively()
        coordinator.hostingController.view.removeFromSuperview()
    }

    final class Coordinator {
        let hostingController: UIHostingController<Content>
        init(content: Content) {
            hostingController = UIHostingController(rootView: content)
        }
    }
}

final class _FadeContainerView: UIView {
    var hasFaded = false

    func fadeOut(duration: Double, completion: @escaping () -> Void) {
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = 1.0
        anim.toValue = 0.0
        anim.duration = duration
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        anim.fillMode = .forwards
        anim.isRemovedOnCompletion = false
        CATransaction.begin()
        CATransaction.setCompletionBlock {
            DispatchQueue.main.async { completion() }
        }
        layer.add(anim, forKey: "launchFade")
        layer.opacity = 0
        CATransaction.commit()
    }

    func stopAnimationsRecursively() {
        removeAnimations(from: self)
    }

    private func removeAnimations(from view: UIView) {
        view.layer.removeAllAnimations()
        view.layer.sublayers?.forEach { $0.removeAllAnimations() }
        for subview in view.subviews {
            removeAnimations(from: subview)
        }
    }
}
