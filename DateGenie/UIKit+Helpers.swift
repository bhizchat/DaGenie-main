//
//  UIKit+Helpers.swift
//  DateGenie
//
//  Adds utility functions bridging UIKit for SwiftUI.
//

import UIKit
import SwiftUI

extension UIApplication {
    static func hideKeyboard() {
        shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    func topMostViewController(base: UIViewController? = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }.first) -> UIViewController? {
        if let nav = base as? UINavigationController { return topMostViewController(base: nav.visibleViewController) }
        if let tab = base as? UITabBarController { return topMostViewController(base: tab.selectedViewController) }
        if let presented = base?.presentedViewController { return topMostViewController(base: presented) }
        return base
    }
}

// MARK: - Persistent full-screen presenter for video previews
final class VideoPreviewPresenter {
    static let shared = VideoPreviewPresenter()
    private var window: UIWindow?

    func show<Content: View>(root: Content) {
        guard window == nil else { return }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first else { return }
        let w = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .black
        w.rootViewController = host
        w.windowLevel = .alert + 1
        w.makeKeyAndVisible()
        window = w
    }

    func dismiss() {
        window?.isHidden = true
        window = nil
    }
}

// Lightweight UIKit image picker bridged into SwiftUI
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    var sourceType: UIImagePickerController.SourceType = .photoLibrary

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = sourceType
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ImagePicker
        init(_ parent: ImagePicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            var result: UIImage?
            if let edited = info[.editedImage] as? UIImage {
                result = edited
            } else if let original = info[.originalImage] as? UIImage {
                result = original
            }
            parent.image = result
            picker.dismiss(animated: true)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
