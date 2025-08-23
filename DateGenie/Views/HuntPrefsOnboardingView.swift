//  HuntPrefsOnboardingView.swift
//  DateGenie
//
//  Collects user preferences in a quick swipeable flow.
//
import SwiftUI

struct HuntPrefsOnboardingView: View {
    @EnvironmentObject private var userRepo: UserRepository
    @EnvironmentObject private var huntsRepo: HuntsRepository

    @State private var prefs = HuntPrefs()
    @State private var showError: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TabView {
            // Page 1: Indoor / Outdoor
            VStack(spacing: 24) {
                Text("Do you prefer indoor or outdoor adventures?")
                    .font(.title2)
                    .multilineTextAlignment(.center)
                HStack {
                    ForEach(IndoorOutdoor.allCases, id: \ .self) { option in
                        Button(option.rawValue.capitalized) {
                            prefs.indoorOutdoor = option
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(prefs.indoorOutdoor == option ? Color.accentColor : Color.gray.opacity(0.2))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                }
                Spacer()
            }
            .padding()

            // Page 2: Budget slider
            VStack(spacing: 24) {
                Text("Max budget for a hunt")
                    .font(.title2)
                Text("$\(prefs.maxBudget)")
                    .font(.largeTitle)
                Slider(value: Binding(get: { Double(prefs.maxBudget) }, set: { prefs.maxBudget = Int($0) }), in: 0...40, step: 5)
                    .tint(.accentColor)
                Spacer()
            }
            .padding()

            // Page 3: Mobility toggle & finish
            VStack(spacing: 24) {
                Toggle("Low-mobility friendly", isOn: $prefs.lowMobility)
                    .toggleStyle(.switch)
                    .padding()
                Toggle("First-date mode", isOn: $prefs.firstDateMode)
                    .toggleStyle(.switch)
                    .padding()
                Spacer()
                Button("See Hunts →") {
                    Task {
                        do {
                            try await userRepo.updatePrefs(prefs)
                            try await huntsRepo.refresh()
                            dismiss()
                        } catch {
                            showError = "Could not save prefs. Check your connection."
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .errorToast(message: $showError)
        .task {
            prefs = userRepo.prefs // preload if cached
        }
    }
}

#if DEBUG
struct HuntPrefsOnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        HuntPrefsOnboardingView()
            .environmentObject(UserRepository.shared)
            .environmentObject(HuntsRepository.shared)
    }
}
#endif
