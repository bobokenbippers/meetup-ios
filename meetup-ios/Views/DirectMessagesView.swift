import SwiftUI
import PhotosUI
import Supabase
import UIKit

struct DirectMessagesView: View {
    @State private var summaries: [ConversationSummary] = []
    @State private var hasLoaded = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if !hasLoaded {
                    ProgressView()
                        .tint(Color.coral)
                } else if summaries.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(summaries) { summary in
                            NavigationLink {
                                MessageThreadView(conversationId: summary.id, friend: summary.friend)
                            } label: {
                                ConversationRow(summary: summary)
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .navigationTitle("Messages")

            .task {
                await load()
                await subscribeToMessageChanges()
            }
            .refreshable { await load() }
            .alert("Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .scaledFont(size: 48)
                .foregroundStyle(Color.coral.opacity(0.45))
            Text("No messages yet")
                .scaledFont(size: 17, weight: .bold)
                .foregroundStyle(DS.Color.textPrimary)
            Text("Open a friend from People to start a DM.")
                .scaledFont(size: 13)
                .foregroundStyle(DS.Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
    }

    private func load() async {
        do {
            let next = try await DirectMessageService.shared.listConversationSummaries()
            if summaries != next {
                summaries = next
            }
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
        hasLoaded = true
    }

    private func subscribeToMessageChanges() async {
        guard let myId = SupabaseManager.shared.client.auth.currentUser?.id else { return }
        let channel = SupabaseManager.shared.client.realtimeV2.channel("direct-messages-\(myId)")
        let changes = channel.postgresChange(AnyAction.self, schema: "public", table: "messages")
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
            // CancellationError — fall through to removeChannel.
        }
        await SupabaseManager.shared.client.realtimeV2.removeChannel(channel)
    }
}

private struct ConversationRow: View {
    let summary: ConversationSummary

    private var displayName: String {
        summary.friend.displayName ?? "Unknown"
    }

    var body: some View {
        HStack(spacing: 12) {
            ProfileAvatarView(profile: summary.friend, size: 46, fontSize: 17)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(displayName)
                        .scaledFont(size: 14, weight: .semibold)
                        .foregroundStyle(DS.Color.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    if let date = summary.lastMessageAt {
                        Text(date, format: .dateTime.month(.abbreviated).day())
                            .scaledFont(size: 10, weight: .medium)
                            .foregroundStyle(DS.Color.textSecondary)
                    }
                }

                HStack(spacing: 8) {
                    Text(summary.preview)
                        .scaledFont(size: 12)
                        .foregroundStyle(DS.Color.textSecondary)
                        .lineLimit(1)
                    Spacer()
                    if summary.unreadCount > 0 {
                        Text("\(summary.unreadCount)")
                            .scaledFont(size: 10, weight: .bold)
                            .foregroundStyle(.white)
                            .frame(minWidth: 20, minHeight: 20)
                            .background(Color.coral)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        }
    }
}

struct MessageThreadView: View {
    let conversationId: UUID
    let friend: Profile

    @Environment(\.dismiss) private var dismiss

    @State private var messages: [Message] = []
    @State private var reactionSummaries: [UUID: [MessageReactionSummary]] = [:]
    @State private var draft = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var isPreparingPhoto = false
    @State private var isSending = false
    @State private var failedPhotoSelection: String?
    @State private var presentedPhoto: MessagePhotoPreview?
    @State private var isShowingFriendProfile = false
    @State private var editingMessage: Message?
    @State private var editDraft = ""
    @State private var lastMarkedReadMessageId: UUID?
    @State private var error: String?

    private var myId: UUID? { SupabaseManager.shared.client.auth.currentUser?.id }
    private var friendName: String { friend.displayName ?? "Unknown" }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(messages) { message in
                            MessageBubble(
                                message: message,
                                isMine: message.senderId == myId,
                                reactionSummaries: reactionSummaries[message.id] ?? [],
                                onOpenPhoto: { url in
                                    presentedPhoto = MessagePhotoPreview(
                                        url: url,
                                        caption: message.body?.isEmpty == false ? message.body : nil
                                    )
                                },
                                onToggleReaction: { emoji in
                                    Task { await toggleReaction(emoji, for: message) }
                                },
                                onEdit: {
                                    editingMessage = message
                                    editDraft = message.body ?? ""
                                },
                                onDelete: { Task { await delete(message) } }
                            )
                            .id(message.id)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .onChange(of: messages.last?.id) { _, id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
            }

            composer
        }
        .background(Color.appBackground)
        .navigationTitle(friendName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Label("Messages", systemImage: "chevron.left")
                        .labelStyle(.titleAndIcon)
                }
                .foregroundStyle(Color.coral)
                .accessibilityLabel("Back to messages")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    isShowingFriendProfile = true
                } label: {
                    ProfileAvatarView(profile: friend, size: 30, fontSize: 12)
                        .overlay {
                            Circle()
                                .strokeBorder(.white.opacity(0.16), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View \(friendName)'s profile")
            }
        }

        .task(id: conversationId) {
            await load()
            await markRead()
            lastMarkedReadMessageId = messages.last?.id
            async let realtime: Void = subscribeToThreadChanges()
            async let refresh: Void = refreshThreadFallback()
            _ = await (realtime, refresh)
        }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            Task { await loadSelectedPhoto(item) }
        }
        .sheet(item: $presentedPhoto) { photo in
            MessagePhotoPreviewView(photo: photo)
        }
        .sheet(isPresented: $isShowingFriendProfile) {
            FriendProfileView(
                profile: friend,
                displayName: friendName,
                isPending: false,
                onMessage: nil,
                onRemove: nil
            )
        }
        .alert("Edit Message", isPresented: Binding(get: { editingMessage != nil }, set: { if !$0 { editingMessage = nil } })) {
            TextField("Message", text: $editDraft, axis: .vertical)
            Button("Cancel", role: .cancel) {
                editingMessage = nil
                editDraft = ""
            }
            Button("Save") {
                guard let editingMessage else { return }
                Task { await edit(editingMessage, body: editDraft) }
            }
        }
        .alert("Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if let selectedImage {
                HStack(spacing: 10) {
                    Image(uiImage: selectedImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 54, height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    Text("Photo ready")
                        .scaledFont(size: 12, weight: .medium)
                        .foregroundStyle(DS.Color.textSecondary)
                    Spacer()
                    Button {
                        self.selectedImage = nil
                        self.selectedPhoto = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .scaledFont(size: 20)
                            .foregroundStyle(DS.Color.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
            } else if isPreparingPhoto {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(Color.coral)
                    Text("Preparing photo…")
                        .scaledFont(size: 12, weight: .medium)
                        .foregroundStyle(DS.Color.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
            } else if let failedPhotoSelection {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .scaledFont(size: 15, weight: .semibold)
                        .foregroundStyle(Color.coral)
                    Text(failedPhotoSelection)
                        .scaledFont(size: 12, weight: .medium)
                        .foregroundStyle(DS.Color.textSecondary)
                    Spacer()
                    Button {
                        self.failedPhotoSelection = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .scaledFont(size: 20)
                            .foregroundStyle(DS.Color.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
            }

            HStack(spacing: 10) {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Image(systemName: "photo")
                        .scaledFont(size: 18, weight: .semibold)
                        .foregroundStyle(Color.coral)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .disabled(isSending || isPreparingPhoto)

                TextField("Message", text: $draft, axis: .vertical)
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
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(canSend ? Color.coral : Color.white.opacity(0.12))
                            .clipShape(Circle())
                    }
                }
                .buttonStyle(.plain)
                .disabled(!canSend || isSending || isPreparingPhoto)
                .accessibilityLabel("Send message")
            }
            .padding(.horizontal, 12)
        }
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(Color.appSurface)
    }

    private var canSend: Bool {
        selectedImage != nil || !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @discardableResult
    private func load() async -> Bool {
        do {
            let next = try await DirectMessageService.shared.listMessages(conversationId: conversationId)
            let nextReactions = try await DirectMessageService.shared.listReactionSummaries(conversationId: conversationId)
            var changed = false
            if messages != next {
                messages = next
                changed = true
            }
            if reactionSummaries != nextReactions {
                reactionSummaries = nextReactions
                changed = true
            }
            return changed
        } catch is CancellationError {
            return false
        } catch {
            self.error = error.localizedDescription
        }
        return false
    }

    private func toggleReaction(_ emoji: String, for message: Message) async {
        do {
            try await DirectMessageService.shared.toggleReaction(messageId: message.id, emoji: emoji)
            await load()
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadSelectedPhoto(_ item: PhotosPickerItem) async {
        isPreparingPhoto = true
        failedPhotoSelection = nil
        defer {
            isPreparingPhoto = false
            selectedPhoto = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                failedPhotoSelection = "Couldn't prepare that photo."
                return
            }
            selectedImage = image
        } catch is CancellationError {
            return
        } catch {
            failedPhotoSelection = "Couldn't prepare that photo."
        }
    }

    private func send() async {
        guard canSend, !isSending else { return }
        isSending = true
        defer { isSending = false }
        do {
            if let selectedImage {
                try await DirectMessageService.shared.sendImage(selectedImage, caption: draft, conversationId: conversationId)
            } else {
                try await DirectMessageService.shared.sendText(draft, conversationId: conversationId)
            }
            draft = ""
            selectedImage = nil
            selectedPhoto = nil
            await load()
            await markLatestIncomingReadIfNeeded()
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func delete(_ message: Message) async {
        do {
            try await DirectMessageService.shared.deleteMessage(message)
            messages.removeAll { $0.id == message.id }
            reactionSummaries[message.id] = nil
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func edit(_ message: Message, body: String) async {
        do {
            try await DirectMessageService.shared.editMessage(message, body: body)
            editingMessage = nil
            editDraft = ""
            await load()
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func markRead() async {
        do {
            try await DirectMessageService.shared.markRead(conversationId: conversationId)
        } catch is CancellationError {
            return
        } catch {
            return
        }
    }

    private func markLatestIncomingReadIfNeeded() async {
        guard let latest = messages.last, latest.senderId != myId else { return }
        guard latest.id != lastMarkedReadMessageId else { return }
        await markRead()
        lastMarkedReadMessageId = latest.id
    }

    private func refreshThreadFallback() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(20))
            } catch {
                return
            }
            let changed = await load()
            if changed {
                await markLatestIncomingReadIfNeeded()
            }
        }
    }

    private func subscribeToThreadChanges() async {
        let channel = SupabaseManager.shared.client.realtimeV2.channel("thread-\(conversationId)")
        let changes = channel.postgresChange(AnyAction.self, schema: "public", table: "messages")
        do {
            try await channel.subscribeWithError()
        } catch {
            return
        }
        do {
            for await _ in changes {
                try Task.checkCancellation()
                let changed = await load()
                if changed {
                    await markLatestIncomingReadIfNeeded()
                }
            }
        } catch {
            // CancellationError — fall through to removeChannel.
        }
        await SupabaseManager.shared.client.realtimeV2.removeChannel(channel)
    }
}

private struct MessageBubble: View {
    let message: Message
    let isMine: Bool
    let reactionSummaries: [MessageReactionSummary]
    let onOpenPhoto: (URL) -> Void
    let onToggleReaction: (String) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    private static let availableReactions = ["❤️", "😂", "😮", "😢", "🔥", "👍"]
    @State private var showsReactionPicker = false

    var body: some View {
        HStack {
            if isMine { Spacer(minLength: 46) }
            ZStack(alignment: isMine ? .topTrailing : .topLeading) {
                bubbleContent
                    .padding(.top, showsReactionPicker ? 40 : 0)

                if showsReactionPicker {
                    reactionPickerRow
                        .transition(
                            .opacity.combined(
                                with: .scale(
                                    scale: 0.96,
                                    anchor: isMine ? .bottomTrailing : .bottomLeading
                                )
                            )
                        )
                        .zIndex(1)
                }
            }
            if !isMine { Spacer(minLength: 46) }
        }
    }

    private var bubbleContent: some View {
        VStack(alignment: isMine ? .trailing : .leading, spacing: 6) {
            if let path = message.imagePath {
                MessageImage(path: path, onOpen: onOpenPhoto)
            }
            if let body = message.body, !body.isEmpty {
                Text(body)
                    .scaledFont(size: 14)
                    .foregroundStyle(isMine ? .white : DS.Color.textPrimary)
                    .multilineTextAlignment(isMine ? .trailing : .leading)
            }
            HStack(spacing: 6) {
                Text(message.createdAt, format: .dateTime.hour().minute())
                    .scaledFont(size: 9, weight: .medium)
                    .foregroundStyle(isMine ? .white.opacity(0.45) : DS.Color.textSecondary)
                Button {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
                        showsReactionPicker.toggle()
                    }
                } label: {
                    Image(systemName: "face.smiling")
                        .scaledFont(size: 10, weight: .semibold)
                        .foregroundStyle(isMine ? .white.opacity(0.62) : DS.Color.textSecondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show reactions")
            }
            if message.editedAt != nil {
                Text("Edited")
                    .scaledFont(size: 9, weight: .medium)
                    .foregroundStyle(isMine ? .white.opacity(0.42) : DS.Color.textSecondary)
            }
            if !reactionSummaries.isEmpty {
                reactionRow
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(isMine ? Color.coral : Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .contextMenu {
            if isMine {
                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                }
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private var reactionPickerRow: some View {
        HStack(spacing: 5) {
            ForEach(Self.availableReactions, id: \.self) { emoji in
                Button {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
                        showsReactionPicker = false
                    }
                    onToggleReaction(emoji)
                } label: {
                    Text(emoji)
                        .scaledFont(size: 13, weight: .semibold)
                        .frame(width: 28, height: 26)
                        .background(isMine ? Color.white.opacity(0.18) : Color.black.opacity(0.07))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("React with \(emoji)")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 4)
    }

    private var reactionRow: some View {
        HStack(spacing: 5) {
            ForEach(reactionSummaries) { reaction in
                Button {
                    onToggleReaction(reaction.emoji)
                } label: {
                    Text("\(reaction.emoji) \(reaction.reactionCount)")
                        .scaledFont(size: 11, weight: .semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(reaction.reactedByMe ? Color.white.opacity(0.24) : Color.black.opacity(0.16))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(reaction.reactionCount) \(reaction.emoji) reactions")
            }
        }
    }
}

private struct MessageImage: View {
    let path: String
    let onOpen: (URL) -> Void

    @State private var url: URL?
    @State private var failedToLoad = false

    var body: some View {
        Group {
            if failedToLoad {
                retryContent
            } else if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .tint(Color.coral)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        retryContent
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                ProgressView()
                    .tint(Color.coral)
            }
        }
        .frame(width: 220, height: 170)
        .background(Color.black.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            guard let url, !failedToLoad else { return }
            onOpen(url)
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(url == nil || failedToLoad ? "Message photo" : "Open message photo")
        .task(id: path) {
            await loadSignedURL()
        }
    }

    private var retryContent: some View {
        Button {
            Task { await loadSignedURL() }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "photo.badge.exclamationmark")
                    .scaledFont(size: 24)
                Text("Tap to retry photo")
                    .scaledFont(size: 11, weight: .semibold)
            }
            .foregroundStyle(.white.opacity(0.65))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func loadSignedURL() async {
        if url != nil, !failedToLoad { return }
        failedToLoad = false
        url = nil
        do {
            url = try await DirectMessageService.shared.signedImageURL(for: path)
        } catch is CancellationError {
            return
        } catch {
            failedToLoad = true
        }
    }
}

private struct MessagePhotoPreview: Identifiable {
    let id = UUID()
    let url: URL
    let caption: String?
}

private struct MessagePhotoPreviewView: View {
    let photo: MessagePhotoPreview

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                AsyncImage(url: photo.url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .tint(Color.coral)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .failure:
                        VStack(spacing: 10) {
                            Image(systemName: "photo.badge.exclamationmark")
                                .scaledFont(size: 44)
                            Text("Couldn't load photo")
                                .scaledFont(size: 14, weight: .semibold)
                        }
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    @unknown default:
                        EmptyView()
                    }
                }

                if let caption = photo.caption {
                    Text(caption)
                        .scaledFont(size: 15)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [.black.opacity(0), .black.opacity(0.7)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .scaledFont(size: 28)
                    .foregroundStyle(.white.opacity(0.82))
                    .padding(20)
            }
            .accessibilityLabel("Close photo")
        }

    }
}
