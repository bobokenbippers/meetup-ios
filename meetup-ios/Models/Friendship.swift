import Foundation

struct IncomingFriendRequest: Identifiable {
    let id: UUID       // friendshipId
    let requester: Profile
}

struct PendingOutgoingRequest: Identifiable {
    let id: UUID       // friendshipId
    let addressee: Profile
}
