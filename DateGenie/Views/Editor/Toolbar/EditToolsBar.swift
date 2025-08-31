import SwiftUI

struct EditToolsBar: View {
    @ObservedObject var state: EditorState
    let onClose: () -> Void

    var body: some View {
        // Match the original bottom toolbar footprint so the timeline doesn't shift
        HStack(spacing: 10) {
            // Back/close tile — no label
            EditToolsBarItem(assetName: "left-arrow", title: "", action: onClose)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    EditToolsBarItem(assetName: "Split", title: "Split") { }
                    EditToolsBarItem(assetName: "Speed", title: "Speed") { }
                    EditToolsBarItem(assetName: "Volume", title: "Volume") { }
                    EditToolsBarItem(assetName: "Delete", title: "Delete") { }
                    EditToolsBarItem(assetName: "Duplicate", title: "Duplicate") { }
                    EditToolsBarItem(assetName: "Extract_audio", title: "Extract\naudio") { }
                    EditToolsBarItem(assetName: "Opacity", title: "Opacity") { }
                }
                .padding(.vertical, 6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Color.black)
        .ignoresSafeArea(edges: .bottom)
    }
}


