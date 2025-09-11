//  LevelView.swift – screenshot #3 stars + timer
import SwiftUI

struct LevelView: View {
    let levelNumber: Int
    let totalMissions: Int = 5
    @State private var completed = 0
    @State private var timeRemaining: TimeInterval = 3 * 60 * 60 // 3 hrs
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack {
            header
            Spacer()
            stars
            Spacer()
            Button("Complete adventure") { completed = totalMissions }
                .buttonStyle(.borderedProminent)
                .padding(.bottom)
        }
        .padding()
        .onReceive(timer) { _ in
            if timeRemaining > 0 { timeRemaining -= 1 }
        }
    }

    private var header: some View {
        HStack {
            Image("welcome_genie")
                .resizable()
                .frame(width: 48, height: 48)
            VStack(alignment: .leading) {
                Text("Level \(levelNumber)")
                    .font(.pressStart(24)).foregroundColor(.pink)
                Text("You have 2 hours to complete your adventure\nGood luck!")
                    .font(.caption)
            }
            Spacer()
            Text(timeString)
                .font(.title2).monospacedDigit()
        }
    }

    private var stars: some View {
        VStack(spacing: 30) {
            ForEach(0..<totalMissions, id: \ .self) { idx in
                Image(systemName: idx < completed ? "star.fill" : "star")
                    .resizable()
                    .frame(width: 80, height: 80)
                    .foregroundColor(idx < completed ? .yellow : .pink)
                    .onTapGesture { if idx == completed { completed += 1 } }
            }
        }
    }

    private var timeString: String {
        let h = Int(timeRemaining) / 3600
        let m = Int(timeRemaining) % 3600 / 60
        let s = Int(timeRemaining) % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}

#if DEBUG
struct LevelView_Previews: PreviewProvider {
    static var previews: some View {
        LevelView(levelNumber: 1)
    }
}
#endif
