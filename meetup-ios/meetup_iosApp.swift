import SwiftUI
import UserNotifications
import CoreLocation
import Supabase

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
        LocationManager.shared.requestPermission()
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task {
            guard let userId = SupabaseManager.shared.client.auth.currentUser?.id else { return }
            _ = try? await SupabaseManager.shared.client
                .from("profiles")
                .update(["apns_token": token])
                .eq("id", value: userId)
                .execute()
        }
    }
}

@main
struct meetup_iosApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var auth = AuthViewModel()

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.session == nil {
                    SignInView()
                } else if auth.profile == nil {
                    ProgressView("Loading...")
                } else if auth.profile?.phoneE164 == nil {
                    ProfileSetupView()
                } else {
                    HomeView()
                }
            }
            .environment(auth)
        }
    }
}
