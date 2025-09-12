import SwiftUI

struct EditToolsBar: View {
    @ObservedObject var state: EditorState
    let onClose: () -> Void
    let onVolume: () -> Void
    let onSpeed: () -> Void

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
                    let isMediaSelected = (state.selectedMediaId != nil)
                    // For clip/audio selections, all tools are enabled per spec.
                    // For text/media selections, only a limited set is enabled.
                    let allowAll = !(isTextSelected || isMediaSelected)
                    let allowForLimitedSelection: (String) -> Bool = { key in
                        return ["Split", "Delete", "Duplicate", "Opacity"].contains(key)
                    }

                    // Temporarily disable Split for audio and text; allow only for clips
                    EditToolsBarItem(assetName: "Split", title: "Split", action: {
                        Task {
                            if state.selectedClipId != nil {
                                await state.splitSelectedClipAtPlayhead()
                            }
                        }
                    }, isEnabled: isClipSelected)
                    EditToolsBarItem(assetName: "Speed", title: "Speed", action: onSpeed, isEnabled: allowAll || allowForLimitedSelection("Speed"))
                    EditToolsBarItem(assetName: "Volume", title: "Volume", action: onVolume, isEnabled: allowAll || allowForLimitedSelection("Volume"))
                    EditToolsBarItem(assetName: "Delete", title: "Delete", action: {
                        Task { await state.deleteSelected() }
                    }, isEnabled: allowAll || allowForLimitedSelection("Delete"))
                    EditToolsBarItem(assetName: "Duplicate", title: "Duplicate", action: { Task { await state.duplicateSelected() } }, isEnabled: allowAll || allowForLimitedSelection("Duplicate"))
                    EditToolsBarItem(assetName: "Extract_audio", title: "Extract\naudio", action: {
                        let um = UIApplication.shared.topMostViewController()?.undoManager
                        Task { await state.extractOriginalAudioFromSelectedClip(undoManager: um) }
                    }, isEnabled: (isClipSelected && !isAudioSelected) && (allowAll || allowForLimitedSelection("Extract_audio")))
                    // Opacity is available for video clip, text, and media overlays (not audio)
                    let opacityEnabled = (isClipSelected || isTextSelected || isMediaSelected)
                    EditToolsBarItem(assetName: "Opacity", title: "Opacity", action: { }, isEnabled: opacityEnabled)
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


