//  Color+App.swift
//  DateGenie
//
//  Central colour utilities & brand palette
//
import SwiftUI

public extension Color {
    /// Create colour from 0xRRGGBB integer
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }

    // MARK: - Brand colours
    static let nodeTop    = Color(hex: 0xF26D64)
    static let nodeBottom = Color(hex: 0xC9554D)
    static let composerGray = Color(hex: 0xD9D9D9)
}
