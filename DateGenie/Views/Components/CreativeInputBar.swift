import SwiftUI
import PhotosUI

struct CreativeInputBar: View {
    @Binding var text: String
    @Binding var attachments: [ImageAttachment]
    var onAddTapped: () -> Void
    var onSend: () -> Void
    var isUploading: Bool = false

    @State private var textHeight: CGFloat = 40
    private let minHeight: CGFloat = 40
    private let maxHeight: CGFloat = 120

    var body: some View {
        // Layout constants
        let screenW: CGFloat = UIScreen.main.bounds.width
        let scale: CGFloat = screenW / 1206
        let side: CGFloat = 20 * scale // outer horizontal padding for grey bar
        let corner: CGFloat = 100 * scale
        let icon: CGFloat = max(20, min(32, 28 * scale))
        let textMaxHeight: CGFloat? = self.maxHeight
        let sendReserve: CGFloat = 36 // reserve space for send icon on the right
        // Inner white bubble height equals text content height (no extra growth bump)
        let innerHeight: CGFloat = min(max(minHeight, textHeight), maxHeight)
        // Chip row measurements
        let chipHeight: CGFloat = 70
        let chipRowVPad: CGFloat = 10
        let chipRowHeight: CGFloat = attachments.isEmpty ? 0 : (chipHeight + chipRowVPad)
        let barHeight: CGFloat = innerHeight + 30 + chipRowHeight
        // Padding used by the text view (kept in sync with placeholder below)
        let textLeadingPadding: CGFloat = 12 + icon + 20
        let textTrailingPadding: CGFloat = 12
        let textVerticalPadding: CGFloat = 10

        HStack(spacing: 0) {
            // Input field sized exactly to Figma rect width (1141px)
            VStack(alignment: .trailing, spacing: chipRowVPad) {
                if !attachments.isEmpty {
                    // Small rounded attachment chips inside grey bar
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(attachments) { item in
                                AttachmentChip(attachment: item, onRemove: {
                                    // Remove only this specific item
                                    attachments.removeAll { $0.id == item.id }
                                })
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                    }
                    .frame(height: chipHeight)
                    .scrollDisabled(true)
                }
                ZStack(alignment: .trailing) {
                // Fixed white rounded rect matching innerHeight
                RoundedRectangle(cornerRadius: corner)
                    .fill(Color.white)
                    .frame(height: innerHeight)
                ZStack(alignment: .topLeading) {
                    GeometryReader { geo in
                        let textWidth = max(1, geo.size.width - (textLeadingPadding) - (textTrailingPadding))
                        GrowingTextViewFixed(
                            text: $text,
                            height: $textHeight,
                            availableWidth: textWidth,
                            minHeight: minHeight,
                            maxHeight: maxHeight,
                            trailingInset: sendReserve
                        )
                        .frame(height: min(max(minHeight, textHeight), maxHeight))
                        .padding(.leading, textLeadingPadding)
                        .padding(.trailing, textTrailingPadding)
                        .padding(.vertical, textVerticalPadding)
                    }
                    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Describe the Animation Idea...")
                            .foregroundColor(Color(hex: 0x808080))
                            .padding(.leading, textLeadingPadding)
                            .padding(.trailing, textTrailingPadding)
                            .padding(.top, textVerticalPadding + 5.5)
                            .padding(.bottom, textVerticalPadding)
                    }
                }
                // Plus icon inside the text box at leading with ~20pt inset (keeps position while expanding)
                .overlay(alignment: .leading) {
                    Button(action: onAddTapped) {
                        Image("plus_icon")
                            .renderingMode(.original)
                            .resizable()
                            .scaledToFit()
                            .frame(width: icon, height: icon)
                            .padding(.leading, 20)
                    }
                    .disabled(attachments.count >= 3)
                    .opacity(attachments.count >= 3 ? 0.4 : 1.0)
                    .accessibilityLabel("Add image")
                }
                // Send icon appears at trailing when typing (keeps position while expanding)
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if isUploading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .frame(width: icon, height: icon)
                            .padding(.trailing, 16)
                            .accessibilityLabel("Uploading image")
                    } else {
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
                        .disabled(isUploading)
                    }
                }
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

struct AttachmentChip: View {
    let attachment: ImageAttachment
    let onRemove: () -> Void

    var body: some View {
        Button(action: onRemove) {
            ZStack(alignment: .topTrailing) {
                Image(uiImage: attachment.image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 70)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 10))
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 22, height: 22)
                        .shadow(color: Color.black.opacity(0.08), radius: 1, x: 0, y: 0)
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.black)
                }
                .frame(width: 36, height: 36, alignment: .topTrailing) // visual + large tap target
                .offset(x: -2, y: 2)
            }
        }
        .buttonStyle(.plain)
        .highPriorityGesture(TapGesture().onEnded { onRemove() })
        .contentShape(Rectangle())
        .accessibilityLabel("Remove image")
    }
}

