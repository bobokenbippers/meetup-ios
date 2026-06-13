import SwiftUI
import Supabase

struct OnboardingProfileView: View {
    @Environment(AuthViewModel.self) private var auth
    let onComplete: () -> Void

    @State private var displayName = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var trimmedName: String { displayName.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(Color.coral.opacity(0.15))
                        .frame(width: 120, height: 120)
                        .blur(radius: 28)
                    Image(systemName: "person.fill")
                        .scaledFont(size: 52)
                        .foregroundColor(Color.coral)
                }
                .padding(.bottom, 32)

                Text("What should we\ncall you?")
                    .scaledFont(size: 34, weight: .black, design: .rounded)
                    .foregroundStyle(DS.Color.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 10)

                Text("This is how your friends will see you.")
                    .scaledFont(size: 16)
                    .foregroundStyle(DS.Color.textSecondary)
                    .padding(.bottom, 40)

                TextField("Your name", text: $displayName)
                    .scaledFont(size: 18)
                    .foregroundStyle(DS.Color.textPrimary)
                    .tint(Color.coral)
                    .padding(16)
                    .background(Color.appSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                trimmedName.isEmpty ? Color.clear : Color.coral.opacity(0.5),
                                lineWidth: 1
                            )
                    )
                    .padding(.horizontal, 32)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.top, 8)
                        .padding(.horizontal, 32)
                }

                Spacer()

                Button {
                    saveName()
                } label: {
                    Group {
                        if isSaving {
                            ProgressView().tint(.white)
                        } else {
                            Text("Done →")
                                .scaledFont(size: 18, weight: .semibold)
                                .foregroundStyle(Color.appAccentForeground)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(trimmedName.isEmpty ? Color.coral.opacity(0.4) : Color.coral)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .disabled(trimmedName.isEmpty || isSaving)
                .padding(.horizontal, 32)
                .padding(.bottom, 60)
            }
        }
        .onAppear {
            if let existing = auth.profile?.displayName, !existing.isEmpty {
                displayName = existing
            }
        }
    }

    private func saveName() {
        guard !trimmedName.isEmpty else { return }
        isSaving = true
        errorMessage = nil

        Task {
            guard let userId = auth.profile?.id else {
                await MainActor.run { isSaving = false; onComplete() }
                return
            }
            do {
                try await SupabaseManager.shared.client
                    .from("profiles")
                    .update(["display_name": trimmedName])
                    .eq("id", value: userId)
                    .execute()
                await auth.loadProfile(userId: userId)
                await MainActor.run { isSaving = false; onComplete() }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

#Preview {
    OnboardingProfileView { }
        .environment(AuthViewModel())
}
