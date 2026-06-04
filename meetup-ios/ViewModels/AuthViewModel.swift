import Foundation
import AuthenticationServices
import Supabase
import Observation

@Observable
final class AuthViewModel {
    var session: Session?
    var profile: Profile?
    var error: String?
    var isLoading = false

    private let supabase = SupabaseManager.shared.client
    private var authTask: Task<Void, Never>?

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            profile = Profile(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                displayName: "Test User",
                phoneE164: "+16469466861",
                email: "test@example.com"
            )
            return
        }
        #endif

        // Load cached profile instantly so UI shows without waiting for network
        profile = Self.cachedProfile()

        authTask = Task {
            for await (event, session) in supabase.auth.authStateChanges {
                self.session = session
                if event == .initialSession, let session = session, !session.isExpired {
                    await loadProfile(userId: session.user.id)
                } else if event == .signedIn, let session = session {
                    await loadProfile(userId: session.user.id)
                }
                if event == .signedOut {
                    self.profile = nil
                    Self.clearCachedProfile()
                }
            }
        }
    }

    func signInWithApple(authorization: ASAuthorization) async {
        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let identityTokenData = credential.identityToken,
            let identityToken = String(data: identityTokenData, encoding: .utf8)
        else {
            error = "Invalid Apple credential"
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            try await supabase.auth.signInWithIdToken(
                credentials: .init(provider: .apple, idToken: identityToken)
            )

            if let fullName = credential.fullName,
               let userId = supabase.auth.currentUser?.id {
                let displayName = [fullName.givenName, fullName.familyName]
                    .compactMap { $0 }.filter { !$0.isEmpty }
                    .joined(separator: " ")
                if !displayName.isEmpty {
                    _ = try? await supabase
                        .from("profiles")
                        .update(["display_name": displayName])
                        .eq("id", value: userId)
                        .execute()
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadProfile(userId: UUID) async {
        do {
            let rows: [Profile] = try await supabase
                .from("profiles")
                .select()
                .eq("id", value: userId)
                .execute()
                .value
            let sessionEmail = supabase.auth.currentSession?.user.email
            if let existing = rows.first {
                self.profile = existing
                Self.cacheProfile(existing)
                if existing.email == nil, let sessionEmail {
                    _ = try? await supabase
                        .from("profiles")
                        .update(["email": sessionEmail])
                        .eq("id", value: userId)
                        .execute()
                }
            } else {
                try await supabase
                    .from("profiles")
                    .insert(["id": userId.uuidString])
                    .execute()
                let fresh = Profile(id: userId, displayName: nil, phoneE164: nil, email: sessionEmail)
                self.profile = fresh
                Self.cacheProfile(fresh)
                if let sessionEmail {
                    _ = try? await supabase
                        .from("profiles")
                        .update(["email": sessionEmail])
                        .eq("id", value: userId)
                        .execute()
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func signOut() async {
        try? await supabase.auth.signOut()
    }

    // MARK: - Profile cache

    private static let cacheKey = "cachedProfile"

    private static func cachedProfile() -> Profile? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(Profile.self, from: data)
    }

    private static func cacheProfile(_ profile: Profile) {
        UserDefaults.standard.set(try? JSONEncoder().encode(profile), forKey: cacheKey)
    }

    private static func clearCachedProfile() {
        UserDefaults.standard.removeObject(forKey: cacheKey)
    }
}
