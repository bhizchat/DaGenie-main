import SwiftUI

struct Chip: View {
    let label: String
    var icon: String? = nil
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                }
                Text(label)
                    .font(.callout)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .frame(maxWidth: .infinity)
            .background(
                Group {
                    if isSelected {
                        LinearGradient(colors: [Color.accentPink, Color.accentPink.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    } else {
                        Color.clear
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accentPink, lineWidth: 1)
            )
            .cornerRadius(12)
            .foregroundColor(isSelected ? .white : Color.accentPink)
        }
        .buttonStyle(.plain)
    }
}
