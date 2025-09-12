import SwiftUI

/// A simple dropdown selector mimicking a material style menu.
/// - Parameters:
///   - selection: Currently selected option (binding).
///   - options: All available options.
///   - placeholder: Optional placeholder displayed when `selection` is empty.
struct DropdownPicker: View {
    @Binding var selection: String
    var options: [String]
    var placeholder: String? = nil

    @State private var expanded = false
    private let cornerRadius: CGFloat = 6

    var body: some View {
        ZStack(alignment: .top) {
            // Control
            Button(action: { withAnimation(.easeInOut) { expanded.toggle() } }) {
                HStack {
                    Text(selection.isEmpty ? (placeholder ?? "Select") : selection)
                        .foregroundColor(.white)
                        .font(.system(size: 17, weight: .semibold))
                    Spacer(minLength: 12)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.accentColor)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Color(.separator), lineWidth: 1)
                )
                // Make the whole bar tappable
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
            }
            .buttonStyle(.plain)

            // Dropdown list
            if expanded {
                VStack(spacing: 0) {
                    ForEach(options, id: \.self) { option in
                        Button(action: {
                            selection = option
                            withAnimation(.easeInOut) { expanded = false }
                        }) {
                            HStack {
                                Text(option)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if option == selection {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .padding(.horizontal, 16)
                            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                            // Expand tappable area to full row
                            .contentShape(Rectangle())
                            .background(option == selection ? Color.accentColor.opacity(0.18) : Color.clear)
                        }
                        .buttonStyle(.plain)
                        if option != options.last {
                            Divider().frame(height: 1).background(Color.white.opacity(0.08))
                        }
                    }
                }
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .shadow(color: Color.black.opacity(0.25), radius: 4, x: 0, y: 2)
                .padding(.top, 48) // push below control height
                .zIndex(2)
            }
        }
        .animation(.default, value: expanded)
        // Close when tapping outside (behind menu so it doesn't steal taps)
        .background(
            Group {
                if expanded {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation(.easeInOut) { expanded = false } }
                }
            }
        )
    }
}
