import SwiftUI

enum AvatarBadgeKind {
    case live
    case arrived
    case late
    case invited
    case custom(color: Color, symbol: String)

    var color: Color {
        switch self {
        case .live: return .statusEnRoute
        case .arrived: return .statusLive
        case .late: return .statusRunningLate
        case .invited: return .statusInvited
        case .custom(let color, _): return color
        }
    }

    var symbol: String {
        switch self {
        case .live: return "location.fill"
        case .arrived: return "checkmark"
        case .late: return "clock.badge.exclamationmark.fill"
        case .invited: return "envelope.fill"
        case .custom(_, let symbol): return symbol
        }
    }
}

struct AvatarPresenceStyle {
    var ringColor: Color? = nil
    var ringWidth: CGFloat = 0
    var glowColor: Color? = nil
    var glowRadius: CGFloat = 0
    var badge: AvatarBadgeKind? = nil
    var overlayLabel: String? = nil
    var overlayTint: Color = .black.opacity(0.48)
}

struct ProfileAvatarView: View {
    let displayName: String?
    let avatarUrl: String?
    let userId: UUID?
    let size: CGFloat
    var fontSize: CGFloat? = nil
    var presenceStyle: AvatarPresenceStyle = AvatarPresenceStyle()

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
        .overlay {
            if let overlayLabel = presenceStyle.overlayLabel {
                Circle()
                    .fill(presenceStyle.overlayTint)

                Image(systemName: overlayLabel)
                    .scaledFont(size: max(10, size * 0.34), weight: .bold)
                    .foregroundStyle(.white)
            }
        }
        .overlay {
            if let ringColor = presenceStyle.ringColor, presenceStyle.ringWidth > 0 {
                Circle()
                    .strokeBorder(ringColor, lineWidth: presenceStyle.ringWidth)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let badge = presenceStyle.badge {
                Circle()
                    .fill(.white)
                    .frame(width: max(14, size * 0.34), height: max(14, size * 0.34))
                    .overlay(
                        Circle()
                            .fill(badge.color)
                            .padding(2)
                    )
                    .overlay(
                        Image(systemName: badge.symbol)
                            .scaledFont(size: max(7, size * 0.14), weight: .bold)
                            .foregroundStyle(.white)
                    )
                    .offset(x: 2, y: 2)
            }
        }
        .shadow(
            color: (presenceStyle.glowColor ?? .clear).opacity(presenceStyle.glowRadius > 0 ? 0.45 : 0),
            radius: presenceStyle.glowRadius
        )
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
