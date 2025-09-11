import SwiftUI

struct HighlightRow: View {
    let reel: HighlightReel
    var onDownload: (() -> Void)? = nil
    var onDelete:   (() -> Void)? = nil
    var onRename:   (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: reel.thumbnailURL) { phase in
                switch phase {
                case .empty: ProgressView()
                case .success(let img): img.resizable().scaledToFill()
                case .failure: Image(systemName: "photo")
                @unknown default: EmptyView()
                }
            }
            .frame(width: 80, height: 80)
            .clipped()
            .cornerRadius(6)

            VStack(alignment: .leading, spacing: 4) {
                Text(reel.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(metaText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Menu {
                Button {
                    onDownload?()
                } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                Button {
                    onRename?()
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    onDelete?()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 44, height: 44) // larger tap target
                    .contentShape(Rectangle())
                    .padding(.trailing, 4)
            }
        }
        .contentShape(Rectangle())
    }

    private var metaText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        let rel = formatter.localizedString(for: reel.createdAt, relativeTo: Date())
        let kind = reel.mediaType == "photo" ? "Photo" : "Video"
        return "\(kind) · \(rel) · \(Int(reel.sizeMB)) MB"
    }
}

//#if DEBUG
//struct HighlightRow_Previews: PreviewProvider {
//    static var previews: some View {
//        HighlightRow(reel: HighlightReel(id: "1", createdAt: Date().addingTimeInterval(-86400), title: "Celebrating National Girlfriend's Day…", thumbnailURL: URL(string: "https://picsum.photos/200")!, videoURL: URL(string: "https://example.com")!, sizeMB: 26))
//            .preferredColorScheme(.dark)
//    }
//}
//#endif
