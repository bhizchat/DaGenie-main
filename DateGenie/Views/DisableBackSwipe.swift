import SwiftUI

// MARK: - DisableBackSwipe
// A tiny helper that disables the interactive pop (back-swipe) gesture while the hosting
// SwiftUI screen is visible, and restores the previous state automatically when it disappears.
// Attach via .background(DisableBackSwipe().frame(width:0,height:0)) on the pushed view.

final class BackSwipeDisablerVC: UIViewController {
    private var previousEnabled: Bool?

    override func viewDidLoad() {
        super.viewDidLoad()
        print("[DisableBackSwipe] viewDidLoad navController: \(navigationController as Any)")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let gesture = navigationController?.interactivePopGestureRecognizer else { return }
        previousEnabled = gesture.isEnabled
        print("[DisableBackSwipe] disabling back-swipe (was \(gesture.isEnabled))")
        gesture.isEnabled = false
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if let prev = previousEnabled {
            navigationController?.interactivePopGestureRecognizer?.isEnabled = prev
            print("[DisableBackSwipe] restored back-swipe to \(prev)")
        }
    }
}

struct DisableBackSwipe: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> BackSwipeDisablerVC {
        BackSwipeDisablerVC()
    }

    func updateUIViewController(_ uiViewController: BackSwipeDisablerVC, context: Context) {}
}
