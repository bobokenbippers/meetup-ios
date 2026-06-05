import Foundation
import UIKit
import Supabase

final class MeetupPhotoService {
    static let shared = MeetupPhotoService()
    private var supabase: SupabaseClient { SupabaseManager.shared.client }
    private let bucket = "meetup-photos"
    // Signed URLs expire in 1 hour — long enough for a recap session.
    private let signedURLExpiry: Int = 3600

    // MARK: - Storage

    /// Compress `image` to JPEG, upload to storage, return the public URL string.
    func uploadPhoto(image: UIImage, meetupId: UUID) async throws -> String {
        guard let jpeg = image.jpegData(compressionQuality: 0.8) else {
            throw PhotoServiceError.compressionFailed
        }
        let path = "\(meetupId.uuidString)/\(UUID().uuidString).jpg"
        try await supabase.storage
            .from(bucket)
            .upload(path: path, file: jpeg, options: FileOptions(contentType: "image/jpeg", upsert: false))
        let signedURL = try await supabase.storage
            .from(bucket)
            .createSignedURL(path: path, expiresIn: signedURLExpiry)
        // Store the path so we can regenerate signed URLs later; return a string URL.
        return signedURL.absoluteString
    }

    // MARK: - Database

    /// Insert a row into meetup_photos.
    func insertPhoto(meetupId: UUID, url: String, caption: String?) async throws {
        guard let uploaderUserId = supabase.auth.currentUser?.id else {
            throw PhotoServiceError.notAuthenticated
        }
        let row = MeetupPhotoInsert(
            meetupId: meetupId,
            uploaderUserId: uploaderUserId,
            photoUrl: url,
            caption: caption
        )
        try await supabase
            .from("meetup_photos")
            .insert(row)
            .execute()
    }

    /// Fetch all photos for a meetup, joined with the uploader's display name.
    func fetchPhotos(meetupId: UUID) async throws -> [MeetupPhoto] {
        let photos: [MeetupPhoto] = try await supabase
            .from("meetup_photos")
            .select("*, profiles(display_name)")
            .eq("meetup_id", value: meetupId)
            .order("created_at", ascending: true)
            .execute()
            .value
        return photos
    }

    // MARK: - Legacy storage-list helper (kept for backward compat with RecapView)

    func uploadPhoto(meetupId: UUID, imageData: Data) async throws -> URL {
        let path = "\(meetupId.uuidString)/\(UUID().uuidString).jpg"
        try await supabase.storage
            .from(bucket)
            .upload(path: path, file: imageData, options: FileOptions(contentType: "image/jpeg", upsert: false))
        return try await supabase.storage
            .from(bucket)
            .createSignedURL(path: path, expiresIn: signedURLExpiry)
    }

    func listPhotos(meetupId: UUID) async throws -> [URL] {
        let folder = meetupId.uuidString
        let files = try await supabase.storage
            .from(bucket)
            .list(path: folder)
        let imagePaths = files
            .filter { !$0.name.isEmpty && $0.name != ".emptyFolderPlaceholder" }
            .map { "\(folder)/\($0.name)" }
        var urls: [URL] = []
        for path in imagePaths {
            if let url = try? await supabase.storage
                .from(bucket)
                .createSignedURL(path: path, expiresIn: signedURLExpiry) {
                urls.append(url)
            }
        }
        return urls
    }
}

enum PhotoServiceError: LocalizedError {
    case compressionFailed
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .compressionFailed:    return "Failed to compress the image."
        case .notAuthenticated:     return "You must be signed in to upload photos."
        }
    }
}
