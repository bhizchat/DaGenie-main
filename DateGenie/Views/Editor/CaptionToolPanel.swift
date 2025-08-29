import SwiftUI
import AVFoundation

struct CaptionToolPanel: View {
    @ObservedObject var state: EditorState
    let canvasRect: CGRect

    @State private var text: String = ""
    @State private var durationSec: Double = 2
    @State private var vertical: Double = 0.8

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Caption")) {
                    TextField("Caption", text: $text)
                    HStack {
                        Text("Duration")
                        Slider(value: $durationSec, in: 0.5...10, step: 0.5)
                        Text("\(String(format: "%.1fs", durationSec))")
                    }
                    HStack {
                        Text("Vertical")
                        Slider(value: $vertical, in: 0...1)
                        Text(String(format: "%.0f%%", vertical*100))
                    }
                }
            }
            .navigationBarTitle("Captions", displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) { Button("Add") { add() } }
            }
        }
    }

    private func dismiss() { UIApplication.shared.topMostViewController()?.dismiss(animated: true) }

    private func add() {
        var model = CaptionModel.default()
        model.text = text
        model.isVisible = true
        model.verticalOffsetNormalized = vertical
        let item = TimedCaption(base: model, start: state.currentTime, duration: CMTime(seconds: durationSec, preferredTimescale: 600))
        state.captions.append(item)
        dismiss()
    }
}


