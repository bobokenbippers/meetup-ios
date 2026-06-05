import SwiftUI
import UserNotifications
import CoreLocation
import Supabase
import GooglePlacesSwift

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        _ = PlacesClient.provideAPIKey("AIzaSyByrHVgXGbeepjyXWc3xP1jdVeF6rquCsA")
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            guard granted else { return }
            Task { @MainActor in
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

extension AppDelegate: UNUserNotificationCenterDelegate {
    // Show notification banner even when app is foregrounded
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    // Handle tap — deep-link into the right screen
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        guard let event = info["event"] as? String else { completionHandler(); return }
        let meetupId = info["meetupId"] as? String
        Task { @MainActor in
            NavigationState.shared.handle(event: event, meetupId: meetupId)
        }
        completionHandler()
    }
}

@main
struct meetup_iosApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var auth = AuthViewModel()
    @State private var settings = AppSettings()
    private let navState = NavigationState.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if isUITestingMode {
                    HomeView()
                } else if auth.session == nil {
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
            .environment(settings)
            .environment(navState)
            .onOpenURL { url in
                handleDeepLink(url)
            }
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "squadbrunch" else { return }
        let host = url.host ?? ""
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        switch host {
        case "meetup":
            let meetupId = pathComponents.first
            Task { @MainActor in
                NavigationState.shared.handle(event: "meetup_invite", meetupId: meetupId)
            }
        case "people":
            Task { @MainActor in
                NavigationState.shared.handle(event: "friend_request", meetupId: nil)
            }
        default:
            break
        }
    }

    private var isUITestingMode: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--ui-testing")
        #else
        false
        #endif
    }
}
