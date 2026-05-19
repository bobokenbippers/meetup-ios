import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @Environment(AuthViewModel.self) private var auth

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "location.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.tint)
                Text("Squad Brunch")
                    .font(.largeTitle.bold())
                Text("Know who's on their way.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
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
            .signInWithAppleButtonStyle(.black)
            .frame(height: 50)
            .padding(.horizontal, 40)

            if let error = auth.error {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            Spacer().frame(height: 40)
        }
    }
}
