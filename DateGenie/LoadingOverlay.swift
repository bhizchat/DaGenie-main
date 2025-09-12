//  LoadingOverlay.swift
//  DateGenie
//  Simple dimmed full-screen overlay with spinner.

import SwiftUI
import UIKit

struct LoadingOverlay: View {
    var text: String? = nil
    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(1.3)
                if let t = text, !t.isEmpty {
                    Text(t)
                        .font(.headline)
                        .foregroundColor(.white)
                }
            }
        }
    }
}

extension LoadingOverlay {
    private static var current: UIViewController?
    static func show(text: String? = nil) {
        guard current == nil else { return }
        let vc = UIHostingController(rootView: LoadingOverlay(text: text))
        vc.modalPresentationStyle = .overFullScreen
        vc.view.backgroundColor = .clear
        UIApplication.shared.topMostViewController()?.present(vc, animated: true)
        current = vc
    }
    static func hide(completion: (() -> Void)? = nil) {
        if let curr = current {
            curr.dismiss(animated: true) {
                current = nil
                completion?()
            }
        } else {
            completion?()
        }
    }
}
