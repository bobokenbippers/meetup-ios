import Foundation
import Supabase

struct NotificationService {
    static let shared = NotificationService()

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
