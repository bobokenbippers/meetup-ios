import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import Supabase
import Auth
import UIKit
import VisionKit

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
    @State private var receiptsRealtimeTask: Task<Void, Never>?
    @State private var itemsRealtimeTask: Task<Void, Never>?
    @State private var claimsRealtimeTask: Task<Void, Never>?

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
                    if let index = receipts.firstIndex(where: { $0.id == receipt.id }) {
                        receipts[index] = receipt
                    } else {
                        receipts.append(receipt)
                    }
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
        .onDisappear { stopRealtime() }
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

    @ViewBuilder private var receiptListView: some View {
        let snapshot = billSnapshot
        ZStack(alignment: .bottom) {
            List {
                ForEach(receipts) { receipt in
                    receiptSection(receipt: receipt, snapshot: snapshot)
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

            bottomBar(snapshot: snapshot)
        }
    }

    private func receiptSection(receipt: Receipt, snapshot: BillSnapshot) -> some View {
        let payerName = snapshot.participantNames[receipt.payerUserId] ?? "Unknown"
        let isExpanded = expandedReceiptId == receipt.id
        let items = receiptItems[receipt.id] ?? []

        return Section {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedReceiptId = isExpanded ? nil : receipt.id
                }
            } label: {
                HStack {
                    receiptThumbnail(receipt)
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
                    ForEach(disambiguatedItems(items), id: \.item.id) { entry in
                        itemRow(item: entry.item, displayName: entry.label, snapshot: snapshot)
                    }
                }
                let myOwed = myOwedForReceipt(receipt, snapshot: snapshot)
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

    @ViewBuilder
    private func receiptThumbnail(_ receipt: Receipt) -> some View {
        if let photoUrl = receipt.photoUrl, let url = URL(string: photoUrl) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                case .empty:
                    ProgressView()
                        .scaleEffect(0.7)
                @unknown default:
                    Color.clear
                }
            }
            .frame(width: 44, height: 56)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Image(systemName: "receipt")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 56)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    /// Build display labels that disambiguate duplicate items. When a receipt has
    /// multiple identical line items (e.g. two "Old Fashioned" rows from a
    /// "(2 @18.00)" annotation), each gets a "· N of M" suffix so two people can
    /// each claim their own without guessing which row is which. Unique items are
    /// left untouched. Order is preserved so the numbering is stable.
    private func disambiguatedItems(_ items: [BillItem]) -> [(item: BillItem, label: String)] {
        let counts = Dictionary(grouping: items, by: { $0.name }).mapValues(\.count)
        var seen: [String: Int] = [:]
        return items.map { item in
            let total = counts[item.name] ?? 1
            guard total > 1 else { return (item, item.name) }
            let n = (seen[item.name] ?? 0) + 1
            seen[item.name] = n
            return (item, "\(item.name) · \(n) of \(total)")
        }
    }

    private func itemRow(item: BillItem, displayName: String, snapshot: BillSnapshot) -> some View {
        let itemClaims = snapshot.claimsByItem[item.id] ?? []
        let isMine = itemClaims.contains { $0.userId == myUserId }
        let claimNames = itemClaims.compactMap { snapshot.participantNames[$0.userId] }
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
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
            .accessibilityLabel(isMine ? "Unclaim \(displayName)" : "Claim \(displayName)")
        }
    }

    private func bottomBar(snapshot: BillSnapshot) -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total you owe")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(crossReceiptMyTotal(snapshot: snapshot), format: .currency(code: "USD"))
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

    @ViewBuilder private var summarySheet: some View {
        let snapshot = billSnapshot
        NavigationStack {
            List {
                ForEach(receipts) { receipt in
                    let payerName = snapshot.participantNames[receipt.payerUserId] ?? "Unknown"
                    let receiptTotals = snapshot.receiptTotalsById[receipt.id] ?? []

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
                    let allTotals = snapshot.crossReceiptTotals
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

    private struct BillSnapshot {
        let participantNames: [UUID: String]
        let claimsByItem: [UUID: [BillItemClaim]]
        let receiptTotalsById: [UUID: [BillService.PersonTotal]]
        let crossReceiptTotals: [BillService.PersonTotal]
    }

    private var billSnapshot: BillSnapshot {
        let participantNames = participants.reduce(into: [UUID: String]()) { names, participant in
            names[participant.userId] = participant.displayName ?? "Unknown"
        }
        let claimsByItem = Dictionary(grouping: claims, by: \.billItemId)
        let receiptTotalsById = BillService.computeReceiptTotals(
            receipts: receipts, items: receiptItems, claims: claims, participants: participants
        )
        var combined: [UUID: BillService.PersonTotal] = [:]

        for (_, totals) in receiptTotalsById {
            for t in totals {
                if combined[t.userId] == nil {
                    combined[t.userId] = t
                } else {
                    combined[t.userId]?.total += t.total
                    combined[t.userId]?.subtotal += t.subtotal
                }
            }
        }

        return BillSnapshot(
            participantNames: participantNames,
            claimsByItem: claimsByItem,
            receiptTotalsById: receiptTotalsById,
            crossReceiptTotals: combined.values.sorted { $0.total > $1.total }
        )
    }

    private func crossReceiptMyTotal(snapshot: BillSnapshot) -> Double {
        guard let me = myUserId else { return 0 }
        return snapshot.crossReceiptTotals.first(where: { $0.userId == me })?.total ?? 0
    }

    private func myOwedForReceipt(_ receipt: Receipt, snapshot: BillSnapshot) -> Double {
        guard let me = myUserId else { return 0 }
        return snapshot.receiptTotalsById[receipt.id]?.first(where: { $0.userId == me })?.total ?? 0
    }

    // MARK: - Data

    private func load() async {
        do {
            try await reloadBillData(preserveExpandedReceipt: false)
            if let first = receipts.first { expandedReceiptId = first.id }
            startRealtime()
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
        hasLoaded = true
    }

    private func reloadBillData(preserveExpandedReceipt: Bool = true) async throws {
        let previousExpandedReceiptId = expandedReceiptId
        let freshReceipts = try await BillService.shared.fetchReceipts(meetupId: meetup.id)
        var freshItems: [UUID: [BillItem]] = [:]
        for receipt in freshReceipts {
            freshItems[receipt.id] = try await BillService.shared.fetchReceiptItems(receiptId: receipt.id)
        }
        let freshClaims = try await BillService.shared.fetchAllReceiptClaims(receiptIds: freshReceipts.map { $0.id })

        receipts = freshReceipts
        receiptItems = freshItems
        claims = freshClaims

        guard preserveExpandedReceipt else { return }
        if let previousExpandedReceiptId,
           freshReceipts.contains(where: { $0.id == previousExpandedReceiptId }) {
            expandedReceiptId = previousExpandedReceiptId
        } else {
            expandedReceiptId = freshReceipts.first?.id
        }
    }

    private func reloadBillDataForRealtime() async {
        do {
            try await reloadBillData()
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func reloadClaims() async {
        do {
            claims = try await BillService.shared.fetchAllReceiptClaims(receiptIds: receipts.map { $0.id })
        } catch is CancellationError {
            return
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
        guard receiptsRealtimeTask == nil,
              itemsRealtimeTask == nil,
              claimsRealtimeTask == nil
        else { return }

        receiptsRealtimeTask = Task {
            let channel = SupabaseManager.shared.client.realtimeV2.channel("receipts-\(meetup.id)")
            let receiptChanges = channel.postgresChange(AnyAction.self, schema: "public", table: "receipts")
            do {
                try await channel.subscribeWithError()
            } catch {
                return
            }
            for await _ in receiptChanges {
                guard !Task.isCancelled else { break }
                await reloadBillDataForRealtime()
            }
            await SupabaseManager.shared.client.realtimeV2.removeChannel(channel)
        }

        itemsRealtimeTask = Task {
            let channel = SupabaseManager.shared.client.realtimeV2.channel("receipt-items-\(meetup.id)")
            let itemChanges = channel.postgresChange(AnyAction.self, schema: "public", table: "bill_items")
            do {
                try await channel.subscribeWithError()
            } catch {
                return
            }
            for await _ in itemChanges {
                guard !Task.isCancelled else { break }
                await reloadBillDataForRealtime()
            }
            await SupabaseManager.shared.client.realtimeV2.removeChannel(channel)
        }

        claimsRealtimeTask = Task {
            let channel = SupabaseManager.shared.client.realtimeV2.channel("receipt-claims-\(meetup.id)")
            let claimChanges = channel.postgresChange(AnyAction.self, schema: "public", table: "bill_item_claims")
            do {
                try await channel.subscribeWithError()
            } catch {
                return
            }
            for await _ in claimChanges {
                guard !Task.isCancelled else { break }
                await reloadClaims()
            }
            await SupabaseManager.shared.client.realtimeV2.removeChannel(channel)
        }
    }

    private func stopRealtime() {
        receiptsRealtimeTask?.cancel()
        receiptsRealtimeTask = nil
        itemsRealtimeTask?.cancel()
        itemsRealtimeTask = nil
        claimsRealtimeTask?.cancel()
        claimsRealtimeTask = nil
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
    @State private var showScanner = false
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
                    HStack(spacing: 8) {
                        Button { startCapture() } label: {
                            Label("Scan", systemImage: "doc.viewfinder")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)

                        Button { startCameraCapture() } label: {
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
        .sheet(isPresented: $showScanner) {
            DocumentScannerView { image in
                receiptImage = image
                Task { await parseImage(image) }
            } onCancel: {}
            .ignoresSafeArea()
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

    private func startCapture() {
        // Prefer the system document scanner: it edge-detects, deskews,
        // crops to the receipt, and reduces glare — producing a far cleaner
        // image for OCR than a raw camera photo. Fall back to a plain camera
        // capture only where scanning is unsupported (e.g. older devices).
        if VNDocumentCameraViewController.isSupported {
            showScanner = true
        } else if UIImagePickerController.isSourceTypeAvailable(.camera) {
            showCamera = true
        } else {
            error = "Camera isn't available on this device. Use Photos instead."
        }
    }

    private func startCameraCapture() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            error = "Camera isn't available on this device. Use Photos instead."
            return
        }
        showCamera = true
    }

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

/// System document scanner (VisionKit). Performs live edge detection,
/// perspective correction, auto-cropping, and glare/shadow reduction, then
/// hands back the enhanced scan of the first page — a much stronger OCR input
/// than a raw camera photo.
struct DocumentScannerView: UIViewControllerRepresentable {
    let onScan: (UIImage) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan, onCancel: onCancel) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onScan: (UIImage) -> Void
        let onCancel: () -> Void
        init(onScan: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onScan = onScan
            self.onCancel = onCancel
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            if scan.pageCount > 0 {
                onScan(scan.imageOfPage(at: 0))
            } else {
                onCancel()
            }
            controller.dismiss(animated: true)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onCancel()
            controller.dismiss(animated: true)
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFailWithError error: Error) {
            onCancel()
            controller.dismiss(animated: true)
        }
    }
}

struct CameraPickerView: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage) }
    func makeUIViewController(context: Context) -> UIViewController {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            let vc = UIViewController()
            vc.view.backgroundColor = .systemBackground
            let label = UILabel()
            label.text = "Camera unavailable"
            label.textAlignment = .center
            label.textColor = .secondaryLabel
            label.translatesAutoresizingMaskIntoConstraints = false
            vc.view.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: vc.view.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: vc.view.centerYAnchor)
            ])
            return vc
        }
        let vc = UIImagePickerController()
        vc.sourceType = .camera
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (UIImage) -> Void
        init(onImage: @escaping (UIImage) -> Void) { self.onImage = onImage }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { onImage(img) }
            picker.dismiss(animated: true)
        }
    }
}
