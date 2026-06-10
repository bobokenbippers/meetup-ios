import SwiftUI
import UserNotifications
import CoreLocation
import Supabase

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Force white navigation titles globally — must set all three appearances
        // (standard, compact, scrollEdge) so large titles are white in SwiftUI NavigationStack
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithTransparentBackground()
        navAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        navAppearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
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
        Task { await NotificationService.shared.registerDeviceToken(deviceToken) }
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
    @State private var pendingShareToken: String?
    @State private var showJoinSheet = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some Scene {
        WindowGroup {
            Group {
                if isUITestingMode {
                    HomeView()
                } else if !auth.hasResolvedInitialSession {
                    ProgressView("Loading...")
                } else if auth.session == nil {
                    SignInView()
                } else if auth.profile?.id != auth.session?.user.id {
                    ProgressView("Loading...")
                } else if auth.profile?.phoneE164 == nil {
                    ProfileSetupView()
                } else if !hasCompletedOnboarding {
                    OnboardingView()
                } else {
                    HomeView()
                }
            }
            .environment(auth)
            .environment(settings)
            .environment(navState)
            .modifier(AppAccessibilityPreferencesModifier(settings: settings))
            .preferredColorScheme(.dark)
            .onOpenURL { url in
                handleDeepLink(url)
            }
            .sheet(isPresented: $showJoinSheet, onDismiss: { pendingShareToken = nil }) {
                if let token = pendingShareToken {
                    JoinMeetupSheet(shareToken: token)
                }
            }
        }
    }

    private func handleDeepLink(_ url: URL) {
        // Universal link: https://squadbrunch.app/join/<token>
        // Also handles Supabase edge function URL: https://<ref>.supabase.co/functions/v1/join-meetup/<token>
        if let host = url.host, host == "squadbrunch.app" || host.hasSuffix(".supabase.co") {
            let path = url.pathComponents.filter { $0 != "/" }
            // squadbrunch.app/join/<token>
            if path.count >= 2, path[0] == "join" {
                pendingShareToken = path[1]
                showJoinSheet = true
                return
            }
            // <ref>.supabase.co/functions/v1/join-meetup/<token>
            if let tokenIndex = path.firstIndex(of: "join-meetup").map({ $0 + 1 }),
               tokenIndex < path.count {
                pendingShareToken = path[tokenIndex]
                showJoinSheet = true
                return
            }
        }

        guard url.scheme == "squadbrunch" else { return }
        let host = url.host ?? ""
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        switch host {
        case "join":
            // squadbrunch://join/<token>
            if let token = pathComponents.first {
                pendingShareToken = token
                showJoinSheet = true
            }
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

private struct AppAccessibilityPreferencesModifier: ViewModifier {
    let settings: AppSettings

    @ViewBuilder
    func body(content: Content) -> some View {
        let weightedContent = content
            .environment(
                \.legibilityWeight,
                settings.boldText ? LegibilityWeight.bold : nil
            )

        if settings.largerText {
            weightedContent.dynamicTypeSize(.accessibility1)
        } else {
            weightedContent
        }
    }
}
