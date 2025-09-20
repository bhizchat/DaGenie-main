//
//  UIKit+Helpers.swift
//  DateGenie
//
//  Adds utility functions bridging UIKit for SwiftUI.
//

import UIKit
import SwiftUI
import UniformTypeIdentifiers

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

// Legacy VideoPreviewPresenter removed (replaced by CapcutEditorView presentation)

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

// MARK: - Audio document picker

struct AudioPicker: UIViewControllerRepresentable {
    typealias Completion = (URL?) -> Void
    let onPick: Completion

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [
            UTType.audio,
            UTType(filenameExtension: "mp3")!,
            UTType(filenameExtension: "m4a")!,
            UTType(filenameExtension: "wav")!,
        ]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: Completion
        init(onPick: @escaping Completion) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { onPick(nil); return }
            var accessed = false
            if url.startAccessingSecurityScopedResource() { accessed = true }
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }

            let fm = FileManager.default
            let ext = url.pathExtension.isEmpty ? "m4a" : url.pathExtension
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent("picked_audio_\(UUID().uuidString).\(ext)")
            do {
                // Prefer a direct copy when possible
                if fm.fileExists(atPath: dest.path) { try? fm.removeItem(at: dest) }
                if fm.fileExists(atPath: url.path) {
                    try fm.copyItem(at: url, to: dest)
                    onPick(dest)
                    return
                }
                // Fallback: read bytes then write to dest
                let data = try Data(contentsOf: url)
                try data.write(to: dest, options: .atomic)
                onPick(dest)
            } catch {
                // If everything fails, return original URL (may still work on some providers)
                onPick(url)
            }
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onPick(nil)
        }
    }
}
