import Foundation
import Observation

@Observable
final class NavigationState {
    static let shared = NavigationState()
    private init() {}

    enum Tab: Int {
        case meetups = 0
        case people = 1
        case messages = 2
        case settings = 3
    }

    var selectedTab: Tab = .meetups
    var pendingMeetupId: UUID? = nil
    var showFriendRequests: Bool = false

    // Called from AppDelegate.didReceive and onOpenURL handlers
    @MainActor
    func handle(event: String, meetupId: String?) {
        switch event {
        case "friend_request", "friend_accepted":
            selectedTab = .people
            showFriendRequests = true
        case "new_message":
            selectedTab = .messages
        case "meetup_invite", "meetup_arrived", "meetup_accepted", "meetup_declined",
             "meetup_cancelled", "leave_now", "rsvp_update":
            selectedTab = .meetups
            if let idStr = meetupId, let id = UUID(uuidString: idStr) {
                pendingMeetupId = id
            }
        default:
            break
        }
    }
}