// MARK: - Growing TextView (continuous height, caret-safe)
struct GrowingTextViewFixed: UIViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    let availableWidth: CGFloat
    let minHeight: CGFloat
    let maxHeight: CGFloat
    let trailingInset: CGFloat
    // Optional focus control for callers that want programmatic focus.
    var isFirstResponder: Binding<Bool>? = nil

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.font = .systemFont(ofSize: 17)
        tv.textColor = .black
        tv.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: trailingInset)
        tv.textContainer.lineFragmentPadding = 0
        tv.textContainer.widthTracksTextView = true
        tv.textContainer.lineBreakMode = .byWordWrapping
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tv.setContentHuggingPriority(.required, for: .vertical)
        tv.returnKeyType = .done
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text { uiView.text = text }
        recalcHeight(for: uiView)
        if let wantFocus = isFirstResponder?.wrappedValue {
            if wantFocus && !uiView.isFirstResponder {
                uiView.becomeFirstResponder()
                // reset flag to prevent repeated calls
                DispatchQueue.main.async { self.isFirstResponder?.wrappedValue = false }
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    // iOS 16+: Let SwiftUI query our ideal size for the proposed width
    @available(iOS 16.0, *)
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let proposedWidth = proposal.replacingUnspecifiedDimensions().width
        let width = max(1, proposedWidth)
        uiView.layoutManager.ensureLayout(for: uiView.textContainer)
        let fit = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        let uncapped = max(minHeight, fit)
        let newHeight = min(uncapped, maxHeight)
        if abs(height - newHeight) > 0.5 {
            DispatchQueue.main.async { self.height = newHeight }
        }
        let shouldScroll = fit > maxHeight - 0.5
        if uiView.isScrollEnabled != shouldScroll {
            uiView.isScrollEnabled = shouldScroll
            uiView.showsVerticalScrollIndicator = shouldScroll
        }
        DispatchQueue.main.async {
            let caret = uiView.caretRect(for: uiView.endOfDocument)
            uiView.scrollRectToVisible(caret, animated: false)
            if uiView.isScrollEnabled {
                let bottomY = max(0, uiView.contentSize.height - uiView.bounds.height)
                if abs(uiView.contentOffset.y - bottomY) > 0.5 {
                    uiView.setContentOffset(CGPoint(x: 0, y: bottomY), animated: false)
                }
            }
        }
        return CGSize(width: width, height: newHeight)
    }

    private func recalcHeight(for tv: UITextView) {
        // Force glyph layout, then measure with known width
        tv.layoutManager.ensureLayout(for: tv.textContainer)
        let fit = tv.sizeThatFits(CGSize(width: availableWidth, height: .greatestFiniteMagnitude)).height
        let uncapped = max(minHeight, fit)
        let newHeight = min(uncapped, maxHeight)
        let heightChanged = abs(height - newHeight) > 0.5
        if heightChanged { height = newHeight }

        // Decide scrolling from uncapped fit
        let shouldScroll = fit > maxHeight - 0.5
        if tv.isScrollEnabled != shouldScroll {
            tv.isScrollEnabled = shouldScroll
            tv.showsVerticalScrollIndicator = shouldScroll
        }

        // After frame updates, ensure caret is visible at bottom
        DispatchQueue.main.async {
            tv.layoutIfNeeded()
            let caret = tv.caretRect(for: tv.endOfDocument)
            tv.scrollRectToVisible(caret, animated: false)
            if tv.isScrollEnabled {
                let bottomY = max(0, tv.contentSize.height - tv.bounds.height)
                if abs(tv.contentOffset.y - bottomY) > 0.5 {
                    tv.setContentOffset(CGPoint(x: 0, y: bottomY), animated: false)
                }
            }
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: GrowingTextViewFixed
        init(_ parent: GrowingTextViewFixed) { self.parent = parent }
        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            parent.recalcHeight(for: textView)
        }
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            // Dismiss keyboard on return and prevent newline
            if text == "\n" {
                textView.resignFirstResponder()
                parent.isFirstResponder?.wrappedValue = false
                return false
            }
            return true
        }
    }
}

 
