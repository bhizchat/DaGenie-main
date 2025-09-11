import SwiftUI
import FirebaseAuth
import FirebaseStorage

struct StorageBrowserView: View {
    @State private var items: [StorageMediaItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var selected: StorageMediaItem? = nil

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading...")
                } else if let msg = errorMessage {
                    VStack(spacing: 12) {
                        Text("Failed to load")
                            .font(.headline)
                        Text(msg)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        Button("Retry", action: load)
                    }
                    .padding()
                } else if items.isEmpty {
                    VStack(spacing: 12) {
                        Text("No images found")
                            .font(.headline)
                        Text("Capture a photo to see it here.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(items) { item in
                                Button {
                                    selected = item
                                } label: {
                                    AsyncImage(url: item.url) { phase in
                                        switch phase {
                                        case .empty:
                                            ZStack { Color.gray.opacity(0.15); ProgressView() }
                                        case .success(let image):
                                            image
                                                .resizable()
                                                .scaledToFill()
                                        case .failure:
                                            ZStack { Color.gray.opacity(0.15); Image(systemName: "exclamationmark.triangle").foregroundColor(.orange) }
                                        @unknown default:
                                            Color.gray.opacity(0.15)
                                        }
                                    }
                                    .frame(height: 110)
                                    .clipped()
                                    .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(action: { UIPasteboard.general.string = item.url?.absoluteString }) {
                                        Label("Copy URL", systemImage: "doc.on.doc")
                                    }
                                }
                            }
                        }
                        .padding(10)
                    }
                }
            }
            .navigationTitle("My Storage Photos")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: load) { Image(systemName: "arrow.clockwise") }
                }
            }
            .onAppear(perform: load)
            .sheet(item: $selected) { item in
                StorageMediaPreview(item: item)
            }
        }
    }

    private func load() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        items.removeAll()

        guard let uid = Auth.auth().currentUser?.uid else {
            errorMessage = "Not signed in"
            isLoading = false
            return
        }

        let root = Storage.storage().reference().child("userMedia/\(uid)")
        root.listAll { listResult, error in
            if let error = error {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
                return
            }
            guard let listResult = listResult else {
                self.errorMessage = "No results"
                self.isLoading = false
                return
            }

            // Collect all items recursively: listAll already returns items in all subpaths
            let imageRefs = listResult.items.filter { ref in
                let name = ref.name.lowercased()
                return name.hasSuffix(".jpg") || name.hasSuffix(".jpeg") || name.hasSuffix(".png")
            }
            if imageRefs.isEmpty {
                self.isLoading = false
                return
            }
            let group = DispatchGroup()
            var collected: [StorageMediaItem] = []
            for ref in imageRefs {
                group.enter()
                ref.downloadURL { url, _ in
                    let item = StorageMediaItem(id: ref.fullPath, name: ref.name, path: ref.fullPath, url: url)
                    collected.append(item)
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                // Sort newest-first by name when it contains UUID/timestamp; fallback to name
                self.items = collected.sorted(by: { $0.name > $1.name })
                self.isLoading = false
            }
        }
    }
}

struct StorageMediaItem: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    let url: URL?
}

private struct StorageMediaPreview: View {
    let item: StorageMediaItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack {
                if let url = item.url {
                    ScrollView {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                ProgressView().padding()
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .cornerRadius(10)
                                    .padding()
                            case .failure:
                                VStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle").foregroundColor(.orange)
                                    Text("Failed to load image")
                                }
                                .padding()
                            @unknown default:
                                EmptyView()
                            }
                        }
                    }
                } else {
                    Text("Missing URL")
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
            }
            .navigationTitle(item.name)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if let link = item.url {
                        ShareLink(item: link) { Image(systemName: "square.and.arrow.up") }
                    }
                }
            }
        }
    }
}


