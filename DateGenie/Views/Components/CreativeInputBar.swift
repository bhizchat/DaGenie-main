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
        HStack(spacing: 8) {
            Button(action: onAddTapped) {
                Image("plus_icon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
            }
            .accessibilityLabel("Add image")

            if !attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(attachments) { att in
                            AttachmentChip(attachment: att) {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                    attachments.removeAll { $0.id == att.id }
                                }
                            }
                        }
                    }
                }
                .frame(height: 70)
            }

            ZStack(alignment: .trailing) {
                ZStack(alignment: .topLeading) {
                    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Describe your idea…")
                            .foregroundColor(.secondary)
                            .padding(.leading, 14)
                            .padding(.top, 12)
                    }
                    GrowingTextView(text: $text, contentHeight: $textHeight)
                        .frame(height: min(max(minHeight, textHeight), maxHeight))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 100).fill(Color.white))
                }
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button(action: onSend) {
                        Image("icon_preview_share") // placeholder; replace with send_new
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                    }
                    .padding(.trailing, 10)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .accessibilityLabel("Send")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: 0xD9D9D9)))
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

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.font = .systemFont(ofSize: 17)
        tv.delegate = context.coordinator
        tv.textContainerInset = UIEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text { uiView.text = text }
        DispatchQueue.main.async {
            self.contentHeight = uiView.contentSize.height
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        let parent: GrowingTextView
        init(_ parent: GrowingTextView) { self.parent = parent }
        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            parent.contentHeight = textView.contentSize.height
        }
    }
}

// MARK: - Color helper
private extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self = Color(red: r, green: g, blue: b).opacity(alpha)
    }
}


