import SwiftUI
import UIKit

/// Opens the side menu with a left screen-edge pan. Unlike SwiftUI `DragGesture`, this uses `UIScreenEdgePanGestureRecognizer` so it does not lose to inner `UIScrollView` pans.
struct LeftEdgeOpenMenuGesture: UIViewRepresentable {
    var isEnabled: Bool
    var onOpen: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onOpen: onOpen)
    }

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        let pan = UIScreenEdgePanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.edges = .left
        pan.delegate = context.coordinator
        v.addGestureRecognizer(pan)
        context.coordinator.edgePan = pan
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onOpen = onOpen
        uiView.isUserInteractionEnabled = isEnabled
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onOpen: () -> Void
        weak var edgePan: UIScreenEdgePanGestureRecognizer?

        init(onOpen: @escaping () -> Void) {
            self.onOpen = onOpen
        }

        @objc func handlePan(_ gr: UIScreenEdgePanGestureRecognizer) {
            guard gr.state == .ended else { return }
            let t = gr.translation(in: gr.view)
            if t.x > 56 {
                onOpen()
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
