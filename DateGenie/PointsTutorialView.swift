//  PointsTutorialView.swift
//  DateGenie
//  Shown the very first time a user taps "Get Romance Points".
//  Created by AI.

import SwiftUI

struct PointsTutorialView: View {
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image("points_tutorial")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 280)
                .padding(.horizontal, 32)
            Text("Snap a pic of your date night and earn Romance Points!")
                .font(.title2)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
            Button(action: onContinue) {
                Text("Open Camera")
                    .font(.custom("VT323", size: 22))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.pink)
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
        .padding()
        .presentationDetents([.medium])
    }
}

#if DEBUG
struct PointsTutorialView_Previews: PreviewProvider {
    static var previews: some View {
        PointsTutorialView(onContinue: {})
    }
}
#endif
