import SwiftUI

/// Text that shows a couple of lines and lets the user tap to expand/collapse.
struct ExpandableText: View {
    let text: String
    /// Maximum number of lines when collapsed.
    let collapsedLineLimit: Int
    /// Whether the view starts expanded.
    @State private var expanded: Bool = false

    init(_ text: String, collapsedLineLimit: Int = 2) {
        self.text = text
        self.collapsedLineLimit = collapsedLineLimit
    }

    var body: some View {
        Text(text)
            .lineLimit(expanded ? nil : collapsedLineLimit)
            .animation(.easeInOut(duration: 0.2), value: expanded)
            .onTapGesture { expanded.toggle() }
            .overlay(alignment: .bottomTrailing) {
                if !expanded && text.count > 60 { // heuristic length check
                    Text("Read more…")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.top, 2)
                }
            }
    }
}

#Preview {
    ExpandableText("Take a moody, film noir-style photo of your partner sipping their drink like a detective on a case, caption it 'Undercover at the bar…'")
        .padding()
        .background(Color.red)
}
