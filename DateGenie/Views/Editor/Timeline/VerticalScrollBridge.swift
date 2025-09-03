import SwiftUI

struct VerticalScrollBridge: UIViewRepresentable {
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
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var onScroll: (CGFloat, Bool, Bool, Bool) -> Void
        weak var scrollView: UIScrollView?
        init(onScroll: @escaping (CGFloat, Bool, Bool, Bool) -> Void) { self.onScroll = onScroll }
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            onScroll(scrollView.contentOffset.y, scrollView.isTracking, scrollView.isDragging, scrollView.isDecelerating)
        }
        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate { onScroll(scrollView.contentOffset.y, scrollView.isTracking, scrollView.isDragging, scrollView.isDecelerating) }
        }
        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            onScroll(scrollView.contentOffset.y, scrollView.isTracking, scrollView.isDragging, scrollView.isDecelerating)
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


