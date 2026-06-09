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
            .preferredColorScheme(.dark)
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
                .foregroundStyle(.white)
            Text("Open a friend from People to start a DM.")
                .scaledFont(size: 13)
                .foregroundStyle(Color(white: 0.55))
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
            Circle()
                .fill(avatarColor(for: summary.friend.id).opacity(0.72))
                .frame(width: 46, height: 46)
                .overlay {
                    Text(String(displayName.prefix(1)).uppercased())
                        .scaledFont(size: 17, weight: .bold)
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(displayName)
                        .scaledFont(size: 14, weight: .semibold)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer()
                    if let date = summary.lastMessageAt {
                        Text(date, format: .dateTime.month(.abbreviated).day())
                            .scaledFont(size: 10, weight: .medium)
                            .foregroundStyle(Color(white: 0.45))
                    }
                }

                HStack(spacing: 8) {
                    Text(summary.preview)
                        .scaledFont(size: 12)
                        .foregroundStyle(Color(white: 0.58))
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

    private func avatarColor(for id: UUID) -> Color {
        Color.participantPalette[abs(id.hashValue) % Color.participantPalette.count]
    }
}

struct MessageThreadView: View {
    let conversationId: UUID
    let friend: Profile

    @Environment(\.dismiss) private var dismiss

    @State private var messages: [Message] = []
    @State private var draft = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var isSending = false
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
        }
        .preferredColorScheme(.dark)
        .task {
            await load()
            await markRead()
            await subscribeToThreadChanges()
        }
        .task(id: selectedPhoto?.itemIdentifier) { await loadSelectedPhoto() }
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
                        .foregroundStyle(Color(white: 0.65))
                    Spacer()
                    Button {
                        self.selectedImage = nil
                        self.selectedPhoto = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .scaledFont(size: 20)
                            .foregroundStyle(Color(white: 0.55))
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
                .disabled(isSending)

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
                .disabled(!canSend || isSending)
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

    private func load() async {
        do {
            let next = try await DirectMessageService.shared.listMessages(conversationId: conversationId)
            if messages != next {
                messages = next
            }
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadSelectedPhoto() async {
        guard let selectedPhoto else { return }
        do {
            guard let data = try await selectedPhoto.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { return }
            selectedImage = image
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func send() async {
        guard canSend, !isSending else { return }
        isSending = true
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
            await markRead()
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
        isSending = false
    }

    private func delete(_ message: Message) async {
        do {
            try await DirectMessageService.shared.deleteMessage(message)
            messages.removeAll { $0.id == message.id }
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
                await load()
                await markRead()
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
    let onDelete: () -> Void

    var body: some View {
        HStack {
            if isMine { Spacer(minLength: 46) }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 6) {
                if let path = message.imagePath {
                    MessageImage(path: path)
                }
                if let body = message.body, !body.isEmpty {
                    Text(body)
                        .scaledFont(size: 14)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(isMine ? .trailing : .leading)
                }
                Text(message.createdAt, format: .dateTime.hour().minute())
                    .scaledFont(size: 9, weight: .medium)
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(isMine ? Color.coral : Color.appSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .contextMenu {
                if isMine {
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            if !isMine { Spacer(minLength: 46) }
        }
    }
}

private struct MessageImage: View {
    let path: String

    @State private var url: URL?

    var body: some View {
        Group {
            if let url {
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
                        Image(systemName: "photo")
                            .scaledFont(size: 24)
                            .foregroundStyle(.white.opacity(0.55))
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
        .task(id: path) {
            url = try? await DirectMessageService.shared.signedImageURL(for: path)
        }
    }
}
