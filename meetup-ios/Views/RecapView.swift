import SwiftUI
import Auth
import PhotosUI

struct RecapView: View {
    let meetup: Meetup

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthViewModel.self) private var auth

    @State private var participants: [MeetupParticipant] = []
    @State private var receipts: [Receipt] = []
    @State private var receiptItems: [UUID: [BillItem]] = [:]
    @State private var claims: [BillItemClaim] = []
    @State private var hasLoaded = false
    @State private var error: String?
    @State private var showBillView = false

    @State private var meetupPhotos: [MeetupPhoto] = []
    @State private var isUploadingPhoto = false
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var fullscreenPhoto: MeetupPhoto?
    @State private var sharePhoto: MeetupPhoto?

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
                    photoGalleryCard
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
            .sheet(isPresented: $showBillView) {
                BillView(meetup: meetup, participants: participants)
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItem, matching: .images)
            .onChange(of: selectedPhotoItem) { _, item in
                guard let item else { return }
                Task { await uploadPickedPhoto(item) }
            }
            .fullScreenCover(item: $fullscreenPhoto) { photo in
                MeetupPhotoPagerView(
                    photos: meetupPhotos,
                    initialPhoto: photo,
                    currentUserId: myUserId,
                    meetupHostId: meetup.hostId,
                    onPhotoDeleted: { deleted in
                        meetupPhotos.removeAll { $0.id == deleted.id }
                    }
                )
            }
            .sheet(item: $sharePhoto) { photo in
                if let url = URL(string: photo.photoUrl) {
                    ShareSheet(url: url).ignoresSafeArea()
                }
            }
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
                    .scaledFont(size: 28)
                    .frame(width: 48, height: 48)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 2) {
                    Text(meetup.destinationName)
                        .scaledFont(size: 20, weight: .bold)
                        .foregroundStyle(Color(.label))
                        .lineLimit(2)
                    if let addr = meetup.destinationAddress, !addr.isEmpty {
                        Text(addr)
                            .scaledFont(size: 12)
                            .foregroundStyle(Color(.secondaryLabel))
                            .lineLimit(1)
                    }
                }
            }

            Divider()

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
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color(.separator).opacity(0.5), lineWidth: 1)
        )
    }

    private func recapDetail(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .scaledFont(size: 12)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(label)
                .scaledFont(size: 12)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .scaledFont(size: 12, weight: .medium)
                .foregroundStyle(Color(.label))
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
                    .scaledFont(size: 28, weight: .black)
                    .foregroundStyle(Color(.label))
                Text("people showed up")
                    .scaledFont(size: 13)
                    .foregroundStyle(.secondary)
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
                attendeeGroup(title: "Said no / maybe", icon: "minus.circle", iconColor: Color(.secondaryLabel), people: declined)
            }
            if !hasLoaded {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))
                    .frame(height: 80)
                    .overlay(ProgressView())
            }
        }
    }

    private func attendeeGroup(title: String, icon: String, iconColor: Color, people: [MeetupParticipant]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(iconColor)
                Text(title.uppercased())
                    .scaledFont(size: 10, weight: .semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(people.count)")
                    .scaledFont(size: 10, weight: .semibold)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ForEach(Array(people.enumerated()), id: \.element.id) { index, person in
                if index > 0 {
                    Divider()
                        .padding(.leading, 46)
                }
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color.participantPalette[index % Color.participantPalette.count].opacity(0.7))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Text(String((person.displayName ?? "?").prefix(1)).uppercased())
                                .scaledFont(size: 11, weight: .bold)
                                .foregroundStyle(.white)
                        )
                    Text(person.displayName ?? "Unknown")
                        .scaledFont(size: 14)
                        .foregroundStyle(Color(.label))
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color(.separator).opacity(0.5), lineWidth: 1)
        )
    }

    // MARK: - Bill Summary Card

    @ViewBuilder
    private var billPlaceholderCard: some View {
        if receipts.isEmpty {
            Button { showBillView = true } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.coral.opacity(0.15))
                            .frame(width: 40, height: 40)
                        Image(systemName: "dollarsign.circle")
                            .scaledFont(size: 18)
                            .foregroundStyle(Color.coral.opacity(0.8))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No receipts")
                            .scaledFont(size: 14, weight: .semibold)
                            .foregroundStyle(Color(.label))
                        Text("Bill splitting not started")
                            .scaledFont(size: 12)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .scaledFont(size: 12, weight: .semibold)
                        .foregroundStyle(Color(.tertiaryLabel))
                }
                .padding(14)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color(.separator).opacity(0.5), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        } else {
            billBreakdownCard
        }
    }

    private var billBreakdownCard: some View {
        Button { showBillView = true } label: {
        billBreakdownCardContent
        }
        .buttonStyle(.plain)
    }

    private var billBreakdownCardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.coral.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: "dollarsign.circle")
                        .scaledFont(size: 15)
                        .foregroundStyle(Color.coral.opacity(0.8))
                }
                Text("Bill Summary")
                    .scaledFont(size: 14, weight: .semibold)
                    .foregroundStyle(Color(.label))
                Spacer()
                HStack(spacing: 4) {
                    Text("View details")
                        .scaledFont(size: 11)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .scaledFont(size: 10, weight: .semibold)
                        .foregroundStyle(Color(.tertiaryLabel))
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            ForEach(receipts) { receipt in
                let payerName = participants.first(where: { $0.userId == receipt.payerUserId })?.displayName ?? "Unknown"
                let myOwed = myOwedInRecap(receipt)
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(receipt.placeName)
                            .scaledFont(size: 13, weight: .medium)
                            .foregroundStyle(Color(.label))
                        Text("Paid by \(payerName)")
                            .scaledFont(size: 11)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if myOwed > 0 {
                        Text("You owe \(myOwed, format: .currency(code: "USD"))")
                            .scaledFont(size: 12, weight: .semibold)
                            .foregroundStyle(Color.coral.opacity(0.9))
                    } else {
                        Text(receipt.totalAmount, format: .currency(code: "USD"))
                            .scaledFont(size: 12)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)

                if receipt.id != receipts.last?.id {
                    Divider()
                        .padding(.leading, 14)
                }
            }

            let crossTotal = crossReceiptMyTotalRecap
            if crossTotal > 0 {
                Divider()
                HStack {
                    Text("Total you owe")
                        .scaledFont(size: 12, weight: .semibold)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(crossTotal, format: .currency(code: "USD"))
                        .scaledFont(size: 14, weight: .bold)
                        .foregroundStyle(Color.coral)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color(.separator).opacity(0.5), lineWidth: 1)
        )
    }

    private func myOwedInRecap(_ receipt: Receipt) -> Double {
        guard let me = myUserId else { return 0 }
        let totals = BillService.computeReceiptTotals(
            receipts: [receipt], items: receiptItems, claims: claims, participants: participants
        )
        return totals[receipt.id]?.first(where: { $0.userId == me })?.total ?? 0
    }

    private var crossReceiptMyTotalRecap: Double {
        guard let me = myUserId else { return 0 }
        var total = 0.0
        let allTotals = BillService.computeReceiptTotals(
            receipts: receipts, items: receiptItems, claims: claims, participants: participants
        )
        for (_, personTotals) in allTotals {
            total += personTotals.first(where: { $0.userId == me })?.total ?? 0
        }
        return total
    }

    // MARK: - Photo Gallery

    private var photoGalleryCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.coral.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: "camera.fill")
                        .scaledFont(size: 14)
                        .foregroundStyle(Color.coral.opacity(0.8))
                }
                Text("Photos")
                    .scaledFont(size: 14, weight: .semibold)
                    .foregroundStyle(Color(.label))
                Spacer()
                if isUploadingPhoto {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Button {
                        showPhotoPicker = true
                    } label: {
                        Image(systemName: "plus")
                            .scaledFont(size: 13, weight: .semibold)
                            .foregroundStyle(Color.coral)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            if meetupPhotos.isEmpty {
                Button {
                    showPhotoPicker = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "camera")
                            .scaledFont(size: 16)
                            .foregroundStyle(Color.coral.opacity(0.7))
                        Text("Add Photos")
                            .scaledFont(size: 14, weight: .medium)
                            .foregroundStyle(Color.coral.opacity(0.9))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
                .buttonStyle(.plain)
            } else {
                let columns = [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)]
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(meetupPhotos) { photo in
                        AsyncImage(url: URL(string: photo.photoUrl)) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            case .failure:
                                Color(.tertiarySystemBackground)
                                    .overlay(
                                        Image(systemName: "photo")
                                            .foregroundStyle(.secondary)
                                    )
                            default:
                                Color(.tertiarySystemBackground)
                                    .overlay(ProgressView().scaleEffect(0.7))
                            }
                        }
                        .frame(height: 140)
                        .clipped()
                        .contentShape(Rectangle())
                        .onTapGesture { fullscreenPhoto = photo }
                        .onLongPressGesture { sharePhoto = photo }
                    }
                }
                .padding(.top, 2)
            }
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color(.separator).opacity(0.5), lineWidth: 1)
        )
    }

    private func uploadPickedPhoto(_ item: PhotosPickerItem) async {
        isUploadingPhoto = true
        defer {
            isUploadingPhoto = false
            selectedPhotoItem = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let uiImage = UIImage(data: data) else { return }
            let urlString = try await MeetupPhotoService.shared.uploadPhoto(image: uiImage, meetupId: meetup.id)
            try await MeetupPhotoService.shared.insertPhoto(meetupId: meetup.id, url: urlString, caption: nil)
            meetupPhotos = (try? await MeetupPhotoService.shared.fetchPhotos(meetupId: meetup.id)) ?? meetupPhotos
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Data

    private func load() async {
        do {
            async let participantsFetch = MeetupService.shared.listParticipants(meetupId: meetup.id)
            async let receiptsFetch = BillService.shared.fetchReceipts(meetupId: meetup.id)

            let (fetchedParticipants, fetchedReceipts) = try await (participantsFetch, receiptsFetch)
            if fetchedParticipants != participants { participants = fetchedParticipants }
            receipts = fetchedReceipts

            for receipt in fetchedReceipts {
                receiptItems[receipt.id] = try await BillService.shared.fetchReceiptItems(receiptId: receipt.id)
            }
            claims = try await BillService.shared.fetchAllReceiptClaims(receiptIds: fetchedReceipts.map { $0.id })
            meetupPhotos = (try? await MeetupPhotoService.shared.fetchPhotos(meetupId: meetup.id)) ?? []

            hasLoaded = true
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
            hasLoaded = true
        }
    }
}

// MARK: - Share Sheet

private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
