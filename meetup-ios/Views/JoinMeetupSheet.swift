import SwiftUI

struct JoinMeetupSheet: View {
    let shareToken: String
    let onJoined: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var meetup: Meetup?
    @State private var isLoading = true
    @State private var isJoining = false
    @State private var joined = false
    @State private var error: String?

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading invite…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let meetup {
                    meetupContent(meetup)
                } else {
                    errorContent
                }
            }
            .navigationTitle("You're Invited")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task {
            await loadMeetup()
        }
        .alert("Error", isPresented: Binding(
            get: { error != nil },
            set: { if !$0 { error = nil } }
        )) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    // MARK: - Sub-views

    @ViewBuilder
    private func meetupContent(_ meetup: Meetup) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    // Hero icon
                    ZStack {
                        Circle()
                            .fill(Color.coral.opacity(0.12))
                            .frame(width: 80, height: 80)
                        Text(meetupCategoryEmoji(meetup.category))
                            .scaledFont(size: 38)
                    }
                    .padding(.top, 24)

                    // Details card
                    VStack(spacing: 16) {
                        detailRow(
                            icon: "mappin.circle.fill",
                            iconColor: Color.coral,
                            title: meetup.destinationName,
                            subtitle: meetup.destinationAddress
                        )

                        if let target = meetup.targetArrivalAt {
                            Divider()
                            detailRow(
                                icon: "clock.fill",
                                iconColor: Color.statusLive,
                                title: "Meet at",
                                subtitle: Self.timeFormatter.string(from: target)
                            )
                        }

                        if let category = meetup.category, !category.isEmpty {
                            Divider()
                            detailRow(
                                icon: "tag.fill",
                                iconColor: Color.statusPending,
                                title: category,
                                subtitle: nil
                            )
                        }
                    }
                    .padding(16)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(Color(.separator).opacity(0.5), lineWidth: 1)
                    )
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 100)
            }

            // Join button pinned to bottom
            VStack(spacing: 0) {
                Divider()
                if joined {
                    Label("You're in!", systemImage: "checkmark.circle.fill")
                        .scaledFont(size: 16, weight: .bold)
                        .foregroundStyle(Color.statusLive)
                        .padding(.vertical, 20)
                } else {
                    Button {
                        Task { await join(meetup) }
                    } label: {
                        Group {
                            if isJoining {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Join Meetup")
                                    .scaledFont(size: 16, weight: .bold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.coral)
                        .foregroundStyle(Color.appAccentForeground)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(isJoining)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
            .background(.regularMaterial)
        }
    }

    private var errorContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "link.badge.plus")
                .scaledFont(size: 48)
                .foregroundStyle(.secondary)
            Text("Invite link invalid or expired")
                .scaledFont(size: 16, weight: .semibold)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func detailRow(icon: String, iconColor: Color, title: String, subtitle: String?) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .scaledFont(size: 20)
                .foregroundStyle(iconColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .scaledFont(size: 14, weight: .semibold)
                    .lineLimit(2)
                if let sub = subtitle {
                    Text(sub)
                        .scaledFont(size: 12)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
    }

    // MARK: - Logic

    private func loadMeetup() async {
        do {
            meetup = try await MeetupService.shared.fetchMeetupByShareToken(shareToken)
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func join(_ meetup: Meetup) async {
        isJoining = true
        do {
            let meetupId = try await MeetupService.shared.joinByShareToken(shareToken)
            withAnimation { joined = true }
            try? await Task.sleep(for: .seconds(1.5))
            dismiss()
            onJoined(meetupId)
        } catch is CancellationError {
            isJoining = false
            return
        } catch {
            self.error = error.localizedDescription
            isJoining = false
        }
    }
}
