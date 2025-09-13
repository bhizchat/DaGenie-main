import SwiftUI
import FirebaseAuth

struct ProjectsView: View {
    @StateObject private var repo = ProjectsRepository.shared
    @State private var isCreating = false
    @State private var showCreationOptions = false

    private var userId: String? { Auth.auth().currentUser?.uid }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Spacer().frame(height: 24)
            HStack { Spacer(); Image("Logo_DG").resizable().scaledToFit().frame(width: 120, height: 120); Spacer() }

            Button(action: { showCreationOptions = true }) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(red: 249/255, green: 210/255, blue: 161/255))
                    HStack(spacing: 14) {
                        Image("plus_newproject")
                            .renderingMode(.original)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                        Text("Start Video")
                            .font(.custom("Inter-Bold", size: 24))
                            .foregroundColor(.black)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 146)
                .padding(.horizontal, 20)
            }
            .disabled(isCreating)
            .fullScreenCover(isPresented: $showCreationOptions) {
                NewVideoChoiceView()
            }

            if !FeatureFlags.disableProjectSaving {
                Text("\(repo.projects.count) Projects")
                    .font(.system(size: 20, weight: .bold))
                    .padding(.horizontal)
            }

            if FeatureFlags.disableProjectSaving {
                Spacer()
                Spacer()
            } else if repo.projects.isEmpty {
                Spacer()
                Text("No projects yet")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(repo.projects) { p in
                            ProjectRow(project: p,
                                       onRename: { rename(project: p) },
                                       onDelete: { delete(project: p) },
                                       onOpen: { open(project: p) })
                                .padding(.horizontal)
                        }
                    }
                }
            }
        }
        .background(Color.white.ignoresSafeArea())
        .onAppear { Task { if let uid = userId { await repo.load(userId: uid) } } }
    }

    private func newProject() {
        guard let uid = userId, !isCreating else { return }
        isCreating = true
        Task {
            if let p = await repo.create(userId: uid) {
                let host = UIHostingController(rootView: CapcutEditorView(url: p.videoURL ?? URL(fileURLWithPath: "/dev/null")))
                host.modalPresentationStyle = .overFullScreen
                UIApplication.shared.topMostViewController()?.present(host, animated: true)
            }
            isCreating = false
        }
    }

    private func rename(project: Project) {
        guard let uid = userId else { return }
        let alert = UIAlertController(title: "Rename Project", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.text = project.name }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default, handler: { _ in
            let raw = alert.textFields?.first?.text ?? project.name
            let newName = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !newName.isEmpty else { return }
            Task { await repo.rename(userId: uid, projectId: project.id, to: newName) }
        }))
        UIApplication.shared.topMostViewController()?.present(alert, animated: true)
    }

    private func delete(project: Project) {
        guard let uid = userId else { return }
        let alert = UIAlertController(title: "Delete Project", message: "This cannot be undone.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive, handler: { _ in
            Task { await repo.delete(userId: uid, projectId: project.id) }
        }))
        UIApplication.shared.topMostViewController()?.present(alert, animated: true)
    }

    private func open(project: Project) {
        let url = project.videoURL ?? URL(fileURLWithPath: "/dev/null")
        let host = UIHostingController(rootView: CapcutEditorView(url: url,
                                                                  storyboardId: project.storyboardId,
                                                                  currentSceneIndex: project.currentSceneIndex,
                                                                  totalScenes: project.totalScenes))
        host.modalPresentationStyle = .overFullScreen
        UIApplication.shared.topMostViewController()?.present(host, animated: true)
    }
}

private struct ProjectRow: View {
    let project: Project
    let onRename: () -> Void
    let onDelete: () -> Void
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: project.thumbURL) { ph in
                switch ph {
                case .empty: Color.gray.opacity(0.3)
                case .success(let img): img.resizable().scaledToFill()
                case .failure: Color.gray.opacity(0.3)
                @unknown default: Color.gray.opacity(0.3)
                }
            }
            .frame(width: 96, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 6) {
                Text(project.name.isEmpty ? "Untitled" : project.name)
                    .font(.custom("Inter-Bold", size: 18))
                    .foregroundColor(.black)
                Text(Self.dateFormatter.string(from: project.createdAt))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.black.opacity(0.5))
            }
            Spacer()
            Menu {
                Button("Rename", action: onRename)
                Button("Delete", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.black)
                    .padding(8)
                    .contentShape(Rectangle())
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MM-dd-yy"; return f
    }()
}


