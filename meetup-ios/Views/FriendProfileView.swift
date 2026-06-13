import SwiftUI

struct FriendProfileView: View {
    let profile: Profile
    let displayName: String
    let isPending: Bool
    let onMessage: (() -> Void)?
    let onRemove: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var stats: FriendProfileStats?
    @State private var isLoadingStats = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 14) {
                        ProfileAvatarView(
                            displayName: displayName,
                            avatarUrl: profile.avatarUrl,
                            userId: profile.id,
                            size: 118,
                            fontSize: 42
                        )
                        .overlay {
                            Circle()
                                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                        }

                        VStack(spacing: 6) {
                            Text(displayName)
                                .scaledFont(size: 24, weight: .bold)
                                .foregroundStyle(DS.Color.textPrimary)
                                .multilineTextAlignment(.center)

                            Text(isPending ? "Pending request" : "Friend")
                                .scaledFont(size: 12, weight: .semibold)
                                .foregroundStyle(isPending ? Color(white: 0.72) : Color.coral)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.08))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.top, 26)

                    VStack(spacing: 10) {
                        if let phone = profile.phoneE164, !phone.isEmpty {
                            profileRow("phone.fill", title: "Phone", value: phone)
                        }

                        if let email = profile.email, !email.isEmpty {
                            profileRow("envelope.fill", title: "Email", value: email)
                        }
                    }

                    if !isPending {
                        statsSection
                    }

                    VStack(spacing: 10) {
                        if let onMessage, !isPending {
                            Button {
                                dismiss()
                                onMessage()
                            } label: {
                                Label("Message", systemImage: "bubble.left.and.bubble.right.fill")
                                    .scaledFont(size: 15, weight: .bold)
                                    .foregroundStyle(Color.appAccentForeground)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .background(Color.coral)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                        }

                        if let onRemove {
                            Button(role: .destructive) {
                                dismiss()
                                onRemove()
                            } label: {
                                Label(isPending ? "Cancel Request" : "Remove Friend", systemImage: isPending ? "xmark" : "person.badge.minus")
                                    .scaledFont(size: 14, weight: .semibold)
                                    .foregroundStyle(.red.opacity(0.9))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.white.opacity(0.07))
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .background(Color.appBackground)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .scaledFont(size: 22)
                            .foregroundStyle(DS.Color.textSecondary)
                    }
                    .accessibilityLabel("Close profile")
                }
            }
        }

        .task(id: profile.id) {
            await loadStats()
        }
    }

    private var statsSection: some View {
        HStack(spacing: 8) {
            statTile(
                title: "Events",
                value: stats.map { "\($0.totalEvents)" } ?? (isLoadingStats ? "..." : "0"),
                color: Color.coral
            )
            statTile(
                title: "On Time",
                value: stats.map { "\($0.onTimeCount)" } ?? (isLoadingStats ? "..." : "0"),
                color: Color.statusLive
            )
            statTile(
                title: "Late",
                value: stats.map { "\($0.lateCount)" } ?? (isLoadingStats ? "..." : "0"),
                color: Color.statusLate
            )
        }
    }

    private func statTile(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 5) {
            Text(value)
                .scaledFont(size: 22, weight: .bold)
                .foregroundStyle(DS.Color.textPrimary)
                .frame(height: 27)

            Text(title)
                .scaledFont(size: 11, weight: .semibold)
                .foregroundStyle(DS.Color.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background(color.opacity(0.13))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(color.opacity(0.18), lineWidth: 1)
        }
    }

    private func loadStats() async {
        guard !isPending else { return }
        isLoadingStats = true
        defer { isLoadingStats = false }
        do {
            stats = try await ProfileStatsService.shared.stats(for: profile.id)
        } catch is CancellationError {
            return
        } catch {
            stats = FriendProfileStats(totalEvents: 0, onTimeCount: 0, lateCount: 0)
        }
    }

    private func profileRow(_ systemImage: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .scaledFont(size: 14, weight: .semibold)
                .foregroundStyle(Color.coral)
                .frame(width: 30, height: 30)
                .background(Color.coral.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .scaledFont(size: 11, weight: .semibold)
                    .foregroundStyle(DS.Color.textSecondary)
                Text(value)
                    .scaledFont(size: 14, weight: .medium)
                    .foregroundStyle(DS.Color.textPrimary)
                    .textSelection(.enabled)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        }
    }
}
