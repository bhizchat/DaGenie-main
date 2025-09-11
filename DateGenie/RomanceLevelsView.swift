//  RomanceLevelsView.swift
//  DateGenie
//
//  Shows four relationship tiers in a paging card.
//  Images should be added to Assets.xcassets with names:
//  level1_movers, level2_duo, level3_winners, level4_legendary

import SwiftUI

struct RomanceLevelsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    private struct Level: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let imageName: String
    }

    private let levels: [Level] = [
        Level(title: "Level 1 – Monthly Movers (≈ 12+ points / top 48 %)",
              subtitle: "One date a month? You’re already ahead of half of couples",
              imageName: "level1_movers"),
        Level(title: "Level 2 – Double-Date Duo (≈ 24–35 pts / top 25 %)",
              subtitle: "Two to three dates each month puts you in the top quarter.",
              imageName: "level2_duo"),
        Level(title: "Level 3 – Weekly Winners (≈ 50+ pts / top 10 %)",
              subtitle: "Weekly date night? You’re in the relationship big leagues — top 10 %!",
              imageName: "level3_winners"),
        Level(title: "Level 4 – Legendary Lovers (100+ pts / elite tier)",
              subtitle: "Legendary status unlocked. Keep the love story rolling!",
              imageName: "level4_legendary")
    ]

    var body: some View {
        VStack {
            TabView(selection: $page) {
                ForEach(Array(levels.enumerated()), id: \ .offset) { idx, level in
                    VStack(spacing: 12) {
                        Text(level.title)
                            .font(.subheadline.bold())
                            .multilineTextAlignment(.center)
                        Image(level.imageName)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 260)
                            .cornerRadius(8)
                        Text(level.subtitle)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .tag(idx)
                }
            }
            
            .frame(maxHeight: .infinity)
            .overlay(
                HStack {
                    if page > 0 {
                        Button(action: { withAnimation { page -= 1 } }) {
                            Image(systemName: "chevron.left")
                                .font(.title)
                                .bold()
                                .padding()
                        }
                    }
                    Spacer()
                    if page < levels.count - 1 {
                        Button(action: { withAnimation { page += 1 } }) {
                            Image(systemName: "chevron.right")
                                .font(.title)
                                .bold()
                                .padding()
                        }
                    }
                }
                .foregroundColor(.primary)
                .padding(.horizontal)
            )

            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(.pink)
                .padding(.bottom, 16)
        }
        .presentationDetents([.medium, .large])
    }
}

#if DEBUG
struct RomanceLevelsView_Previews: PreviewProvider {
    static var previews: some View {
        RomanceLevelsView()
    }
}
#endif
