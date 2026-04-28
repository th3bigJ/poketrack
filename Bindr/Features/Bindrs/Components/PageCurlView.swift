import SwiftUI
import UIKit

/// A SwiftUI wrapper around `UIPageViewController` that provides a realistic
/// book-like page curl transition. Used by both the internal binder view
/// (``BinderDetailView``) and shared social binder previews (``SharedBinderView``)
/// to create a high-fidelity physical experience.
struct PageCurlView<Content: View>: UIViewControllerRepresentable {
    let pageCount: Int
    @Binding var currentPage: Int
    @Binding var isTurning: Bool
    let pageBackgroundColor: UIColor
    @ViewBuilder let pageContent: (Int) -> Content

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let vc = UIPageViewController(
            transitionStyle: .pageCurl,
            navigationOrientation: .horizontal,
            options: [.spineLocation: UIPageViewController.SpineLocation.min.rawValue]
        )
        vc.isDoubleSided = false
        vc.view.backgroundColor = pageBackgroundColor
        vc.view.layer.speed = 0.55
        vc.dataSource = context.coordinator
        vc.delegate = context.coordinator
        context.coordinator.parent = self
        context.coordinator.controllers = (0..<pageCount).map { makeHosting(index: $0) }
        if pageCount > 0 {
            vc.setViewControllers(
                [context.coordinator.controllers[currentPage]],
                direction: .forward,
                animated: false
            )
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIPageViewController, context: Context) {
        let coord = context.coordinator
        coord.parent = self

        let needed = pageCount
        if coord.controllers.count != needed {
            coord.controllers = (0..<needed).map { makeHosting(index: $0) }
        } else {
            for i in 0..<needed {
                (coord.controllers[i] as? UIHostingController<Content>)?.rootView = pageContent(i)
            }
        }

        guard needed > 0 else { return }
        let clampedPage = max(0, min(currentPage, needed - 1))
        let shown = uiViewController.viewControllers?.first
        if shown !== coord.controllers[clampedPage] {
            isTurning = true
            uiViewController.setViewControllers(
                [coord.controllers[clampedPage]],
                direction: clampedPage > (coord.lastPage ?? 0) ? .forward : .reverse,
                animated: true
            )
            coord.lastPage = clampedPage
        }
    }

    private func makeHosting(index: Int) -> UIViewController {
        let hosting = UIHostingController(rootView: pageContent(index))
        hosting.view.backgroundColor = pageBackgroundColor
        hosting.view.isOpaque = true
        return hosting
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: PageCurlView
        var controllers: [UIViewController] = []
        var lastPage: Int?

        init(parent: PageCurlView) {
            self.parent = parent
        }

        func pageViewController(_ pvc: UIPageViewController, viewControllerBefore vc: UIViewController) -> UIViewController? {
            guard let idx = controllers.firstIndex(of: vc), idx > 0 else { return nil }
            return controllers[idx - 1]
        }

        func pageViewController(_ pvc: UIPageViewController, viewControllerAfter vc: UIViewController) -> UIViewController? {
            guard let idx = controllers.firstIndex(of: vc), idx < controllers.count - 1 else { return nil }
            return controllers[idx + 1]
        }

        func pageViewController(_ pvc: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
            parent.isTurning = true
        }

        func pageViewController(
            _ pvc: UIPageViewController,
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            parent.isTurning = false
            guard completed, let shown = pvc.viewControllers?.first,
                  let idx = controllers.firstIndex(of: shown) else { return }
            parent.currentPage = idx
            self.lastPage = idx
        }
    }
}
