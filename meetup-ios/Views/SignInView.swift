import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @Environment(AuthViewModel.self) private var auth
    @State private var glowPulse = false

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Logo glow area
                ZStack {
                    // Outer soft radial glow
                    RadialGradient(
                        colors: [Color.coral.opacity(glowPulse ? 0.30 : 0.18), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 120
                    )
                    .frame(width: 240, height: 240)
                    .blur(radius: 20)
                    .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true), value: glowPulse)

                    // Icon ring
                    Circle()
                        .fill(Color.appSurface)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [Color.coral.opacity(0.7), Color.coral.opacity(0.2)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.5
                                )
                        )
                        .frame(width: 100, height: 100)
                        .shadow(color: Color.coral.opacity(0.4), radius: 24)

                    Image(systemName: "fork.knife.circle.fill")
                        .scaledFont(size: 52)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.coral, Color.coral.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .padding(.bottom, 32)

                // Title
                Text("Squad Brunch")
                    .scaledFont(size: 42, weight: .black, design: .default)
                    .foregroundStyle(DS.Color.textPrimary)
                    .tracking(-0.5)

                Text("Know who's on their way.")
                    .scaledFont(size: 17, weight: .regular)
                    .foregroundStyle(DS.Color.textSecondary)
                    .padding(.top, 6)
                    .padding(.bottom, 56)

                Spacer()

                // Sign in button area
                VStack(spacing: 16) {
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                        request.nonce = auth.generateNonce()
                    } onCompletion: { result in
                        Task {
                            switch result {
                            case .success(let authorization):
                                await auth.signInWithApple(authorization: authorization)
                            case .failure(let error):
                                auth.error = error.localizedDescription
                            }
                        }
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: Color.coral.opacity(0.25), radius: 16, y: 6)

                    if let error = auth.error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(Color.statusLate)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    Text("By signing in you agree to our terms")
                        .scaledFont(size: 11)
                        .foregroundStyle(DS.Color.textSecondary)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 52)
            }
        }

        .onAppear { glowPulse = true }
    }
}
