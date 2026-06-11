import SwiftUI

/// Full-screen swipeable viewer for a meetup's photo gallery.
/// Shared by the meetup dashboard and the recap; supports sharing the
/// visible photo and deleting it when the viewer is the uploader or host.
struct MeetupPhotoPagerView: View {
    let currentUserId: UUID?
    let meetupHostId: UUID
    let onPhotoDeleted: (MeetupPhoto) -> Void

    @State private var photos: [MeetupPhoto]
    @State private var selectedPhotoId: UUID
    @State private var isDeleting = false
    @State private var showDeleteConfirm = false
    @State private var error: String?

    @Environment(\.dismiss) private var dismiss

    init(
        photos: [MeetupPhoto],
        initialPhoto: MeetupPhoto,
        currentUserId: UUID?,
        meetupHostId: UUID,
        onPhotoDeleted: @escaping (MeetupPhoto) -> Void
    ) {
        self.currentUserId = currentUserId
        self.meetupHostId = meetupHostId
        self.onPhotoDeleted = onPhotoDeleted
        _photos = State(initialValue: photos)
        _selectedPhotoId = State(initialValue: initialPhoto.id)
    }

    private var currentPhoto: MeetupPhoto? {
        photos.first(where: { $0.id == selectedPhotoId })
    }

    private var canDeleteCurrent: Bool {
        guard let currentPhoto else { return false }
        return MeetupPhotoService.canDelete(
            photo: currentPhoto,
            currentUserId: currentUserId,
            meetupHostId: meetupHostId
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            TabView(selection: $selectedPhotoId) {
                ForEach(photos) { photo in
                    photoPage(photo)
                        .tag(photo.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .automatic : .never))

            topBar
        }
        .confirmationDialog("Delete this photo?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete Photo", role: .destructive) {
                Task { await deleteCurrentPhoto() }
            }
            Button("Keep Photo", role: .cancel) {}
        }
        .alert("Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    // MARK: - Pages

    private func photoPage(_ photo: MeetupPhoto) -> some View {
        VStack(spacing: 0) {
            AsyncImage(url: URL(string: photo.photoUrl)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failure:
                    Image(systemName: "photo")
                        .scaledFont(size: 48)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                default:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            if photo.caption?.isEmpty == false || photo.uploaderDisplayName != nil {
                VStack(alignment: .leading, spacing: 4) {
                    if let caption = photo.caption, !caption.isEmpty {
                        Text(caption)
                            .scaledFont(size: 15)
                            .foregroundStyle(.white)
                    }
                    if let name = photo.uploaderDisplayName {
                        Text("Shared by \(name)")
                            .scaledFont(size: 12)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
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
    }

    // MARK: - Controls

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .scaledFont(size: 28)
                    .foregroundStyle(.white.opacity(0.8))
            }

            Spacer()

            if let currentPhoto, let url = URL(string: currentPhoto.photoUrl) {
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up.circle.fill")
                        .scaledFont(size: 28)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }

            if canDeleteCurrent {
                Button {
                    showDeleteConfirm = true
                } label: {
                    if isDeleting {
                        ProgressView()
                            .tint(.white)
                            .frame(width: 28, height: 28)
                    } else {
                        Image(systemName: "trash.circle.fill")
                            .scaledFont(size: 28)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .disabled(isDeleting)
            }
        }
        .padding(20)
    }

    // MARK: - Delete

    private func deleteCurrentPhoto() async {
        guard let photo = currentPhoto else { return }
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await MeetupPhotoService.shared.deletePhoto(photo)
            onPhotoDeleted(photo)

            guard let index = photos.firstIndex(where: { $0.id == photo.id }) else { return }
            photos.remove(at: index)
            if photos.isEmpty {
                dismiss()
            } else {
                selectedPhotoId = photos[min(index, photos.count - 1)].id
            }
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }
}
