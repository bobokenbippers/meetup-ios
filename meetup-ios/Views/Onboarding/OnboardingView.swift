import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var currentPage = 0

    var body: some View {
        ZStack(alignment: .top) {
            Color.appBackground.ignoresSafeArea()

            TabView(selection: $currentPage) {
                OnboardingWelcomeView { currentPage = 1 }
                    .tag(0)
                OnboardingHowItWorksView { currentPage = 2 }
                    .tag(1)
                OnboardingPermissionsView { currentPage = 3 }
                    .tag(2)
                OnboardingProfileView { hasCompletedOnboarding = true }
                    .tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: currentPage)

            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule()
                        .fill(i == currentPage ? Color.coral : Color(white: 0.3))
                        .frame(width: i == currentPage ? 20 : 8, height: 8)
                        .animation(.spring(response: 0.3), value: currentPage)
                }
            }
            .padding(.top, 64)
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    OnboardingView()
        .environment(AuthViewModel())
}
