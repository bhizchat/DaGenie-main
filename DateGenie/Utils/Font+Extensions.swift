//  Font+Extensions.swift
//  Provides convenient helpers for custom pixel fonts.
//  Ensure the "Press Start 2P" and "VT323" .ttf files are added to the project
//  and listed in Info.plist under "Fonts provided by application".
import SwiftUI

extension Font {
    static func pressStart(_ size: CGFloat) -> Font {
        Font.custom("PressStart2P-Regular", size: size)
    }

    static func vt323(_ size: CGFloat) -> Font {
        Font.custom("VT323-Regular", size: size)
    }
}
