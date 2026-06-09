import SwiftUI
import UserNotifications

struct OnboardingPermissionsView: View {
    let onNext: () -> Void
    @State private var isRequesting = false

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
                    Image(systemName: "location.fill")
                        .scaledFont(size: 52)
                        .foregroundColor(Color.coral)
                }
                .padding(.bottom, 32)

                Text("A couple of things")
                    .scaledFont(size: 34, weight: .black, design: .rounded)
                    .foregroundColor(.white)
                    .padding(.bottom, 36)

                VStack(spacing: 16) {
                    permissionRow(
                        icon: "location.fill",
                        title: "Location",
                        subtitle: "We need your location to show friends how close you are"
                    )
                    permissionRow(
                        icon: "bell.fill",
                        title: "Notifications",
                        subtitle: "Get notified when it's time to leave"
                    )
                }
                .padding(.horizontal, 32)

                Spacer()

                Button {
                    requestPermissions()
                } label: {
                    Text(isRequesting ? "Requesting…" : "Allow →")
                        .scaledFont(size: 18, weight: .semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.coral)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .disabled(isRequesting)
                .padding(.horizontal, 32)
                .padding(.bottom, 60)
            }
        }
    }

    @ViewBuilder
    private func permissionRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .scaledFont(size: 20)
                .foregroundColor(Color.coral)
                .frame(width: 28)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .scaledFont(size: 16, weight: .semibold)
                    .foregroundColor(.white)
                Text(subtitle)
                    .scaledFont(size: 14)
                    .foregroundColor(Color(white: 0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(16)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func requestPermissions() {
        isRequesting = true
        Task {
            LocationManager.shared.requestPermission()
            _ = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            await MainActor.run {
                isRequesting = false
                onNext()
            }
        }
    }
}

#Preview {
    OnboardingPermissionsView { }
}
