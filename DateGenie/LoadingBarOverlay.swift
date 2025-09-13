//  LoadingBarOverlay.swift
//  DateGenie

import SwiftUI

struct LoadingBarOverlay: View {
    @Binding var progress: Double
    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 6) {
                ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 220, height: 6)
                Capsule()
                    .fill(Color.accentPrimary)
                    .frame(width: 220 * progress, height: 6)
                            }
                Text("Loading…")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }
        }
    }
}

struct DoneOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            Text("Done")
                .font(.title2).bold()
                .foregroundColor(.white)
        }
    }
}
