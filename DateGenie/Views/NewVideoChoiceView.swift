import SwiftUI

struct NewVideoChoiceView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color(red: 0xF7/255.0, green: 0xB4/255.0, blue: 0x51/255.0)
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer().frame(height: 65)

                Text("CHOOSE WHAT TO CREATE")
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundColor(.black)
                    .kerning(1)
                    .padding(.horizontal, 15)

                VStack(spacing: 28) {
                    // Animated Educational Videos
                    VStack(spacing: 12) {
                        Button(action: openCommercialAdFlow) {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white)
                                .frame(width: 185, height: 185)
                                .overlay(
                                    Image("astro")
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 185, height: 185)
                                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                )
                        }
                        .buttonStyle(.plain)

                        Text("ANIMATED EDUCATIONAL VIDEOS")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.black)
                    }

                    // Animated Movie Trailers
                    VStack(spacing: 12) {
                        Button(action: {}) {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white)
                                .frame(width: 185, height: 185)
                                .overlay(
                                    Image("glinda")
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 185, height: 185)
                                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                )
                        }
                        .buttonStyle(.plain)

                        Text("ANIMATED MOVIE TRAILERS")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.black)
                    }

                    // Animated Music Videos
                    VStack(spacing: 12) {
                        Button(action: {}) {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white)
                                .frame(width: 185, height: 185)
                                .overlay(
                                    Image("T8")
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 185, height: 185)
                                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                )
                        }
                        .buttonStyle(.plain)

                        Text("ANIMATED MUSIC VIDEOS")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.black)
                    }
                }

                Spacer()
            }
        }
        .overlay(alignment: .topLeading) {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.black)
                    .padding(12)
                    .background(Color.white.opacity(0.8))
                    .clipShape(Circle())
            }
            .padding(.top, 40)
            .padding(.leading, 20)
        }
    }

    private func openCommercialAdFlow() {
        let host = UIHostingController(rootView: AdGenChoiceView())
        host.modalPresentationStyle = .overFullScreen
        UIApplication.shared.topMostViewController()?.present(host, animated: true)
    }
}

