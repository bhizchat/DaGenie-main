import SwiftUI

struct ThemeSwipeOnboardingView: View {
    var onProceed: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)
            Image("onboard_swipe")
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 420)
                .cornerRadius(12)
                .padding(.horizontal)
            Spacer()
            Button(action: onProceed) {
                Text("Proceed")
                    .font(.vt323(24))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Color.nodeTop)
                    .cornerRadius(8)
                    .padding(.horizontal)
            }
            .padding(.bottom, 24)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) { EmptyView() }
        }
    }
}

#if DEBUG
struct ThemeSwipeOnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        ThemeSwipeOnboardingView(onProceed: {})
    }
}
#endif


