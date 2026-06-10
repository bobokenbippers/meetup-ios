import Foundation
import Supabase
import UIKit

enum DirectMessageError: LocalizedError {
    case notSignedIn
    case imageCompressionFailed
    case imageUploadFailed

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "You must be signed in to message friends."
        case .imageCompressionFailed:
            return "Failed to prepare the image."
        case .imageUploadFailed:
            return "Couldn't upload that photo. Please try again."
        }
    }
}

final class DirectMessageService {
    static let shared = DirectMessageService()

    private let supabase = SupabaseManager.shared.client
    private let photoBucket = "message-photos"
    private let signedURLExpiry = 60 * 60 * 24

    private init() {}

    func getOrCreateConversation(with friendId: UUID) async throws -> UUID {
        try await supabase
            .rpc("get_or_create_conversation", params: ["p_other_user_id": friendId.uuidString])
            .execute()
            .value
    }

    func listConversationSummaries() async throws -> [ConversationSummary] {
        struct NoParams: Encodable {}
        struct SummaryRow: Codable {
            let conversationId: UUID
            let otherUserId: UUID
            let lastMessageAt: Date?
            let lastBody: String?
            let lastImagePath: String?
            let lastSenderId: UUID?
            let unreadCount: Int

            enum CodingKeys: String, CodingKey {
                case conversationId = "conversation_id"
                case otherUserId = "other_user_id"
                case lastMessageAt = "last_message_at"
                case lastBody = "last_body"
                case lastImagePath = "last_image_path"
                case lastSenderId = "last_sender_id"
                case unreadCount = "unread_count"
            }
        }

        let rows: [SummaryRow] = try await supabase
            .rpc("list_conversation_summaries", params: NoParams())
            .execute()
            .value
        guard !rows.isEmpty else { return [] }

        let profiles: [Profile] = try await supabase
            .from("profiles")
            .select()
            .in("id", values: rows.map { $0.otherUserId.uuidString })
            .execute()
            .value
        let profileById = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })

        return rows.compactMap { row in
            guard let friend = profileById[row.otherUserId] else { return nil }
            return ConversationSummary(
                id: row.conversationId,
                friend: friend,
                lastBody: row.lastBody,
                lastImagePath: row.lastImagePath,
                lastMessageAt: row.lastMessageAt,
                lastSenderId: row.lastSenderId,
                unreadCount: row.unreadCount
            )
        }
    }

    func listMessages(conversationId: UUID) async throws -> [Message] {
        try await supabase
            .from("messages")
            .select()
            .eq("conversation_id", value: conversationId.uuidString)
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    func listReactionSummaries(conversationId: UUID) async throws -> [UUID: [MessageReactionSummary]] {
        let summaries: [MessageReactionSummary] = try await supabase
            .rpc("list_message_reactions", params: ["p_conversation_id": conversationId.uuidString])
            .execute()
            .value

        return Dictionary(grouping: summaries, by: \.messageId)
            .mapValues { reactions in
                reactions.sorted {
                    if $0.reactionCount == $1.reactionCount {
                        return $0.emoji < $1.emoji
                    }
                    return $0.reactionCount > $1.reactionCount
                }
            }
    }

    func toggleReaction(messageId: UUID, emoji: String) async throws {
        try await supabase
            .rpc("toggle_message_reaction", params: [
                "p_message_id": messageId.uuidString,
                "p_emoji": emoji
            ])
            .execute()
    }

    func sendText(_ body: String, conversationId: UUID) async throws {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try await insertMessage(body: trimmed, imagePath: nil, conversationId: conversationId)
    }

    func sendImage(_ image: UIImage, caption: String?, conversationId: UUID) async throws {
        let preparedImage = image.resizedForMessageUpload(maxDimension: 1600)
        guard let jpeg = preparedImage.jpegData(compressionQuality: 0.72) else {
            throw DirectMessageError.imageCompressionFailed
        }
        let path = "\(conversationId.uuidString)/\(UUID().uuidString).jpg"
        do {
            try await supabase.storage
                .from(photoBucket)
                .upload(path: path, file: jpeg, options: FileOptions(contentType: "image/jpeg", upsert: false))
        } catch {
            throw DirectMessageError.imageUploadFailed
        }

        let trimmed = caption?.trimmingCharacters(in: .whitespacesAndNewlines)
        try await insertMessage(
            body: trimmed?.isEmpty == false ? trimmed : nil,
            imagePath: path,
            conversationId: conversationId
        )
    }

    func signedImageURL(for path: String) async throws -> URL {
        try await supabase.storage
            .from(photoBucket)
            .createSignedURL(path: path, expiresIn: signedURLExpiry)
    }

    func markRead(conversationId: UUID) async throws {
        try await supabase
            .rpc("mark_conversation_read", params: ["p_conversation_id": conversationId.uuidString])
            .execute()
    }

    func deleteMessage(_ message: Message) async throws {
        guard let myId = supabase.auth.currentUser?.id else { throw DirectMessageError.notSignedIn }
        guard message.senderId == myId else { return }
        try await supabase
            .from("messages")
            .delete()
            .eq("id", value: message.id.uuidString)
            .eq("sender_id", value: myId.uuidString)
            .execute()
    }

    func editMessage(_ message: Message, body: String) async throws {
        guard let myId = supabase.auth.currentUser?.id else { throw DirectMessageError.notSignedIn }
        guard message.senderId == myId else { return }

        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || message.imagePath != nil else { return }

        struct MessageUpdate: Encodable {
            let body: String?
            let editedAt: String

            enum CodingKeys: String, CodingKey {
                case body
                case editedAt = "edited_at"
            }
        }

        try await supabase
            .from("messages")
            .update(MessageUpdate(
                body: trimmed.isEmpty ? nil : trimmed,
                editedAt: ISO8601DateFormatter().string(from: Date())
            ))
            .eq("id", value: message.id.uuidString)
            .eq("sender_id", value: myId.uuidString)
            .execute()
    }

    private func insertMessage(body: String?, imagePath: String?, conversationId: UUID) async throws {
        guard let senderId = supabase.auth.currentUser?.id else { throw DirectMessageError.notSignedIn }
        struct MessageInsert: Encodable {
            let conversationId: UUID
            let senderId: UUID
            let body: String?
            let imagePath: String?

            enum CodingKeys: String, CodingKey {
                case conversationId = "conversation_id"
                case senderId = "sender_id"
                case body
                case imagePath = "image_path"
            }
        }

        try await supabase
            .from("messages")
            .insert(MessageInsert(
                conversationId: conversationId,
                senderId: senderId,
                body: body,
                imagePath: imagePath
            ))
            .execute()
    }
}

private extension UIImage {
    func resizedForMessageUpload(maxDimension: CGFloat) -> UIImage {
        let longestSide = max(size.width, size.height)
        guard longestSide > maxDimension else { return self }

        let scale = maxDimension / longestSide
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
