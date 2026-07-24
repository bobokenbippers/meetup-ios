import Foundation
import Testing
@testable import meetup_ios

@Suite("BillService receipt photos")
struct BillServicePhotoTests {

    @Test("receipt photo storage path passes through unchanged")
    func receiptPhotoStoragePathPassesThrough() {
        let path = "B0D3B243-842D-4D75-A1B1-6E5B7B8C294E/photo.jpg"

        #expect(BillService.receiptPhotoStoragePath(from: path) == path)
    }

    @Test("receipt photo storage path is extracted from signed URL")
    func receiptPhotoStoragePathExtractedFromSignedURL() {
        let signedURL = "https://example.supabase.co/storage/v1/object/sign/receipts/"
            + "B0D3B243-842D-4D75-A1B1-6E5B7B8C294E/photo.jpg?token=abc"

        #expect(
            BillService.receiptPhotoStoragePath(from: signedURL)
                == "B0D3B243-842D-4D75-A1B1-6E5B7B8C294E/photo.jpg"
        )
    }

    @Test("receipt photo storage path decodes escaped URL path")
    func receiptPhotoStoragePathDecodesEscapedURLPath() {
        let publicURL = "https://example.supabase.co/storage/v1/object/public/receipts/"
            + "receipt%20folder%2Fphoto%201.jpg"

        #expect(BillService.receiptPhotoStoragePath(from: publicURL) == "receipt folder/photo 1.jpg")
    }

    @Test("non-receipt photo URL is ignored")
    func nonReceiptPhotoURLIsIgnored() {
        let url = "https://example.com/photo.jpg"

        #expect(BillService.receiptPhotoStoragePath(from: url) == nil)
    }
}
