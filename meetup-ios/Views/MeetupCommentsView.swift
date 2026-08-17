import SwiftUI
import Supabase

struct MeetupCommentsView: View {
    let meetup: Meetup

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthViewModel.self) private var auth

    @State private var comments: [MeetupComment] = []
    @State private var draft = ""
    @State private var hasLoaded = false
    @State private var isSending = false
    @State private var error: String?

    private var myUserId: UUID? { auth.session?.user.id }
    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            if !hasLoaded {
                                ProgressView()
                                    .tint(Color.coral)
                                    .padding(.top, 40)
                            } else if comments.isEmpty {
                                emptyState
                                    .padding(.top, 54)
                            } else {
                                ForEach(comments) { comment in
                                    MeetupCommentRow(
                                        comment: comment,
                                        isMine: comment.authorUserId == myUserId,
                                        onDelete: { Task { await delete(comment) } }
                                    )
                                    .id(comment.id)
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                    }
                    .onChange(of: comments.last?.id) { _, id in
                        guard let id else { return }
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(id, anchor: .bottom)
                        }
                    }
                }

                composer
            }
            .background(Color.appBackground)
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.coral)
                }
            }
            .task(id: meetup.id) {
                await load()
                async let realtime: Void = subscribeToCommentChanges()
                async let refresh: Void = refreshFallback()
                _ = await (realtime, refresh)
            }
            .alert("Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.bubble")
                .scaledFont(size: 42)
                .foregroundStyle(Color.coral.opacity(0.45))
            Text("No comments yet")
                .scaledFont(size: 17, weight: .bold)
                .foregroundStyle(DS.Color.textPrimary)
            Text("Start the thread for this meetup.")
                .scaledFont(size: 13)
                .foregroundStyle(DS.Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 28)
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Add a comment", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .scaledFont(size: 14)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .disabled(isSending)

            Button {
                Task { await send() }
            } label: {
                if isSending {
                    ProgressView()
                        .tint(.white)
                        .frame(width: 36, height: 36)
                } else {
                    Image(systemName: "arrow.up")
                        .scaledFont(size: 16, weight: .bold)
                        .foregroundStyle(canSend ? Color.appAccentForeground : .white)
                        .frame(width: 36, height: 36)
                        .background(canSend ? Color.coral : Color.white.opacity(0.12))
                        .clipShape(Circle())
                }
            }
            .buttonStyle(.plain)
            .disabled(!canSend || isSending)
            .accessibilityLabel("Post comment")
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(Color.appSurface)
    }

    private func load() async {
        do {
            let next = try await MeetupCommentService.shared.listComments(meetupId: meetup.id)
            if comments != next {
                comments = next
            }
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
        hasLoaded = true
    }

    private func send() async {
        guard canSend, !isSending else { return }
        isSending = true
        defer { isSending = false }
        do {
            try await MeetupCommentService.shared.postComment(meetupId: meetup.id, body: draft)
            draft = ""
            await load()
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func delete(_ comment: MeetupComment) async {
        do {
            try await MeetupCommentService.shared.deleteComment(comment)
            comments.removeAll { $0.id == comment.id }
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func refreshFallback() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(20))
            } catch {
                return
            }
            await load()
        }
    }

    private func subscribeToCommentChanges() async {
        let channel = SupabaseManager.shared.client.realtimeV2.channel("meetup-comments-\(meetup.id)")
        let changes = channel.postgresChange(AnyAction.self, schema: "public", table: "meetup_comments")
        do {
            try await channel.subscribeWithError()
        } catch {
            return
        }
        do {
            for await _ in changes {
                try Task.checkCancellation()
                await load()
            }
        } catch {
            // CancellationError - fall through to removeChannel.
        }
        await SupabaseManager.shared.client.realtimeV2.removeChannel(channel)
    }
}

private struct MeetupCommentRow: View {
    let comment: MeetupComment
    let isMine: Bool
    let onDelete: () -> Void

    private var authorName: String {
        comment.authorDisplayName ?? "Someone"
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if !isMine {
                ProfileAvatarView(
                    displayName: comment.authorDisplayName,
                    avatarUrl: comment.authorAvatarUrl,
                    userId: comment.authorUserId,
                    size: 30,
                    fontSize: 12
                )
            } else {
                Spacer(minLength: 44)
            }

            VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
                if !isMine {
                    Text(authorName)
                        .scaledFont(size: 10, weight: .semibold)
                        .foregroundStyle(DS.Color.textSecondary)
                        .padding(.leading, 2)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(comment.body)
                        .scaledFont(size: 14)
                        .foregroundStyle(isMine ? .white : DS.Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(comment.createdAt, format: .dateTime.hour().minute())
                        .scaledFont(size: 9, weight: .medium)
                        .foregroundStyle(isMine ? .white.opacity(0.45) : DS.Color.textSecondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(isMine ? Color.coral : Color.appSurface)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .contextMenu {
                    if isMine {
                        Button(role: .destructive) {
                            onDelete()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }

            if !isMine {
                Spacer(minLength: 44)
            }
        }
        .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
    }
}
