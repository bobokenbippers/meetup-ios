import Foundation
import Supabase
import UIKit
import UserNotifications

struct NotificationService {
    static let shared = NotificationService()

    @MainActor
    func registerForRemoteNotificationsIfAuthorized() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized ||
              settings.authorizationStatus == .provisional ||
              settings.authorizationStatus == .ephemeral
        else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    @MainActor
    func requestAuthorizationAndRegister() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
            return granted
        } catch {
            return false
        }
    }

    func registerDeviceToken(_ tokenData: Data) async {
        let token = tokenData.map { String(format: "%02x", $0) }.joined()
        guard let userId = SupabaseManager.shared.client.auth.currentUser?.id else { return }
        do {
            try await SupabaseManager.shared.client
                .from("device_tokens")
                .upsert(
                    ["user_id": userId.uuidString, "token": token, "platform": "ios"],
                    onConflict: "user_id,token"
                )
                .execute()
        } catch {
            print("Failed to register device token: \(error)")
        }
    }
}
