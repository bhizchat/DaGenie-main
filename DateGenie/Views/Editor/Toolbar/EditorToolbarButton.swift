import SwiftUI

struct EditorToolbarButton: View {
    let title: String
    let system: String
    let action: () -> Void

    var body: some View {
        Button(action: { UIImpactFeedbackGenerator(style: .light).impactOccurred(); action() }) {
            VStack(spacing: 6) {
                Image(systemName: system)
                    .foregroundColor(.white)
                    .font(.system(size: 20, weight: .semibold))
                Text(title)
                    .foregroundColor(.white)
                    .font(.system(size: 12, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}


