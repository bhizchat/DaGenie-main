import SwiftUI
import PhotosUI

struct CreativeInputBar: View {
    @Binding var text: String
    @Binding var attachments: [ImageAttachment]
    var onAddTapped: () -> Void
    var onSend: () -> Void

    @State private var textHeight: CGFloat = 40
    private let minHeight: CGFloat = 40
    private let maxHeight: CGFloat = 120

    var body: some View {
        // Figma-aware sizing based on canvas 1206x2622
        let screenW = UIScreen.main.bounds.width
        let scale = screenW / 1206.0
        let side = 20.0 * scale // outer horizontal padding for grey bar
        let baseHeight = 133.0 * scale
        let innerHeight = max(44.0, baseHeight - 5.0) // white text box height minus 5pt
        let barHeight = innerHeight + 30.0 // grey rectangle height plus 30pt
        let corner = 100.0 * scale
        let icon = max(20.0, min(32.0, 28.0 * scale))
        let placeholderW = 452.0 * scale
        let placeholderH = 58.0 * scale
        // left: base 28×scale, shifted right by 10pt and plus icon + 20pt spacing
        let placeholderLeft = (28.0 * scale) + 10.0 + icon + 20.0
        let placeholderTop = max(0.0, (innerHeight - placeholderH) / 2.0) + 6.5

        HStack(spacing: 0) {
            // Input field sized exactly to Figma rect width (1141px)
            ZStack(alignment: .trailing) {
                // Fixed white rounded rect matching innerHeight
                RoundedRectangle(cornerRadius: corner)
                    .fill(Color.white)
                    .frame(height: innerHeight)
                ZStack(alignment: .topLeading) {
                    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Describe the idea...")
                            .foregroundColor(Color(hex: 0x808080))
                            .frame(width: placeholderW, height: placeholderH, alignment: .leading)
                            .padding(.leading, placeholderLeft)
                            .padding(.top, placeholderTop)
                    }
                    GrowingTextView(text: $text, contentHeight: $textHeight, maxHeight: maxHeight)
                        .frame(height: min(max(minHeight, textHeight), maxHeight))
                        .padding(.leading, 12 + icon + 20)
                        .padding(.trailing, 12)
                        .padding(.vertical, 10)
                }
                // Plus icon inside the text box, inset by ~20pt
                .overlay(alignment: .leading) {
                    Button(action: onAddTapped) {
                        Image("plus_icon")
                            .renderingMode(.original)
                            .resizable()
                            .scaledToFit()
                            .frame(width: icon, height: icon)
                            .padding(.leading, 20)
                    }
                    .accessibilityLabel("Add image")
                }
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button(action: onSend) {
                        Image("send")
                            .renderingMode(.original)
                            .resizable()
                            .scaledToFit()
                            .frame(width: icon, height: icon)
                    }
                    .padding(.trailing, 16)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .accessibilityLabel("Send")
                }
            }
            .frame(width: screenW - side * 2, height: barHeight)

            // Side padding inside grey bar
            Color.clear.frame(width: side, height: barHeight)
        }
        .frame(maxWidth: .infinity, minHeight: barHeight, maxHeight: barHeight)
        .background(Color.composerGray)
    }
}

private struct AttachmentChip: View {
    let attachment: ImageAttachment
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: attachment.image)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 70)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 50))
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.black.opacity(0.8))
                    .padding(4)
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Growing TextView
struct GrowingTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var contentHeight: CGFloat
    var maxHeight: CGFloat?

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.font = .systemFont(ofSize: 17)
        tv.textColor = .black
        tv.delegate = context.coordinator
        // Move caret/content down by 3.5pt total (previous 2 + 1.5)
        tv.textContainerInset = UIEdgeInsets(top: 9.5, left: 0, bottom: 6, right: 0)
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tv.tintColor = .black // cursor color
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text { uiView.text = text }
        DispatchQueue.main.async {
            self.contentHeight = uiView.contentSize.height
            if let m = self.maxHeight {
                let needsScroll = uiView.contentSize.height > m - 0.5
                if uiView.isScrollEnabled != needsScroll {
                    uiView.isScrollEnabled = needsScroll
                    uiView.showsVerticalScrollIndicator = needsScroll
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        let parent: GrowingTextView
        init(_ parent: GrowingTextView) { self.parent = parent }
        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            parent.contentHeight = textView.contentSize.height
            if let m = parent.maxHeight {
                let needsScroll = textView.contentSize.height > m - 0.5
                if textView.isScrollEnabled != needsScroll {
                    textView.isScrollEnabled = needsScroll
                    textView.showsVerticalScrollIndicator = needsScroll
                }
            }
        }
    }
}

 
