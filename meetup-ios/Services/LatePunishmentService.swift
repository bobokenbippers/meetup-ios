import Foundation
import UIKit
import Supabase

final class LatePunishmentService {
    static let shared = LatePunishmentService()
    private var supabase: SupabaseClient { SupabaseManager.shared.client }
    private let bucket = "meetup-photos"
    private let signedURLExpiry = 3600

    func fetchVotes(meetupId: UUID) async throws -> [LatePunishmentVote] {
        try await supabase
            .from("meetup_late_punishment_votes")
            .select()
            .eq("meetup_id", value: meetupId)
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    func vote(meetupId: UUID, optionKey: String) async throws {
        struct Params: Encodable {
            let pMeetupId: UUID
            let pOptionKey: String

            enum CodingKeys: String, CodingKey {
                case pMeetupId = "p_meetup_id"
                case pOptionKey = "p_option_key"
            }
        }

        try await supabase
            .rpc(
                "vote_late_punishment",
                params: Params(pMeetupId: meetupId, pOptionKey: optionKey)
            )
            .execute()
    }

    func uploadProof(image: UIImage, meetupId: UUID) async throws {
        guard let uploaderUserId = supabase.auth.currentUser?.id else {
            throw LatePunishmentError.notAuthenticated
        }
        guard let jpeg = image.jpegData(compressionQuality: 0.8) else {
            throw LatePunishmentError.compressionFailed
        }

        let path = "\(meetupId.uuidString)/late-punishment-\(UUID().uuidString).jpg"
        try await supabase.storage
            .from(bucket)
            .upload(path, data: jpeg, options: FileOptions(contentType: "image/jpeg", upsert: false))

        struct ProofInsert: Encodable {
            let meetupId: UUID
            let uploaderUserId: UUID
            let photoUrl: String
            let caption: String?

            enum CodingKeys: String, CodingKey {
                case meetupId = "meetup_id"
                case uploaderUserId = "uploader_user_id"
                case photoUrl = "photo_url"
                case caption
            }
        }

        try await supabase
            .from("meetup_late_punishment_proofs")
            .insert(ProofInsert(
                meetupId: meetupId,
                uploaderUserId: uploaderUserId,
                photoUrl: path,
                caption: "Late tax evidence"
            ))
            .execute()
    }

    func fetchProofs(meetupId: UUID) async throws -> [LatePunishmentProof] {
        let proofs: [LatePunishmentProof] = try await supabase
            .from("meetup_late_punishment_proofs")
            .select()
            .eq("meetup_id", value: meetupId)
            .order("created_at", ascending: false)
            .execute()
            .value
        return await refreshProofURLs(proofs)
    }

    func listProofReactionSummaries(meetupId: UUID) async throws -> [UUID: [LatePunishmentProofReactionSummary]] {
        let summaries: [LatePunishmentProofReactionSummary] = try await supabase
            .rpc("list_late_punishment_proof_reactions", params: ["p_meetup_id": meetupId.uuidString])
            .execute()
            .value

        return Dictionary(grouping: summaries, by: \.proofId)
            .mapValues { reactions in
                reactions.sorted {
                    if $0.reactionCount == $1.reactionCount {
                        return $0.emoji < $1.emoji
                    }
                    return $0.reactionCount > $1.reactionCount
                }
            }
    }

    func toggleProofReaction(proofId: UUID, emoji: String) async throws {
        try await supabase
            .rpc("toggle_late_punishment_proof_reaction", params: [
                "p_proof_id": proofId.uuidString,
                "p_emoji": emoji
            ])
            .execute()
    }

    private func refreshProofURLs(_ proofs: [LatePunishmentProof]) async -> [LatePunishmentProof] {
        var refreshed: [LatePunishmentProof] = []
        refreshed.reserveCapacity(proofs.count)

        for proof in proofs {
            guard let signedURL = await signedURLString(forStoredPhotoURL: proof.photoUrl) else {
                refreshed.append(proof)
                continue
            }
            refreshed.append(proof.replacingPhotoUrl(signedURL))
        }

        return refreshed
    }

    private func signedURLString(forStoredPhotoURL storedPhotoURL: String) async -> String? {
        guard let signedURL = try? await supabase.storage
            .from(bucket)
            .createSignedURL(path: storedPhotoURL, expiresIn: signedURLExpiry) else {
            return nil
        }
        return signedURL.absoluteString
    }
}

enum LatePunishmentError: LocalizedError {
    case notAuthenticated
    case compressionFailed

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "You must be signed in to post evidence."
        case .compressionFailed: return "Failed to prepare the evidence photo."
        }
    }
}
