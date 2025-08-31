import SwiftUI

/// Attaches to the underlying UIScrollView of a SwiftUI ScrollView to observe
/// live contentOffset.x and optionally set a target offset when not interacting.
struct ScrollViewBridge: UIViewRepresentable {
    var targetX: CGFloat? = nil
    var onScroll: (CGFloat, Bool, Bool, Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onScroll: onScroll) }

    func makeUIView(context: Context) -> UIView { UIView(frame: .zero) }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            guard let scrollView = enclosingScrollView(from: uiView) else { return }
            if context.coordinator.scrollView !== scrollView {
                scrollView.delegate = context.coordinator
                context.coordinator.scrollView = scrollView
            }
            // Ensure content insets keep a fixed playhead at center
            let center = scrollView.bounds.width / 2
            let inset = pxRound(center, scale: scrollView.window?.windowScene?.screen.scale ?? UIScreen.main.scale)
            let currentInsets = scrollView.contentInset
            if currentInsets.left != inset || currentInsets.right != inset {
                scrollView.contentInset = UIEdgeInsets(top: 0, left: inset, bottom: 0, right: inset)
            }
            // Configure scroll physics to reduce edge friction and avoid auto insets
            scrollView.contentInsetAdjustmentBehavior = .never
            scrollView.decelerationRate = .fast
            if let x = targetX {
                if !(scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating) {
                    let minX = -scrollView.contentInset.left
                    let maxX = scrollView.contentSize.width - scrollView.bounds.width + scrollView.contentInset.right
                    let clamped = min(max(x, minX), maxX)
                    if scrollView.contentOffset.x != clamped {
                        scrollView.setContentOffset(CGPoint(x: clamped, y: 0), animated: false)
                    }
                }
            }
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var onScroll: (CGFloat, Bool, Bool, Bool) -> Void
        weak var scrollView: UIScrollView?
        init(onScroll: @escaping (CGFloat, Bool, Bool, Bool) -> Void) { self.onScroll = onScroll }
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            onScroll(scrollView.contentOffset.x, scrollView.isTracking, scrollView.isDragging, scrollView.isDecelerating)
        }
        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate { onScroll(scrollView.contentOffset.x, scrollView.isTracking, scrollView.isDragging, scrollView.isDecelerating) }
        }
        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            onScroll(scrollView.contentOffset.x, scrollView.isTracking, scrollView.isDragging, scrollView.isDecelerating)
        }
        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
            onScroll(scrollView.contentOffset.x, scrollView.isTracking, scrollView.isDragging, scrollView.isDecelerating)
        }
    }

    private func enclosingScrollView(from view: UIView) -> UIScrollView? {
        var v: UIView? = view.superview
        while let cur = v {
            if let sv = cur as? UIScrollView { return sv }
            v = cur.superview
        }
        return nil
    }
}

private func pxRound(_ x: CGFloat, scale: CGFloat) -> CGFloat {
    (x * scale).rounded(.toNearestOrAwayFromZero) / scale
}


