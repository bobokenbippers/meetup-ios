import Foundation
import Supabase

enum MeetupCommentError: LocalizedError {
    case notSignedIn
    case emptyComment

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "You must be signed in to comment."
        case .emptyComment:
            return "Write a comment first."
        }
    }
}

final class MeetupCommentService {
    static let shared = MeetupCommentService()

    private let supabase = SupabaseManager.shared.client

    private init() {}

    func listComments(meetupId: UUID) async throws -> [MeetupComment] {
        try await supabase
            .rpc("list_meetup_comments", params: ["p_meetup_id": meetupId.uuidString])
            .execute()
            .value
    }

    func postComment(meetupId: UUID, body: String) async throws {
        guard let authorId = supabase.auth.currentUser?.id else { throw MeetupCommentError.notSignedIn }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MeetupCommentError.emptyComment }

        struct CommentInsert: Encodable {
            let meetupId: UUID
            let authorUserId: UUID
            let body: String

            enum CodingKeys: String, CodingKey {
                case meetupId = "meetup_id"
                case authorUserId = "author_user_id"
                case body
            }
        }

        try await supabase
            .from("meetup_comments")
            .insert(CommentInsert(meetupId: meetupId, authorUserId: authorId, body: trimmed))
            .execute()
    }

    func deleteComment(_ comment: MeetupComment) async throws {
        guard let myId = supabase.auth.currentUser?.id else { throw MeetupCommentError.notSignedIn }
        guard comment.authorUserId == myId else { return }

        try await supabase
            .from("meetup_comments")
            .delete()
            .eq("id", value: comment.id.uuidString)
            .eq("author_user_id", value: myId.uuidString)
            .execute()
    }
}
