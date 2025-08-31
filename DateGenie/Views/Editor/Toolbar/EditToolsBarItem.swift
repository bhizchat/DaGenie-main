import SwiftUI

struct EditToolsBarItem: View {
    let assetName: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: { UIImpactFeedbackGenerator(style: .light).impactOccurred(); action() }) {
            VStack(spacing: title.isEmpty ? 0 : 3) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(assetName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                        .foregroundColor(.white)
                }
                if !title.isEmpty {
                    Text(title)
                        .foregroundColor(.white)
                        .font(.system(size: 11, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 2)
        }
        .buttonStyle(.plain)
    }
}


