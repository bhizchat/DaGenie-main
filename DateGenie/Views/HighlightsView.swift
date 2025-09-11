import SwiftUI

struct HighlightsView: View {
    @StateObject private var repo = HighlightReelRepository.shared
    private struct PreviewItem: Identifiable {
        enum Kind { case photo, video }
        let id = UUID()
        let url: URL
        let kind: Kind
    }
    @State private var previewItem: PreviewItem? = nil
    @State private var toast: ToastMessage? = nil
    @State private var showRename: Bool = false
    @State private var renameText: String = ""
    @State private var reelToRename: HighlightReel? = nil

    var body: some View {
        Group {
            if repo.reels.isEmpty {
                VStack(spacing: 12) {
                    Text("No highlights yet")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Finish a date adventure to generate a highlight reel.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(grouped.keys.sorted(by: >), id: \.self) { key in
                            sectionHeader(for: key)
                            ForEach(grouped[key]!) { reel in
                                HighlightRow(reel: reel,
                                             onDownload: { download(reel) },
                                             onDelete: { delete(reel) },
                                             onRename: { promptRename(reel) })
                                    .padding(.horizontal)
                                    .padding(.vertical, 6)
                                    .onTapGesture {
                                        if reel.mediaType == "photo", let url = reel.imageURL {
                                            previewItem = PreviewItem(url: url, kind: .photo)
                                        } else if let url = reel.videoURL {
                                            previewItem = PreviewItem(url: url, kind: .video)
                                        }
                                    }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Highlights")
        .onAppear { Task { await repo.refresh() } }
        .background(Color.black.ignoresSafeArea())
        .sheet(item: $previewItem) { item in
            CapcutEditorView(url: item.url)
        }
        .toast(message: $toast)
        .alert("Rename Highlight", isPresented: $showRename, actions: {
            TextField("Title", text: $renameText)
            Button("Save") { renameCommit() }
            Button("Cancel", role: .cancel) { }
        }, message: {
            Text("Enter a new name for this highlight.")
        })
    }

    private var grouped: [DaySemesterKey: [HighlightReel]] {
        Dictionary(grouping: repo.reels) { DaySemesterKey(date: $0.createdAt) }
    }

    @ViewBuilder private func sectionHeader(for key: DaySemesterKey) -> some View {
        Text(key.display)
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal)
            .padding(.top, 16)
    }
}

// MARK: - Day + Semester grouping key
fileprivate struct DaySemesterKey: Hashable, Comparable {
    let date: Date
    init(date: Date) {
        self.date = Calendar.current.startOfDay(for: date)
    }
    static func < (lhs: DaySemesterKey, rhs: DaySemesterKey) -> Bool { lhs.date < rhs.date }

    var display: String { "\(monthDayString(for: date)) - \(semester(for: date))" }
}

fileprivate func monthDayString(for date: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "MMMM d" // August 13
    return f.string(from: date)
}

fileprivate func semester(for date: Date) -> String {
    let comps = Calendar.current.dateComponents([.year, .month], from: date)
    guard let m = comps.month, let y = comps.year else { return "" }
    let name: String
    switch m {
    case 1...5: name = "Spring"
    case 6...8: name = "Summer"
    default: name = "Fall"
    }
    return "\(name) \(y)"
}

// MARK: - Actions
extension HighlightsView {
    private func download(_ reel: HighlightReel) {
        Task {
            do {
                if reel.mediaType == "photo" {
                    try await HighlightReelRepository.shared.downloadPhotoAndSaveToPhotos(reel)
                } else {
                    try await HighlightReelRepository.shared.downloadAndSaveToPhotos(reel)
                }
                await MainActor.run {
                    toast = ToastMessage(text: "Saved to Photos", style: .success)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { toast = nil }
                }
            } catch {
                await MainActor.run {
                    toast = ToastMessage(text: "Couldn't save to Photos. Try again.", style: .error)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { toast = nil }
                }
            }
        }
    }

    private func delete(_ reel: HighlightReel) {
        Task {
            do {
                try await HighlightReelRepository.shared.delete(reel)
            } catch {
                await MainActor.run {
                    toast = ToastMessage(text: "Delete failed. Try again.", style: .error)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { toast = nil }
                }
            }
        }
    }

    private func promptRename(_ reel: HighlightReel) {
        reelToRename = reel
        renameText = reel.title
        showRename = true
    }

    private func renameCommit() {
        guard let reel = reelToRename else { return }
        let newTitle = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newTitle.isEmpty else { showRename = false; return }
        Task {
            do {
                try await HighlightReelRepository.shared.rename(reel, to: newTitle)
            } catch {
                await MainActor.run {
                    toast = ToastMessage(text: "Rename failed. Try again.", style: .error)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { toast = nil }
                }
            }
            await MainActor.run { showRename = false }
        }
    }
}
