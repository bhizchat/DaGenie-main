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
        let side = 65.0 * scale // left/right margin in Figma
        let inputHeight = 133.0 * scale
        let corner = 100.0 * scale
        let icon = max(20.0, min(32.0, 28.0 * scale))

        HStack(spacing: 0) {
            // Left margin area hosts the plus button centered
            Button(action: onAddTapped) {
                Image("plus_new")
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: icon, height: icon)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .accessibilityLabel("Add image")
            .frame(width: side, height: inputHeight)

            // Input field sized exactly to Figma rect width (1141px)
            ZStack(alignment: .trailing) {
                ZStack(alignment: .topLeading) {
                    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Describe your idea…")
                            .foregroundColor(.secondary)
                            .padding(.leading, 14)
                            .padding(.top, 12)
                    }
                    GrowingTextView(text: $text, contentHeight: $textHeight, maxHeight: maxHeight)
                        .frame(height: min(max(minHeight, textHeight), maxHeight))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: corner).fill(Color.white))
                }
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button(action: onSend) {
                        Image("send_new")
                            .renderingMode(.original)
                            .resizable()
                            .scaledToFit()
                            .frame(width: icon, height: icon)
                    }
                    .padding(.trailing, 12)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .accessibilityLabel("Send")
                }
            }
            .frame(width: screenW - side * 2, height: inputHeight)

            // Right margin keeps symmetry (and tap target space near edge)
            Color.clear.frame(width: side, height: inputHeight)
        }
        .frame(maxWidth: .infinity, minHeight: inputHeight, maxHeight: inputHeight)
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
        tv.delegate = context.coordinator
        tv.textContainerInset = UIEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
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

 
