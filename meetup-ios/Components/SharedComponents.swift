import SwiftUI

// MARK: - AvatarView
// Single source of truth for all avatar rendering in the app.
// Shows initials with a consistent color derived from the user's id.
struct AvatarView: View {
    let name: String
    let id: UUID
    var size: CGFloat = 36
    var showBorder: Bool = false

    private var initials: String {
        name.split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined()
            .uppercased()
    }

    private var backgroundColor: Color {
        Color.participantPalette[abs(id.hashValue) % Color.participantPalette.count]
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(backgroundColor)
            Text(initials)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .overlay {
            if showBorder {
                Circle().strokeBorder(.white, lineWidth: 2)
            }
        }
    }
}

// MARK: - SectionHeader
struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - PrimaryButton
struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    var isLoading: Bool = false
    var isDisabled: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.85)
                }
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.appAccentForeground)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(isDisabled ? Color.secondary : Color.coral)
            .clipShape(Capsule())
        }
        .disabled(isDisabled || isLoading)
    }
}

// MARK: - SecondaryButton
struct SecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.coral)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.coral.opacity(0.12))
                .clipShape(Capsule())
        }
    }
}

// MARK: - StatusPill
struct StatusPill: View {
    enum ParticipantState {
        case live, enRoute, late, invited

        var label: String {
            switch self {
            case .live:    return "Arrived"
            case .enRoute: return "En Route"
            case .late:    return "Running Late"
            case .invited: return "Invited"
            }
        }

        var color: Color {
            switch self {
            case .live:    return .statusLive
            case .enRoute: return .statusEnRoute
            case .late:    return .statusRunningLate
            case .invited: return .statusInvited
            }
        }
    }

    let state: ParticipantState

    var body: some View {
        Text(state.label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(state.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(state.color.opacity(0.15))
            .clipShape(Capsule())
    }
}
