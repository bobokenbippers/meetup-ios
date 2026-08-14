import Foundation
import UIKit
import Supabase

final class MeetupPhotoService {
    static let shared = MeetupPhotoService()
    private var supabase: SupabaseClient { SupabaseManager.shared.client }
    private let bucket = "meetup-photos"
    // Signed URLs expire, so the database stores storage paths and fetches
    // regenerate signed URLs for the current viewing session.
    private let signedURLExpiry: Int = 3600

    // MARK: - Storage

    /// Compress `image` to JPEG, upload to storage, return the storage path.
    func uploadPhoto(image: UIImage, meetupId: UUID) async throws -> String {
        let prepared = image.resizedForMeetupUpload(maxDimension: 1600)
        guard let jpeg = prepared.jpegData(compressionQuality: 0.78) else {
            throw PhotoServiceError.compressionFailed
        }
        let path = "\(meetupId.uuidString)/\(UUID().uuidString).jpg"
        try await supabase.storage
            .from(bucket)
            .upload(path, data: jpeg, options: FileOptions(contentType: "image/jpeg", upsert: false))
        return path
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

    /// Delete a photo: remove the database row, then best-effort remove the
    /// storage object. RLS limits this to the uploader or the meetup host.
    func deletePhoto(_ photo: MeetupPhoto) async throws {
        try await supabase
            .from("meetup_photos")
            .delete()
            .eq("id", value: photo.id)
            .execute()

        // The row is the source of truth; an orphaned object is harmless and
        // unreachable once the row is gone, so storage cleanup is best effort.
        if let path = Self.storagePath(from: photo.photoUrl) {
            do {
                _ = try await supabase.storage.from(bucket).remove(paths: [path])
            } catch is CancellationError {
                return
            } catch {
                // Ignore: signed-URL reads stop working without the row anyway.
            }
        }
    }

    /// Whether `currentUserId` may delete `photo` — mirrors the
    /// "uploaders and hosts can delete photos" RLS policy.
    static func canDelete(photo: MeetupPhoto, currentUserId: UUID?, meetupHostId: UUID) -> Bool {
        guard let currentUserId else { return false }
        return photo.uploaderUserId == currentUserId || meetupHostId == currentUserId
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
        return await refreshPhotoURLs(photos)
    }

    private func refreshPhotoURLs(_ photos: [MeetupPhoto]) async -> [MeetupPhoto] {
        var refreshed: [MeetupPhoto] = []
        refreshed.reserveCapacity(photos.count)

        for photo in photos {
            guard let signedURL = await signedURLString(forStoredPhotoURL: photo.photoUrl) else {
                refreshed.append(photo)
                continue
            }
            refreshed.append(photo.replacingPhotoUrl(signedURL))
        }

        return refreshed
    }

    private func signedURLString(forStoredPhotoURL storedPhotoURL: String) async -> String? {
        guard let path = Self.storagePath(from: storedPhotoURL) else { return nil }
        guard let signedURL = try? await supabase.storage
            .from(bucket)
            .createSignedURL(path: path, expiresIn: signedURLExpiry) else {
            return nil
        }
        return signedURL.absoluteString
    }

    static func storagePath(from storedPhotoURL: String) -> String? {
        let trimmed = storedPhotoURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if !trimmed.localizedCaseInsensitiveContains("://") {
            return trimmed
        }

        guard let url = URL(string: trimmed) else { return nil }
        let pathComponents = url.pathComponents
        guard let bucketIndex = pathComponents.firstIndex(of: "meetup-photos") else { return nil }
        let storageComponents = pathComponents.dropFirst(bucketIndex + 1)
        guard !storageComponents.isEmpty else { return nil }

        return storageComponents
            .joined(separator: "/")
            .removingPercentEncoding
    }

    // MARK: - Legacy storage-list helper (kept for backward compat with RecapView)

    func uploadPhoto(meetupId: UUID, imageData: Data) async throws -> URL {
        let path = "\(meetupId.uuidString)/\(UUID().uuidString).jpg"
        try await supabase.storage
            .from(bucket)
            .upload(path, data: imageData, options: FileOptions(contentType: "image/jpeg", upsert: false))
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

private extension UIImage {
    func resizedForMeetupUpload(maxDimension: CGFloat) -> UIImage {
        let longestSide = max(size.width, size.height)
        guard longestSide > maxDimension else { return normalizedForMeetupUpload() }

        let scale = maxDimension / longestSide
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            normalizedForMeetupUpload().draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    func normalizedForMeetupUpload() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
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
