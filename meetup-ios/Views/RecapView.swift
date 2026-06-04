import SwiftUI

struct RecapView: View {
    let meetup: Meetup

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthViewModel.self) private var auth

    @State private var participants: [MeetupParticipant] = []
    @State private var hasLoaded = false
    @State private var error: String?

    private var myUserId: UUID? { auth.session?.user.id }
    private var isHost: Bool { myUserId == meetup.hostId }

    private var arrived: [MeetupParticipant] {
        participants.filter { $0.status == "arrived" }
    }
    private var noShow: [MeetupParticipant] {
        participants.filter { $0.status == "yes" || $0.status == "accepted" }
    }
    private var declined: [MeetupParticipant] {
        participants.filter { $0.status == "declined" || $0.status == "maybe" || $0.status == "invited" }
    }

    private var hostName: String {
        participants.first(where: { $0.userId == meetup.hostId })?.displayName ?? "Unknown"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    headerCard
                    if isHost { hostSummaryCard }
                    attendeeSection
                    billPlaceholderCard
                    Spacer(minLength: 32)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .scrollContentBackground(.hidden)
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("Recap")
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await load() }
            .alert("Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(meetupCategoryEmoji(meetup.category))
                    .font(.system(size: 28))
                    .frame(width: 48, height: 48)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 2) {
                    Text(meetup.destinationName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    if let addr = meetup.destinationAddress, !addr.isEmpty {
                        Text(addr)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }
            }

            Divider().background(Color.white.opacity(0.08))

            VStack(spacing: 8) {
                if let target = meetup.targetArrivalAt {
                    recapDetail(
                        icon: "clock",
                        label: "Scheduled",
                        value: target.formatted(.dateTime.weekday(.wide).month(.wide).day().hour().minute())
                    )
                }
                if hasLoaded {
                    recapDetail(icon: "person.fill", label: "Hosted by", value: hostName)
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    private func recapDetail(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 16)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.4))
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - Host Summary

    private var hostSummaryCard: some View {
        let total = participants.count
        let came = arrived.count
        return HStack(spacing: 0) {
            Spacer()
            VStack(spacing: 4) {
                Text("\(came) of \(total)")
                    .font(.system(size: 28, weight: .black))
                    .foregroundStyle(.white)
                Text("people showed up")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.45))
            }
            Spacer()
        }
        .padding(.vertical, 20)
        .background(Color.coral.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.coral.opacity(0.18), lineWidth: 1)
        )
    }

    // MARK: - Attendees

    private var attendeeSection: some View {
        VStack(spacing: 12) {
            if !arrived.isEmpty {
                attendeeGroup(title: "Came", icon: "checkmark.circle.fill", iconColor: .statusLive, people: arrived)
            }
            if !noShow.isEmpty {
                attendeeGroup(title: "Said yes, didn't show", icon: "xmark.circle", iconColor: .statusLate, people: noShow)
            }
            if !declined.isEmpty {
                attendeeGroup(title: "Said no / maybe", icon: "minus.circle", iconColor: Color.white.opacity(0.3), people: declined)
            }
            if !hasLoaded {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.04))
                    .frame(height: 80)
                    .overlay(ProgressView())
            }
        }
    }

    private func attendeeGroup(title: String, icon: String, iconColor: Color, people: [MeetupParticipant]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(iconColor)
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
                Text("\(people.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ForEach(Array(people.enumerated()), id: \.element.id) { index, person in
                if index > 0 {
                    Divider()
                        .background(Color.white.opacity(0.05))
                        .padding(.leading, 46)
                }
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color.participantPalette[index % Color.participantPalette.count].opacity(0.7))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Text(String((person.displayName ?? "?").prefix(1)).uppercased())
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        )
                    Text(person.displayName ?? "Unknown")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.8))
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - Bill Placeholder

    private var billPlaceholderCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.coral.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: "dollarsign.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.coral.opacity(0.8))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Bill Summary")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                Text("See who owes what")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.2))
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - Data

    private func load() async {
        do {
            let result = try await MeetupService.shared.listParticipants(meetupId: meetup.id)
            if result != participants { participants = result }
            hasLoaded = true
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
            hasLoaded = true
        }
    }
}
