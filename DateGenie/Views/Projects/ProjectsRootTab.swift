import SwiftUI

struct ProjectsRootTab: View {
    @State private var selected: Int = 0 // 0 projects, 1 profile

    var body: some View {
        VStack(spacing: 0) {
            if selected == 0 {
                ProjectsView()
            } else {
                ProfileView()
            }
            HStack {
                Button(action: { selected = 0 }) {
                    VStack(spacing: 6) {
                        Image(selected == 0 ? "color_project" : "black_project")
                            .renderingMode(.original)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                        Text("Projects").font(.system(size: 12, weight: .semibold)).foregroundColor(.black)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                Button(action: { selected = 1 }) {
                    VStack(spacing: 6) {
                        Image(selected == 1 ? "color_user" : "black_user")
                            .renderingMode(.original)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                        Text("Profile").font(.system(size: 12, weight: .semibold)).foregroundColor(.black)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
            }
            .background(Color.white)
        }
        .background(Color.white)
    }
}


