import Foundation
import Testing
@testable import meetup_ios

@Suite("MeetupPhotoService")
struct MeetupPhotoServiceTests {

    @Test("storage path passes through unchanged")
    func storagePathPassesThrough() {
        let path = "B0D3B243-842D-4D75-A1B1-6E5B7B8C294E/photo.jpg"

        #expect(MeetupPhotoService.storagePath(from: path) == path)
    }

    @Test("storage path is extracted from signed URL")
    func storagePathExtractedFromSignedURL() {
        let signedURL = "https://example.supabase.co/storage/v1/object/sign/meetup-photos/"
            + "B0D3B243-842D-4D75-A1B1-6E5B7B8C294E/photo.jpg?token=abc"

        #expect(
            MeetupPhotoService.storagePath(from: signedURL)
                == "B0D3B243-842D-4D75-A1B1-6E5B7B8C294E/photo.jpg"
        )
    }

    @Test("storage path decodes escaped URL path")
    func storagePathDecodesEscapedPath() {
        let signedURL = "https://example.supabase.co/storage/v1/object/sign/meetup-photos/"
            + "event%20folder%2Fphoto%201.jpg?token=abc"

        #expect(MeetupPhotoService.storagePath(from: signedURL) == "event folder/photo 1.jpg")
    }

    @Test("non-meetup photo URL is ignored")
    func nonMeetupPhotoURLIsIgnored() {
        let url = "https://example.com/photo.jpg"

        #expect(MeetupPhotoService.storagePath(from: url) == nil)
    }

    // MARK: - canDelete

    private func makePhoto(uploaderUserId: UUID) -> MeetupPhoto {
        MeetupPhoto(
            id: UUID(),
            meetupId: UUID(),
            uploaderUserId: uploaderUserId,
            photoUrl: "meetup/photo.jpg",
            caption: nil,
            createdAt: Date(),
            profiles: nil
        )
    }

    @Test("uploader can delete their own photo")
    func uploaderCanDeleteOwnPhoto() {
        let uploader = UUID()
        let photo = makePhoto(uploaderUserId: uploader)

        #expect(MeetupPhotoService.canDelete(photo: photo, currentUserId: uploader, meetupHostId: UUID()))
    }

    @Test("host can delete any photo in their meetup")
    func hostCanDeleteAnyPhoto() {
        let host = UUID()
        let photo = makePhoto(uploaderUserId: UUID())

        #expect(MeetupPhotoService.canDelete(photo: photo, currentUserId: host, meetupHostId: host))
    }

    @Test("other participants cannot delete photos")
    func otherParticipantsCannotDelete() {
        let photo = makePhoto(uploaderUserId: UUID())

        #expect(!MeetupPhotoService.canDelete(photo: photo, currentUserId: UUID(), meetupHostId: UUID()))
    }

    @Test("signed-out users cannot delete photos")
    func signedOutUsersCannotDelete() {
        let photo = makePhoto(uploaderUserId: UUID())

        #expect(!MeetupPhotoService.canDelete(photo: photo, currentUserId: nil, meetupHostId: UUID()))
    }
}
