import Foundation
import UIKit
import Supabase

enum ProfilePhotoError: LocalizedError {
    case notSignedIn
    case compressionFailed

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "You must be signed in to upload a profile photo."
        case .compressionFailed:
            return "Couldn't prepare that profile photo."
        }
    }
}

final class ProfilePhotoService {
    static let shared = ProfilePhotoService()

    private let bucket = "profile-photos"
    private var supabase: SupabaseClient { SupabaseManager.shared.client }

    private init() {}

    func uploadProfilePhoto(_ image: UIImage) async throws -> String {
        guard let userId = supabase.auth.currentUser?.id else {
            throw ProfilePhotoError.notSignedIn
        }
        let prepared = image.resizedForProfilePhoto(maxDimension: 900)
        guard let jpeg = prepared.jpegData(compressionQuality: 0.78) else {
            throw ProfilePhotoError.compressionFailed
        }

        let path = "\(userId.uuidString)/\(UUID().uuidString).jpg"
        try await supabase.storage
            .from(bucket)
            .upload(path: path, file: jpeg, options: FileOptions(contentType: "image/jpeg", upsert: false))
        let publicURL = try supabase.storage
            .from(bucket)
            .getPublicURL(path: path)
        return publicURL.absoluteString
    }
}

private extension UIImage {
    func resizedForProfilePhoto(maxDimension: CGFloat) -> UIImage {
        let longestSide = max(size.width, size.height)
        guard longestSide > maxDimension else { return normalizedForUpload() }

        let scale = maxDimension / longestSide
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            normalizedForUpload().draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    func normalizedForUpload() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
