import SwiftUI

struct EditToolsBar: View {
    @ObservedObject var state: EditorState
    let onClose: () -> Void
    let onVolume: () -> Void

    var body: some View {
        // Match the original bottom toolbar footprint so the timeline doesn't shift
        HStack(spacing: 10) {
            // Back/close tile — no label
            EditToolsBarItem(assetName: "left-arrow", title: "", action: onClose)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    let isTextSelected = (state.selectedTextId != nil)
                    let isAudioSelected = (state.selectedAudioId != nil)
                    let isClipSelected = (state.selectedClipId != nil)
                    // For non-text selections (audio/clip), all tools are enabled per spec.
                    let allowAll = !isTextSelected
                    let allowForText: (String) -> Bool = { key in
                        // When text is selected, only these are enabled
                        return ["Split", "Delete", "Duplicate", "Opacity"].contains(key)
                    }

                    EditToolsBarItem(assetName: "Split", title: "Split", action: { }, isEnabled: allowAll || allowForText("Split"))
                    EditToolsBarItem(assetName: "Speed", title: "Speed", action: { }, isEnabled: allowAll || allowForText("Speed"))
                    EditToolsBarItem(assetName: "Volume", title: "Volume", action: onVolume, isEnabled: allowAll || allowForText("Volume"))
                    EditToolsBarItem(assetName: "Delete", title: "Delete", action: {
                        Task { await state.deleteSelected() }
                    }, isEnabled: allowAll || allowForText("Delete"))
                    EditToolsBarItem(assetName: "Duplicate", title: "Duplicate", action: { }, isEnabled: allowAll || allowForText("Duplicate"))
                    EditToolsBarItem(assetName: "Extract_audio", title: "Extract\naudio", action: {
                        let um = UIApplication.shared.topMostViewController()?.undoManager
                        Task { await state.extractOriginalAudioFromSelectedClip(undoManager: um) }
                    }, isEnabled: (isClipSelected && !isAudioSelected) && (allowAll || allowForText("Extract_audio")))
                    EditToolsBarItem(assetName: "Opacity", title: "Opacity", action: { }, isEnabled: allowAll || allowForText("Opacity"))
                }
                .padding(.vertical, 6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Color.editorToolbarBackground)
        .ignoresSafeArea(edges: .bottom)
    }
}


