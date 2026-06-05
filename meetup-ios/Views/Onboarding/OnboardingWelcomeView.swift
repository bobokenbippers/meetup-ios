import SwiftUI

struct OnboardingWelcomeView: View {
    let onNext: () -> Void

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            RadialGradient(
                gradient: Gradient(colors: [Color.coral.opacity(0.30), Color.clear]),
                center: .center,
                startRadius: 10,
                endRadius: 340
            )
            .frame(width: 680, height: 680)
            .offset(y: -100)
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(Color.coral.opacity(0.18))
                        .frame(width: 110, height: 110)
                        .blur(radius: 24)
                    Text("🍳")
                        .font(.system(size: 68))
                }
                .padding(.bottom, 36)

                Text("Squad Brunch")
                    .font(.system(size: 42, weight: .black, design: .rounded))
                    .foregroundColor(.white)

                Text("Know who's on their way.")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.top, 14)

                Text("Live location sharing for your crew.")
                    .font(.system(size: 16))
                    .foregroundColor(Color(white: 0.6))
                    .padding(.top, 8)

                Spacer()

                Button(action: onNext) {
                    HStack(spacing: 8) {
                        Text("Let's go")
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.coral)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 60)
            }
        }
    }
}

#Preview {
    OnboardingWelcomeView { }
}
