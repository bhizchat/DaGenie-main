//  ErrorOverlay.swift
//  DateGenie
//
//  A simple reusable error toast modifier.
//
import SwiftUI

struct ErrorToast: ViewModifier {
    @Binding var errorMessage: String?

    func body(content: Content) -> some View {
        ZStack {
            content
            if let message = errorMessage {
                VStack {
                    Spacer()
                    Text(message)
                        .font(.subheadline)
                        .padding()
                        .background(Color.red.opacity(0.9))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .padding()
                        .transition(.move(edge: .bottom))
                        .animation(.easeInOut, value: message)
                }
            }
        }
    }
}

extension View {
    func errorToast(message: Binding<String?>) -> some View {
        self.modifier(ErrorToast(errorMessage: message))
    }
}
