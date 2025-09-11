//  HuntCardView.swift
//  DateGenie
//
import SwiftUI

struct HuntCardView: View {
    let hunt: HuntTemplate
    var onStart: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(hunt.title)
                .font(.title)
                .multilineTextAlignment(.center)
            Text("⏱️ " + hunt.heroDurationString + "   •   💰 " + hunt.heroBudgetString)
                .foregroundColor(.secondary)
            Spacer()
            Button("Start Hunt") {
                onStart()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(radius: 6)
        .padding()
    }
}

#if DEBUG
struct HuntCardView_Previews: PreviewProvider {
    static var previews: some View {
        HuntCardView(hunt: HuntTemplate(id: "demo", title: "Street Art Quest", city: .campusA, durationMin: 45, budgetUSD: 0, clues: [])) {}
    }
}
#endif
