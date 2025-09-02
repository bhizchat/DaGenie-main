import SwiftUI
import UIKit

struct CaptionBarView: View {
    // Primitive bindings (safe to mutate from child)
    @Binding var committedText: String
    @Binding var verticalNormalized: CGFloat   // 0...1 within canvas height
    @Binding var isEditing: Bool

    // Parent-owned focus binding
    var focus: FocusState<Bool>.Binding

    let canvasRect: CGRect // parent sets a canvas-sized container
    let onTapToEdit: () -> Void
    let onDone: () -> Void

    @State private var draftText: String = ""
    @StateObject private var kb = CaptionKeyboardObserver()

    // Fixed, single-line bar metrics (Snapchat-like pill)
    private let barFont = UIFont.systemFont(ofSize: 18, weight: .semibold)
    private let horizPad: CGFloat = 16
    private let vertPad: CGFloat = 10
    private var barHeight: CGFloat { barFont.lineHeight + vertPad * 2 }

    private func keyboardTopLocal(in g: GeometryProxy) -> CGFloat? {
        let end = kb.endFrameGlobal
        if end.isEmpty { return nil }
        let root = g.frame(in: .global)
        return end.minY - root.minY
    }

    private func yInCanvas(containerHeight: CGFloat, kbTopLocalY: CGFloat?) -> CGFloat {
        let h = max(containerHeight, 1)
        let base = (verticalNormalized.isFinite ? verticalNormalized : 0.8) * h
        guard isEditing, let kbTop = kbTopLocalY else { return base }
        let bottomLimit = min(h - barHeight/2, max(0, kbTop - 12) - barHeight/2)
        let topLimit = barHeight/2
        return min(max(base, topLimit), max(topLimit, bottomLimit))
    }

    var body: some View {
        GeometryReader { g in
            let kbTop = keyboardTopLocal(in: g)
            let y = yInCanvas(containerHeight: g.size.height, kbTopLocalY: kbTop)

            ZStack {
                Group {
                    if isEditing {
                        TextField("Add a caption", text: $draftText)
                            .focused(focus)
                            .textFieldStyle(.plain)
                            .submitLabel(.done)
                            .foregroundColor(.white)
                            .padding(.horizontal, horizPad)
                            .padding(.vertical,   vertPad)
                            .background(Color.black.opacity(0.55))
                            .cornerRadius(8)
                            .frame(maxWidth: .infinity)
                            .onSubmit { commitAndFinish() }
                    } else {
                        Text(committedText.isEmpty ? " " : committedText)
                            .font(.system(size: barFont.pointSize, weight: .semibold))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 1)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, horizPad)
                            .padding(.vertical,   vertPad)
                            .frame(maxWidth: .infinity)
                            .background(Color.black.opacity(0.55))
                            .cornerRadius(8)
                            .onTapGesture { onTapToEdit() }
                    }
                }
                .frame(maxWidth: .infinity)
                .offset(y: y - barHeight/2)
                .padding(.horizontal, 8)
            }
            .highPriorityGesture(
                DragGesture()
                    .onChanged { value in
                        let h = max(g.size.height, 1)
                        let vn = verticalNormalized + value.translation.height / h
                        verticalNormalized = min(max(vn, 0.05), 0.95)
                    }
            )
        }
        .task(id: isEditing) { if isEditing { draftText = committedText; focus.wrappedValue = true } }
    }

    private func commitAndFinish() {
        Task { @MainActor in
            committedText = draftText
            onDone()
        }
    }
}

final class CaptionKeyboardObserver: ObservableObject {
    @Published var endFrameGlobal: CGRect = .zero
    init() {
        NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main) { note in
            let f = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue ?? .zero
            self.endFrameGlobal = f
        }
        NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { _ in
            self.endFrameGlobal = .zero
        }
    }
}