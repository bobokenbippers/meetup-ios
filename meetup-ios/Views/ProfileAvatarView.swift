import SwiftUI

struct ProfileAvatarView: View {
    let displayName: String?
    let avatarUrl: String?
    let userId: UUID?
    let size: CGFloat
    var fontSize: CGFloat? = nil

    private var initial: String {
        let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return String((trimmed.isEmpty ? "?" : trimmed).prefix(1)).uppercased()
    }

    private var fallbackColor: Color {
        guard let userId else { return Color.coral }
        return Color.participantPalette[abs(userId.hashValue) % Color.participantPalette.count]
    }

    private var imageURL: URL? {
        guard let avatarUrl else { return nil }
        return URL(string: avatarUrl)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(fallbackColor)

            if let url = imageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        fallbackInitial
                    }
                }
            } else {
                fallbackInitial
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var fallbackInitial: some View {
        Text(initial)
            .scaledFont(size: fontSize ?? max(11, size * 0.38), weight: .bold)
            .foregroundStyle(.white)
    }
}

extension ProfileAvatarView {
    init(profile: Profile?, size: CGFloat, fontSize: CGFloat? = nil) {
        self.init(
            displayName: profile?.displayName,
            avatarUrl: profile?.avatarUrl,
            userId: profile?.id,
            size: size,
            fontSize: fontSize
        )
    }
}
