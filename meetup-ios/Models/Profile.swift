import Foundation

struct Profile: Codable, Identifiable, Equatable {
    let id: UUID
    var displayName: String?
    var phoneE164: String?
    var email: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case phoneE164 = "phone_e164"
        case email
    }
}
