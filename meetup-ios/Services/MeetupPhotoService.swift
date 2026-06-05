import Foundation
import Supabase

final class MeetupPhotoService {
    static let shared = MeetupPhotoService()
    private var supabase: SupabaseClient { SupabaseManager.shared.client }
    private let bucket = "meetup-photos"
    // Signed URLs expire in 1 hour — long enough for a recap session.
    private let signedURLExpiry: Int = 3600

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
