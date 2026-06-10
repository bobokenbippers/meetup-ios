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
}
