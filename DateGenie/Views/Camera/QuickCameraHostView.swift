import SwiftUI

struct QuickCameraHostView: View {
    @State private var captured: CapturedMedia? = nil

    var body: some View {
        ZStack {
            CameraSheet { media in
                captured = media
            }
        }
        .sheet(isPresented: Binding(get: { captured != nil }, set: { if !$0 { captured = nil } })) {
            if let media = captured {
                if media.type == .photo {
                    // Route photos to the new editor as well or replace with a photo editor if desired
                    CapcutEditorView(url: media.localURL)
                } else {
                    CapcutEditorView(url: media.localURL)
                }
            } else {
                EmptyView()
            }
        }
    }
}


