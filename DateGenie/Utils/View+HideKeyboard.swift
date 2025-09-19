//  View+HideKeyboard.swift
//  Dismisses keyboard on tap outside fields
import SwiftUI

#if canImport(UIKit)
extension View {
    func hideKeyboardOnTap() -> some View {
        self.simultaneousGesture(
            TapGesture().onEnded { _ in
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        )
    }
}
#endif
