import SwiftUI
import UIKit

enum ToastStyle {
    case success
    case error
    case info

    var iconName: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }
}

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let style: ToastStyle
}

private struct ToastBanner: View {
    let message: ToastMessage

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: message.style.iconName)
                .foregroundColor(.white)
                .imageScale(.large)
            Text(message.text)
                .foregroundColor(.white)
                .font(.system(.subheadline, design: .rounded))
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 42)
        .background(Color.black.opacity(0.85))
        .clipShape(Capsule())
        .shadow(radius: 6)
        .padding(.bottom, 24)
    }
}

private struct ToastPresenter: ViewModifier {
    @Binding var message: ToastMessage?

    func body(content: Content) -> some View {
        ZStack {
            content
            if let msg = message {
                VStack {
                    Spacer()
                    ToastBanner(message: msg)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .onAppear { notifyHaptic(for: msg.style) }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: message)
    }

    private func notifyHaptic(for style: ToastStyle) {
        let g = UINotificationFeedbackGenerator()
        g.prepare()
        switch style {
        case .success: g.notificationOccurred(.success)
        case .error: g.notificationOccurred(.error)
        case .info: g.notificationOccurred(.warning)
        }
    }
}

extension View {
    func toast(message: Binding<ToastMessage?>) -> some View {
        self.modifier(ToastPresenter(message: message))
    }
}


