import SwiftUI

struct VideoCaptionSheet: View {
    let onCancel: () -> Void
    let onSave: (String?) -> Void

    @State private var caption: String = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                TextField("Add a caption (optional)", text: $caption)
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding(12)
                    .background(Color.white.opacity(0.15))
                    .cornerRadius(8)
                    .foregroundColor(.white)
                Spacer()
            }
            .padding()
            .background(Color.black.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        AnalyticsManager.shared.logEvent("editor_saved", parameters: [
                            "type": "video",
                            "caption_present": !caption.isEmpty
                        ])
                        onSave(caption.isEmpty ? nil : caption)
                    }
                }
            }
        }
    }
}
