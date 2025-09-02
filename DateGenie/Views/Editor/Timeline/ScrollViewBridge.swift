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
            // No runtime contentInset centering. We use spacer views inside content for centering.
            let _ = scrollView.bounds.width / 2
            // Configure scroll physics to reduce edge friction and avoid auto insets
            scrollView.contentInsetAdjustmentBehavior = .never
            // Prefer natural glide and rubber-band bounce for editor timeline feel
            scrollView.decelerationRate = .normal
            scrollView.alwaysBounceHorizontal = true
            scrollView.alwaysBounceVertical = false
            scrollView.bounces = true
            scrollView.isDirectionalLockEnabled = true
            scrollView.delaysContentTouches = false
            scrollView.canCancelContentTouches = true
            if let x = targetX {
                if !(scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating) {
                    let minX: CGFloat = 0
                    let maxX = max(0, scrollView.contentSize.width - scrollView.bounds.width)
                    let clamped = min(max(x, minX), maxX)
                    // Pixel-round to device scale to eliminate sub-pixel jitter
                    let scale = scrollView.window?.screen.scale ?? UIScreen.main.scale
                    let rounded = (clamped * scale).rounded(.toNearestOrAwayFromZero) / scale
                    if abs(scrollView.contentOffset.x - rounded) > 0.5 {
                        context.coordinator.suppressNextDidScroll = true
                        scrollView.setContentOffset(CGPoint(x: rounded, y: 0), animated: false)
                        DispatchQueue.main.async {
                            DispatchQueue.main.async { context.coordinator.suppressNextDidScroll = false }
                        }
                    }
                }
            }
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var onScroll: (CGFloat, Bool, Bool, Bool) -> Void
        weak var scrollView: UIScrollView?
        var suppressNextDidScroll: Bool = false
        init(onScroll: @escaping (CGFloat, Bool, Bool, Bool) -> Void) { self.onScroll = onScroll }
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard !suppressNextDidScroll else { return }
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
        // Clamp final landing position without fighting momentum mid-flight
        func scrollViewWillEndDragging(_ scrollView: UIScrollView,
                                       withVelocity velocity: CGPoint,
                                       targetContentOffset: UnsafeMutablePointer<CGPoint>) {
            let minX: CGFloat = 0
            let maxX = max(0, scrollView.contentSize.width - scrollView.bounds.width)
            let proposed = targetContentOffset.pointee.x
            targetContentOffset.pointee.x = min(max(proposed, minX), maxX)
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


