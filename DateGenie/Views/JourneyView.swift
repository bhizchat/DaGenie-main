import SwiftUI

struct JourneyView: View {
    @State private var summaries: [JourneyPersistence.LevelSummary] = []

    var body: some View {
        Group {
            if summaries.isEmpty {
                VStack(spacing: 12) {
                    Text("No completed adventures")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Finish an adventure to see it here.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        ForEach(Array(summaries.enumerated()), id: \.offset) { _, item in
                            JourneyLevelCard(level: item.level, runId: item.runId)
                        }
                    }
                    .padding()
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Highlights")
        .onAppear { refresh() }
    }

    private func refresh() {
        JourneyPersistence.shared.listCompletedLevels { arr in
            self.summaries = arr
        }
    }
}

//#if DEBUG
//struct JourneyView_Previews: PreviewProvider {
//    static var previews: some View {
//        NavigationStack { JourneyView() }
//    }
//}
//#endif


