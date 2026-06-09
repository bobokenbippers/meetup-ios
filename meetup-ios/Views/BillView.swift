import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import Supabase
import Auth

struct BillView: View {
    let meetup: Meetup
    let participants: [MeetupParticipant]
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthViewModel.self) private var auth

    @State private var receipts: [Receipt] = []
    @State private var receiptItems: [UUID: [BillItem]] = [:]
    @State private var claims: [BillItemClaim] = []
    @State private var hasLoaded = false
    @State private var error: String?
    @State private var showAddReceipt = false
    @State private var showSummary = false
    @State private var expandedReceiptId: UUID?
    @State private var realtimeTask: Task<Void, Never>?

    private var myUserId: UUID? { auth.session?.user.id }

    var body: some View {
        NavigationStack {
            Group {
                if !hasLoaded {
                    ProgressView()
                } else if receipts.isEmpty {
                    emptyView
                } else {
                    receiptListView
                }
            }
            .navigationTitle("Split Bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if !receipts.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Summary") { showSummary = true }
                    }
                }
            }
            .alert("Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
            .sheet(isPresented: $showAddReceipt) {
                AddReceiptView(meetup: meetup, participants: participants) { receipt, items in
                    receipts.append(receipt)
                    receiptItems[receipt.id] = items
                    expandedReceiptId = receipt.id
                    startRealtime()
                }
            }
            .sheet(isPresented: $showSummary) {
                summarySheet
            }
        }
        .task { await load() }
        .onDisappear { realtimeTask?.cancel() }
    }

    // MARK: - Empty View

    private var emptyView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "receipt.stack")
                .scaledFont(size: 56)
                .foregroundStyle(.secondary)
            VStack(spacing: 8) {
                Text("No receipts yet")
                    .font(.title3.bold())
                Text("Add a receipt for each place you visited to split the bill.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }
            Button {
                showAddReceipt = true
            } label: {
                Label("Add First Receipt", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .padding(.horizontal)
            Spacer()
        }
    }

    // MARK: - Receipt List

    private var receiptListView: some View {
        ZStack(alignment: .bottom) {
            List {
                ForEach(receipts) { receipt in
                    receiptSection(receipt: receipt)
                }
                Section {
                    Button {
                        showAddReceipt = true
                    } label: {
                        Label("Add Another Receipt", systemImage: "plus")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .contentMargins(.bottom, 80, for: .scrollContent)

            bottomBar
        }
    }

    private func receiptSection(receipt: Receipt) -> some View {
        let payerName = participants.first(where: { $0.userId == receipt.payerUserId })?.displayName ?? "Unknown"
        let isExpanded = expandedReceiptId == receipt.id
        let items = receiptItems[receipt.id] ?? []

        return Section {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedReceiptId = isExpanded ? nil : receipt.id
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(receipt.placeName)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("Paid by \(payerName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(receipt.totalAmount, format: .currency(code: "USD"))
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                if items.isEmpty {
                    Text("No items")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(items) { item in
                        itemRow(item: item)
                    }
                }
                let myOwed = myOwedForReceipt(receipt)
                if myOwed > 0 {
                    HStack {
                        Text("You owe at \(receipt.placeName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(myOwed, format: .currency(code: "USD"))
                            .font(.caption.bold())
                            .foregroundStyle(Color.coral)
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private func itemRow(item: BillItem) -> some View {
        let itemClaims = claims.filter { $0.billItemId == item.id }
        let isMine = itemClaims.contains { $0.userId == myUserId }
        let claimNames = itemClaims.compactMap { c in
            participants.first(where: { $0.userId == c.userId })?.displayName
        }
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                if !claimNames.isEmpty {
                    Text(claimNames.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(item.price, format: .currency(code: "USD"))
                .foregroundStyle(itemClaims.isEmpty ? Color.coral : .primary)
            Button {
                Task { await toggleClaim(item: item, isMine: isMine) }
            } label: {
                Image(systemName: isMine ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isMine ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isMine ? "Unclaim \(item.name)" : "Claim \(item.name)")
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total you owe")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(crossReceiptMyTotal, format: .currency(code: "USD"))
                        .font(.headline)
                }
                Spacer()
                Button("See all totals") { showSummary = true }
                    .buttonStyle(.glass)
            }
            .padding()
            .background(.regularMaterial)
        }
    }

    // MARK: - Summary Sheet

    private var summarySheet: some View {
        NavigationStack {
            List {
                ForEach(receipts) { receipt in
                    let payerName = participants.first(where: { $0.userId == receipt.payerUserId })?.displayName ?? "Unknown"
                    let receiptTotals = BillService.computeReceiptTotals(
                        receipts: [receipt],
                        items: receiptItems,
                        claims: claims,
                        participants: participants
                    )[receipt.id] ?? []

                    Section("At \(receipt.placeName) · paid by \(payerName)") {
                        ForEach(receiptTotals.filter { $0.total > 0.005 }, id: \.userId) { t in
                            HStack {
                                Text(t.displayName)
                                    .foregroundStyle(t.userId == myUserId ? .primary : .secondary)
                                Spacer()
                                Text(t.total, format: .currency(code: "USD"))
                                    .bold()
                                    .foregroundStyle(t.userId == myUserId ? Color.coral : .primary)
                            }
                        }
                        if receiptTotals.allSatisfy({ $0.total <= 0.005 }) {
                            Text("No items claimed yet")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    let allTotals = crossReceiptTotals
                    ForEach(allTotals.filter { $0.total > 0.005 }, id: \.userId) { t in
                        HStack {
                            Text(t.displayName)
                            Spacer()
                            Text(t.total, format: .currency(code: "USD"))
                                .bold()
                                .foregroundStyle(t.userId == myUserId ? Color.coral : .primary)
                        }
                    }
                } header: {
                    Text("Total across \(receipts.count) place\(receipts.count == 1 ? "" : "s")")
                }
            }
            .navigationTitle("Who owes what")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showSummary = false }
                }
            }
        }
    }

    // MARK: - Computed Totals

    private var crossReceiptTotals: [BillService.PersonTotal] {
        var combined: [UUID: BillService.PersonTotal] = [:]
        let allReceiptTotals = BillService.computeReceiptTotals(
            receipts: receipts, items: receiptItems, claims: claims, participants: participants
        )
        for (_, totals) in allReceiptTotals {
            for t in totals {
                if combined[t.userId] == nil {
                    combined[t.userId] = t
                } else {
                    combined[t.userId]?.total += t.total
                    combined[t.userId]?.subtotal += t.subtotal
                }
            }
        }
        return combined.values.sorted { $0.total > $1.total }
    }

    private var crossReceiptMyTotal: Double {
        guard let me = myUserId else { return 0 }
        return crossReceiptTotals.first(where: { $0.userId == me })?.total ?? 0
    }

    private func myOwedForReceipt(_ receipt: Receipt) -> Double {
        guard let me = myUserId else { return 0 }
        let totals = BillService.computeReceiptTotals(
            receipts: [receipt], items: receiptItems, claims: claims, participants: participants
        )
        return totals[receipt.id]?.first(where: { $0.userId == me })?.total ?? 0
    }

    // MARK: - Data

    private func load() async {
        do {
            receipts = try await BillService.shared.fetchReceipts(meetupId: meetup.id)
            for receipt in receipts {
                receiptItems[receipt.id] = try await BillService.shared.fetchReceiptItems(receiptId: receipt.id)
            }
            claims = try await BillService.shared.fetchAllReceiptClaims(receiptIds: receipts.map { $0.id })
            if let first = receipts.first { expandedReceiptId = first.id }
            if !receipts.isEmpty { startRealtime() }
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
        hasLoaded = true
    }

    private func reloadClaims() async {
        do {
            claims = try await BillService.shared.fetchAllReceiptClaims(receiptIds: receipts.map { $0.id })
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func toggleClaim(item: BillItem, isMine: Bool) async {
        do {
            if isMine {
                try await BillService.shared.unclaimItem(billItemId: item.id)
            } else {
                try await BillService.shared.claimItem(billItemId: item.id)
            }
            await reloadClaims()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func startRealtime() {
        guard realtimeTask == nil else { return }
        realtimeTask = Task {
            let channel = SupabaseManager.shared.client.realtimeV2.channel("receipts-\(meetup.id)")
            let changes = channel.postgresChange(AnyAction.self, schema: "public", table: "bill_item_claims")
            do {
                try await channel.subscribeWithError()
            } catch {
                return
            }
            for await _ in changes {
                guard !Task.isCancelled else { break }
                await reloadClaims()
            }
            await SupabaseManager.shared.client.realtimeV2.removeChannel(channel)
        }
    }
}

// MARK: - Add Receipt Sheet

struct AddReceiptView: View {
    let meetup: Meetup
    let participants: [MeetupParticipant]
    let onSaved: (Receipt, [BillItem]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthViewModel.self) private var auth

    @State private var placeName: String
    @State private var selectedPayerId: UUID?

    init(meetup: Meetup, participants: [MeetupParticipant], onSaved: @escaping (Receipt, [BillItem]) -> Void) {
        self.meetup = meetup
        self.participants = participants
        self.onSaved = onSaved
        _placeName = State(initialValue: meetup.destinationName)
    }
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var receiptImage: UIImage?
    @State private var showCamera = false
    @State private var parsedReceipt: ParsedReceipt?
    @State private var editableItems: [BillItem] = []
    @FocusState private var focusedItemId: UUID?
    @State private var step: AddStep = .details
    @State private var isProcessing = false
    @State private var error: String?

    enum AddStep { case details, items }

    private var canProceedToItems: Bool {
        !placeName.trimmingCharacters(in: .whitespaces).isEmpty && selectedPayerId != nil
    }

    private var canSave: Bool {
        !editableItems.isEmpty &&
        editableItems.allSatisfy { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty && $0.price > 0 }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .details: detailsView
                case .items:   itemsView
                }
            }
            .navigationTitle(step == .details ? "New Receipt" : "Edit Items")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(step == .details ? "Cancel" : "Back") {
                        if step == .items { step = .details } else { dismiss() }
                    }
                }
            }
            .alert("Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
    }

    // MARK: - Step 1: Details

    private var detailsView: some View {
        VStack(spacing: 0) {
            Form {
                Section("Place") {
                    TextField("e.g. Sadelle's, Café Boulud", text: $placeName)
                }

                Section("Paid by") {
                    Picker("Payer", selection: $selectedPayerId) {
                        Text("Select payer").tag(Optional<UUID>.none)
                        ForEach(participants, id: \.userId) { p in
                            Text(p.displayName ?? "Unknown").tag(Optional(p.userId))
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                Section {
                    if let img = receiptImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    HStack(spacing: 12) {
                        Button { showCamera = true } label: {
                            Label("Camera", systemImage: "camera")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)

                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            Label("Photos", systemImage: "photo.on.rectangle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                        .onChange(of: selectedPhotoItem) { _, item in
                            guard let item else { return }
                            Task {
                                if let data = try? await item.loadTransferable(type: Data.self),
                                   let img = UIImage(data: data) {
                                    receiptImage = img
                                    await parseImage(img)
                                }
                                selectedPhotoItem = nil
                            }
                        }
                    }
                } header: {
                    Text("Receipt photo (optional)")
                }
            }

            Button {
                step = .items
            } label: {
                Label("Next: Add Items", systemImage: "chevron.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .disabled(!canProceedToItems || isProcessing)
            .padding()
        }
        .sheet(isPresented: $showCamera) {
            CameraPickerView { image in
                receiptImage = image
                Task { await parseImage(image) }
            }
            .ignoresSafeArea()
        }
        .overlay {
            if isProcessing {
                ProgressView("Parsing receipt…")
                    .padding()
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Step 2: Items

    private var itemsView: some View {
        VStack(spacing: 0) {
            List {
                Section("Items (tap to edit)") {
                    ForEach(editableItems.indices, id: \.self) { idx in
                        HStack {
                            TextField("Item name", text: $editableItems[idx].name)
                                .focused($focusedItemId, equals: editableItems[idx].id)
                            Spacer()
                            TextField("0.00", value: $editableItems[idx].price, format: .currency(code: "USD"))
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.decimalPad)
                                .frame(width: 80)
                        }
                        .foregroundStyle(
                            editableItems[idx].name.trimmingCharacters(in: .whitespaces).isEmpty || editableItems[idx].price <= 0
                                ? AnyShapeStyle(Color.coral) : AnyShapeStyle(Color.primary)
                        )
                    }
                    .onDelete { editableItems.remove(atOffsets: $0) }
                    Button {
                        let newItem = BillItem(id: UUID(), name: "", price: 0, position: editableItems.count)
                        editableItems.append(newItem)
                        focusedItemId = newItem.id
                    } label: {
                        Label("Add Item", systemImage: "plus")
                    }
                }

                if let parsed = parsedReceipt {
                    Section("Totals") {
                        LabeledContent("Subtotal", value: parsed.subtotal, format: .currency(code: "USD"))
                        LabeledContent("Tax",      value: parsed.tax,      format: .currency(code: "USD"))
                        LabeledContent("Tip",      value: parsed.tip,      format: .currency(code: "USD"))
                        LabeledContent("Total",    value: parsed.total,    format: .currency(code: "USD"))
                    }
                }
            }

            VStack(spacing: 4) {
                Button {
                    Task { await saveReceipt() }
                } label: {
                    Label("Save Receipt", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .disabled(isProcessing || !canSave)
                .padding([.horizontal, .top])

                if !canSave && !isProcessing && !editableItems.isEmpty {
                    Text("Fix items with missing names or $0 prices")
                        .font(.caption)
                        .foregroundStyle(Color.coral)
                        .padding(.bottom, 8)
                }
            }
        }
        .overlay {
            if isProcessing {
                ProgressView("Saving…")
                    .padding()
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Actions

    private func parseImage(_ image: UIImage) async {
        isProcessing = true
        let parsed = await ReceiptParser.parse(image: image)
        parsedReceipt = parsed
        editableItems = parsed.items.enumerated().map { idx, i in
            BillItem(id: UUID(), name: i.name, price: i.price, position: idx)
        }
        isProcessing = false
    }

    private func saveReceipt() async {
        guard let payerId = selectedPayerId else { return }
        isProcessing = true
        do {
            var receipt = try await BillService.shared.createReceipt(
                meetupId: meetup.id,
                placeName: placeName.trimmingCharacters(in: .whitespaces),
                payerUserId: payerId
            )

            if let image = receiptImage, let data = image.jpegData(compressionQuality: 0.8) {
                if let photoUrl = try? await BillService.shared.uploadReceiptPhoto(receiptId: receipt.id, imageData: data) {
                    try await BillService.shared.updateReceiptPhotoUrl(receipt.id, photoUrl: photoUrl)
                    receipt = Receipt(
                        id: receipt.id, meetupId: receipt.meetupId, placeName: receipt.placeName,
                        payerUserId: receipt.payerUserId, totalAmount: receipt.totalAmount,
                        tax: receipt.tax, tip: receipt.tip, surcharge: receipt.surcharge,
                        photoUrl: photoUrl, createdAt: receipt.createdAt
                    )
                }
            }

            let savedItems = try await BillService.shared.insertReceiptItems(
                receiptId: receipt.id,
                parsedItems: editableItems.map { (name: $0.name, price: $0.price) }
            )

            let tax = parsedReceipt?.tax ?? 0
            let tip = parsedReceipt?.tip ?? 0
            let surcharge = parsedReceipt?.surcharge ?? 0
            let total = savedItems.reduce(0.0) { $0 + $1.price } + tax + tip + surcharge
            try await BillService.shared.updateReceiptFinancials(receipt.id, total: total, tax: tax, tip: tip, surcharge: surcharge)

            let finalReceipt = Receipt(
                id: receipt.id, meetupId: receipt.meetupId, placeName: receipt.placeName,
                payerUserId: receipt.payerUserId, totalAmount: total,
                tax: tax, tip: tip, surcharge: surcharge,
                photoUrl: receipt.photoUrl, createdAt: receipt.createdAt
            )

            onSaved(finalReceipt, savedItems)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isProcessing = false
    }
}

// MARK: - UIKit wrappers

struct CameraPickerView: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let vc = UIImagePickerController()
        vc.sourceType = .camera
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (UIImage) -> Void
        init(onImage: @escaping (UIImage) -> Void) { self.onImage = onImage }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { onImage(img) }
            picker.dismiss(animated: true)
        }
    }
}
