import SwiftUI
import AVFoundation

struct TextToolPanel: View {
    @ObservedObject var state: EditorState
    let canvasRect: CGRect

    @State private var text: String = ""
    @State private var color: Color = .white
    @State private var durationSec: Double = 2

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Text")) {
                    TextField("Enter text", text: $text)
                    ColorPicker("Color", selection: $color)
                    HStack {
                        Text("Duration")
                        Slider(value: $durationSec, in: 0.5...10, step: 0.5)
                        Text("\(String(format: "%.1fs", durationSec))")
                    }
                }
            }
            .navigationBarTitle("Add Text", displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) { Button("Add") { add() } }
            }
        }
    }

    private func dismiss() { UIApplication.shared.topMostViewController()?.dismiss(animated: true) }

    private func add() {
        let center = CGPoint(x: canvasRect.width/2, y: canvasRect.height/2)
        var base = TextOverlay(string: text, position: center)
        base.color = RGBAColor(color)
        let item = TimedTextOverlay(base: base, start: state.currentTime, duration: CMTime(seconds: durationSec, preferredTimescale: 600))
        state.textOverlays.append(item)
        dismiss()
    }
}


