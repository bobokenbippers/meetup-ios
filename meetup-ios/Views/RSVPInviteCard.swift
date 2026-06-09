import SwiftUI

// MARK: - RSVPInviteCard
// Displayed in the Invited section of MeetupsListView.
// Shows meetup info + Yes/No/Maybe buttons with premium animations.

struct RSVPInviteCard: View {
    let participation: MyParticipation
    let onOpen: () -> Void
    let onRespond: (String) async -> Void

    @State private var isActing = false
    @State private var showConfetti = false
    @State private var wobbleCount = 0
    @State private var dismissed = false
    @Environment(AppSettings.self) private var settings

    var body: some View {
        if !dismissed {
            cardContent
                .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Meetup info — tap to open dashboard
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    Text(meetupCategoryEmoji(participation.meetup.category))
                        .scaledFont(size: 22)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(participation.meetup.destinationName)
                            .scaledFont(size: 14, weight: .bold)
                            .foregroundStyle(Color(.label))
                            .lineLimit(1)
                        if let addr = participation.meetup.destinationAddress, !addr.isEmpty {
                            Text(addr)
                                .scaledFont(size: 11)
                                .foregroundStyle(Color(.secondaryLabel))
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    if let target = participation.meetup.targetArrivalAt {
                        Text(target, format: .dateTime.weekday(.abbreviated).hour().minute())
                            .scaledFont(size: 10, weight: .medium)
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // RSVP buttons
            HStack(spacing: 8) {
                RSVPPillButton(
                    label: "Yes",
                    systemImage: "checkmark",
                    color: .statusLive,
                    disabled: isActing
                ) { await respond("yes") }

                RSVPPillButton(
                    label: "Maybe",
                    systemImage: "questionmark",
                    color: .statusPending,
                    disabled: isActing
                ) { await respond("maybe") }

                RSVPPillButton(
                    label: "No",
                    systemImage: "xmark",
                    color: .statusLate,
                    disabled: isActing
                ) { await respond("no") }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .background {
            RoundedRectangle(cornerRadius: 18)
                .fill(meetupCategoryGradient(
                    category: participation.meetup.category,
                    meetupStatus: participation.meetup.status,
                    participantStatus: participation.status
                ))
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color(.separator), lineWidth: 1)
        }
        .keyframeAnimator(initialValue: CGFloat(0), trigger: wobbleCount) { content, angle in
            content.rotationEffect(.degrees(angle))
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(0.0, duration: 0.04)
                SpringKeyframe(4.0, duration: 0.10, spring: .bouncy(duration: 0.1, extraBounce: 0.3))
                SpringKeyframe(-4.0, duration: 0.10, spring: .bouncy(duration: 0.1, extraBounce: 0.3))
                SpringKeyframe(3.5, duration: 0.09, spring: .bouncy)
                SpringKeyframe(-3.5, duration: 0.09, spring: .bouncy)
                SpringKeyframe(2.0, duration: 0.08, spring: .bouncy)
                SpringKeyframe(0.0, spring: .smooth(duration: 0.15))
            }
        }
        .overlay(alignment: .center) {
            if showConfetti {
                ConfettiBurstCanvas()
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .allowsHitTesting(false)
            }
        }
    }

    private func respond(_ status: String) async {
        guard !isActing else { return }
        isActing = true

        if !settings.reduceMotion {
            switch status {
            case "yes":
                showConfetti = true
                Task {
                    do { try await Task.sleep(for: .seconds(1.6)) } catch { return }
                    showConfetti = false
                }
            case "maybe":
                wobbleCount += 1
                try? await Task.sleep(for: .milliseconds(700))
            case "no":
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    dismissed = true
                }
                try? await Task.sleep(for: .milliseconds(350))
            default:
                break
            }
        }

        await onRespond(status)
        isActing = false
    }
}

// MARK: - RSVP Pill Button

private struct RSVPPillButton: View {
    let label: String
    let systemImage: String
    let color: Color
    let disabled: Bool
    let action: () async -> Void

    var body: some View {
        Button {
            Task { await action() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .scaledFont(size: 10, weight: .bold)
                Text(label)
                    .scaledFont(size: 13, weight: .semibold)
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(color.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(color.opacity(0.28), lineWidth: 1)
            )
        }
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }
}

// MARK: - Confetti Burst Canvas
// Canvas-based particle burst using TimelineView for per-frame rendering.

struct ConfettiBurstCanvas: View {
    private struct Particle {
        let angle: Double
        let speed: Double
        let color: Color
        let size: CGFloat
        let isCircle: Bool
        let delay: Double
    }

    private static let burstParticles: [Particle] = {
        let palette: [Color] = [
            .statusLive, .statusPending, .coral,
            Color(red: 0.118, green: 0.565, blue: 1.0),
            Color(red: 0.922, green: 0.212, blue: 0.510),
            Color(red: 0.000, green: 0.780, blue: 0.941),
            Color(red: 0.984, green: 0.843, blue: 0.235),
            Color(red: 0.200, green: 0.900, blue: 0.540),
        ]
        return (0..<65).map { _ in
            Particle(
                angle: .random(in: 0...(2 * .pi)),
                speed: .random(in: 80...220),
                color: palette.randomElement()!,
                size: .random(in: 4...12),
                isCircle: Bool.random(),
                delay: .random(in: 0...0.18)
            )
        }
    }()

    @State private var startTime: Date = .now

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { ctx in
            Canvas { drawCtx, size in
                let center = CGPoint(x: size.width / 2, y: size.height * 0.62)
                let gravity = 200.0

                for p in Self.burstParticles {
                    let elapsed = ctx.date.timeIntervalSince(startTime) - p.delay
                    guard elapsed > 0 else { continue }
                    let t = min(elapsed, 1.5)

                    let x = center.x + cos(p.angle) * p.speed * t
                    let y = center.y + sin(p.angle) * p.speed * t + 0.5 * gravity * t * t
                    let opacity = Double(max(0, 1.0 - t / 1.05))
                    guard opacity > 0 else { continue }

                    var copy = drawCtx
                    copy.opacity = opacity
                    let rect = CGRect(x: x - p.size / 2, y: y - p.size / 2,
                                     width: p.size, height: p.size)
                    let path: Path = p.isCircle ? Path(ellipseIn: rect) : Path(rect)
                    copy.fill(path, with: .color(p.color))
                }
            }
        }
        .onAppear { startTime = .now }
    }
}
