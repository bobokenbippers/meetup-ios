import Foundation
import Supabase

final class SupabaseManager {
    static let shared = SupabaseManager()

    let client: SupabaseClient

    private init() {
        let url = URL(string: "https://boyrqhbdkqzffvfokpri.supabase.co")!
        let anonKey = "sb_publishable_nbZ1LRBEHbTEylig9ST9-Q_Qxyx29_8"
        client = SupabaseClient(supabaseURL: url, supabaseKey: anonKey)
    }
}
