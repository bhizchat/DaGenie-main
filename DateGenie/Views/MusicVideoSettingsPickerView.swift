import SwiftUI

struct MusicVideoSettingsPickerView: View {
    var onBack: (() -> Void)? = nil
    var onPick: ((MusicVideoSetting) -> Void)? = nil

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 18, alignment: .top),
        GridItem(.flexible(), spacing: 18, alignment: .top)
    ]

    @State private var selected: MusicVideoSetting? = nil

    var body: some View {
        ZStack(alignment: .topLeading) {
            ScrollView {
                VStack(spacing: 18) {
                    Text("SETTINGS")
                        .font(.system(size: 34, weight: .heavy))
                        .foregroundColor(.black)
                        .padding(.top, 18)
                    LazyVGrid(columns: columns, spacing: 28) {
                        ForEach(MusicVideoSettingsCatalog.all) { item in
                            VStack(spacing: 10) {
                                Image(item.imageAssetName)
                                    .resizable()
                                    .renderingMode(.original)
                                    .scaledToFit()
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                Text(item.name)
                                    .font(.system(size: 18, weight: .heavy))
                                    .foregroundColor(.black)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { selected = item }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 24)
                }
            }
            .background(Color(hex: 0xF7B451).ignoresSafeArea())
            .sheet(item: Binding(get: { selected.map(IdentifiableSetting.init(from:)) }, set: { newVal in
                selected = newVal?.value
            })) { wrap in
                let item = wrap.value
                MusicVideoSettingDetailSheet(item: item) { chosen in
                    selected = nil
                    onPick?(chosen)
                }
            }

            Button(action: { onBack?() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.black)
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
            .padding(.leading, 6)
            .padding(.top, 6)
        }
    }
}

private struct IdentifiableSetting: Identifiable {
    let value: MusicVideoSetting
    var id: String { value.id }
    init(from v: MusicVideoSetting) { self.value = v }
}

private struct MusicVideoSettingDetailSheet: View {
    let item: MusicVideoSetting
    let onSelect: (MusicVideoSetting) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(item.imageAssetName)
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 20)

                Text(item.name.uppercased())
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)

                Text(item.bio)
                    .font(.system(size: 14))
                    .foregroundColor(.black)
                    .padding(.horizontal, 24)
                    .multilineTextAlignment(.leading)

                Button(action: { onSelect(item) }) {
                    Text("Select \(item.name)")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
                        .padding(.horizontal, 24)
                }
                .padding(.bottom, 24)
            }
            .padding(.top, 12)
        }
        .background(Color(hex: 0xF7B451).ignoresSafeArea())
        .overlay(alignment: .topLeading) {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundColor(.black)
                    .frame(width: 48, height: 48, alignment: .center)
                    .contentShape(Rectangle())
            }
            .padding(.leading, 2)
            .padding(.top, 2)
        }
    }
}


