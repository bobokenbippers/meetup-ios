import Foundation
import Testing
@testable import meetup_ios

@Suite("PrivacyAuditLog")
struct PrivacyAuditLogTests {
    @Test("event metadata exposes stable display labels and icons")
    func eventDisplayMetadata() {
        #expect(PrivacyAuditEventType.locationSharingStarted.title == "Location sharing started")
        #expect(PrivacyAuditEventType.locationSharingStopped.systemImage == "location.slash.fill")
        #expect(PrivacyAuditEventType.locationCleared.title == "Location cleared")
        #expect(PrivacyAuditEventType.meetupCompleted.systemImage == "checkmark.seal.fill")
    }
}
