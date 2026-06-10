import Foundation

/// A single direct message (text and/or image) in a 1:1 conversation.
struct Message: Codable, Identifiable, Equatable {
    let id: UUID
    let conversationId: UUID
    let senderId: UUID
    let body: String?
    let imagePath: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, body
        case conversationId = "conversation_id"
        case senderId = "sender_id"
        case imagePath = "image_path"
        case createdAt = "created_at"
    }
}

/// Canonical conversation row for an accepted friend-pair (user_a_id < user_b_id).
struct Conversation: Codable, Identifiable {
    let id: UUID
    let userAId: UUID
    let userBId: UUID
    let lastMessageAt: Date?
    let lastReadA: Date?
    let lastReadB: Date?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userAId = "user_a_id"
        case userBId = "user_b_id"
        case lastMessageAt = "last_message_at"
        case lastReadA = "last_read_a"
        case lastReadB = "last_read_b"
        case createdAt = "created_at"
    }
}

/// Inbox row: one conversation with its last-message preview and unread count,
/// joined with the other participant's profile (resolved client-side).
struct ConversationSummary: Identifiable, Equatable {
    let id: UUID            // conversation id
    let friend: Profile
    let lastBody: String?
    let lastImagePath: String?
    let lastMessageAt: Date?
    let lastSenderId: UUID?
    let unreadCount: Int

    static func == (lhs: ConversationSummary, rhs: ConversationSummary) -> Bool {
        lhs.id == rhs.id
            && lhs.lastMessageAt == rhs.lastMessageAt
            && lhs.lastBody == rhs.lastBody
            && lhs.lastImagePath == rhs.lastImagePath
            && lhs.unreadCount == rhs.unreadCount
            && lhs.friend.id == rhs.friend.id
            && lhs.friend.displayName == rhs.friend.displayName
            && lhs.friend.avatarUrl == rhs.friend.avatarUrl
    }

    /// One-line preview for the inbox row.
    var preview: String {
        if let body = lastBody, !body.isEmpty { return body }
        if lastImagePath != nil { return "📷 Photo" }
        return "No messages yet"
    }
}
