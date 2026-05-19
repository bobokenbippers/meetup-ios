import SwiftUI
import UniformTypeIdentifiers
import Supabase
import Auth

struct BillView: View {
    let meetup: Meetup
    let participants: [MeetupParticipant]
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthViewModel.self) private var auth

    @State private var bill: Bill?
    @State private var items: [BillItem] = []
    @State private var claims: [BillItemClaim] = []
    @State private var hasLoaded = false
    @State private var isProcessing = false
    @State private var error: String?
    @State private var showSummary = false
    @State private var realtimeTask: Task<Void, Never>?

    @State private var showImagePicker = false
    @State private var showDocPicker = false
    @State private var parsedReceipt: ParsedReceipt?
    @State private var editableItems: [BillItem] = []

    private var myUserId: UUID? { auth.session?.user.id }

    var body: some View {
        NavigationStack {
            Group {
                if !hasLoaded {
                    ProgressView()
                } else if let bill {
                    checklistView(bill: bill)
                } else if parsedReceipt != nil {
                    previewView
                } else {
                    uploadView
                }
            }
            .navigationTitle("Split Bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .alert("Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
            .sheet(isPresented: $showSummary) {
                summarySheet
            }
        }
        .task { await load() }
        .onDisappear { realtimeTask?.cancel() }
    }

    // MARK: - Upload view

    private var uploadView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "receipt")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("Photograph or upload the receipt to split the bill.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            HStack(spacing: 16) {
                Button {
                    showImagePicker = true
                } label: {
                    Label("Take Photo", systemImage: "camera")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                Button {
                    showDocPicker = true
                } label: {
                    Label("Choose PDF", systemImage: "doc.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }
            .padding(.horizontal)
            Spacer()
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePickerView { image in
                Task { await handleImage(image) }
            }
        }
        .sheet(isPresented: $showDocPicker) {
            DocumentPickerView { url in
                Task { await handlePDF(url) }
            }
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

    // MARK: - Preview / edit parsed items

    private var previewView: some View {
        VStack(spacing: 0) {
            List {
                Section("Items (tap to edit)") {
                    ForEach(editableItems.indices, id: \.self) { idx in
                        HStack {
                            TextField("Item name", text: $editableItems[idx].name)
                            Spacer()
                            TextField("0.00", value: $editableItems[idx].price, format: .currency(code: "USD"))
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.decimalPad)
                                .frame(width: 80)
                        }
                    }
                    .onDelete { editableItems.remove(atOffsets: $0) }
                }
                if let parsed = parsedReceipt {
                    Section("Summary") {
                        LabeledContent("Subtotal", value: parsed.subtotal, format: .currency(code: "USD"))
                        LabeledContent("Tax", value: parsed.tax, format: .currency(code: "USD"))
                        LabeledContent("Tip", value: parsed.tip, format: .currency(code: "USD"))
                        LabeledContent("Total", value: parsed.total, format: .currency(code: "USD"))
                    }
                }
            }
            Button {
                Task { await shareBill() }
            } label: {
                Label("Share with group", systemImage: "person.2.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .disabled(isProcessing || editableItems.isEmpty)
            .padding()
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

    // MARK: - Checklist view

    private func checklistView(bill: Bill) -> some View {
        let currentItems = items
        let currentClaims = claims
        let currentParticipants = participants
        let currentMyUserId = myUserId
        return VStack(spacing: 0) {
            List {
                Section {
                    ForEach(currentItems) { item in
                        let itemClaims = currentClaims.filter { $0.billItemId == item.id }
                        let isMine = itemClaims.contains { $0.userId == currentMyUserId }
                        let claimNames = itemClaims.compactMap { c in
                            currentParticipants.first(where: { $0.userId == c.userId })?.displayName
                        }
                        HStack {
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
                                .foregroundStyle(itemClaims.isEmpty ? .orange : .primary)
                            Image(systemName: isMine ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isMine ? Color.accentColor : Color.secondary)
                                .onTapGesture { Task { await toggleClaim(item: item, isMine: isMine) } }
                        }
                    }
                } header: {
                    Text("Items")
                } footer: {
                    if currentItems.contains(where: { i in !currentClaims.contains(where: { $0.billItemId == i.id }) }) {
                        Text("Unclaimed items shown in orange").foregroundStyle(.orange)
                    }
                }
            }
            VStack(spacing: 12) {
                Text("Your total: \(myTotal(bill: bill), format: .currency(code: "USD"))")
                    .font(.headline)
                Button("See totals") { showSummary = true }
                    .buttonStyle(.glass)
            }
            .padding()
            .background(.regularMaterial)
        }
    }

    // MARK: - Summary sheet

    private var summarySheet: some View {
        NavigationStack {
            let totals = BillService.shared.computeTotals(
                bill: bill!,
                items: items,
                claims: claims,
                participants: participants
            )
            List {
                ForEach(totals, id: \.userId) { t in
                    HStack {
                        Text(t.displayName)
                        Spacer()
                        Text(t.total, format: .currency(code: "USD")).bold()
                    }
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

    // MARK: - Helpers

    private func myTotal(bill: Bill) -> Double {
        let myId = myUserId
        let myClaims = claims.filter { $0.userId == myId }
        var sub = 0.0
        for claim in myClaims {
            guard let item = items.first(where: { $0.id == claim.billItemId }) else { continue }
            let splitCount = Double(claims.filter { $0.billItemId == item.id }.count)
            sub += item.price / splitCount
        }
        let billSub = bill.subtotal > 0 ? bill.subtotal : 1
        return sub + (sub / billSub) * bill.tax + (sub / billSub) * bill.tip
    }

    private func toggleClaim(item: BillItem, isMine: Bool) async {
        do {
            if isMine {
                try await BillService.shared.unclaimItem(billItemId: item.id)
            } else {
                try await BillService.shared.claimItem(billItemId: item.id)
            }
            await loadClaims()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func handleImage(_ image: UIImage) async {
        isProcessing = true
        let parsed = await ReceiptParser.parse(image: image)
        parsedReceipt = parsed
        editableItems = parsed.items.enumerated().map { idx, i in
            BillItem(id: UUID(), billId: UUID(), name: i.name, price: i.price, position: idx)
        }
        isProcessing = false
    }

    private func handlePDF(_ url: URL) async {
        isProcessing = true
        let parsed = await ReceiptParser.parse(pdfURL: url)
        parsedReceipt = parsed
        editableItems = parsed.items.enumerated().map { idx, i in
            BillItem(id: UUID(), billId: UUID(), name: i.name, price: i.price, position: idx)
        }
        isProcessing = false
    }

    private func shareBill() async {
        guard let parsed = parsedReceipt else { return }
        isProcessing = true
        var adjusted = parsed
        adjusted.items = editableItems.map { (name: $0.name, price: $0.price) }
        adjusted.subtotal = adjusted.items.reduce(0) { $0 + $1.price }
        do {
            let (newBill, newItems) = try await BillService.shared.createBill(meetupId: meetup.id, receipt: adjusted)
            bill = newBill
            items = newItems
            claims = []
            parsedReceipt = nil
            startRealtime()
        } catch {
            self.error = error.localizedDescription
        }
        isProcessing = false
    }

    private func load() async {
        do {
            bill = try await BillService.shared.fetchBill(meetupId: meetup.id)
            if let b = bill {
                items = try await BillService.shared.fetchItems(billId: b.id)
                claims = try await BillService.shared.fetchClaims(billId: b.id)
                startRealtime()
            }
        } catch {
            self.error = error.localizedDescription
        }
        hasLoaded = true
    }

    private func loadClaims() async {
        guard let b = bill else { return }
        do { claims = try await BillService.shared.fetchClaims(billId: b.id) }
        catch { self.error = error.localizedDescription }
    }

    private func startRealtime() {
        guard let b = bill else { return }
        realtimeTask?.cancel()
        realtimeTask = Task {
            let channel = SupabaseManager.shared.client.realtimeV2.channel("bill-\(b.id)")
            let changes = channel.postgresChange(AnyAction.self, schema: "public", table: "bill_item_claims")
            do { try await channel.subscribeWithError() } catch { return }
            for await _ in changes {
                guard !Task.isCancelled else { break }
                await loadClaims()
            }
            await SupabaseManager.shared.client.realtimeV2.removeChannel(channel)
        }
    }
}

// MARK: - UIKit wrappers

struct ImagePickerView: UIViewControllerRepresentable {
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

struct DocumentPickerView: UIViewControllerRepresentable {
    let onURL: (URL) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onURL: onURL) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let vc = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf])
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onURL: (URL) -> Void
        init(onURL: @escaping (URL) -> Void) { self.onURL = onURL }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { onURL(url) }
        }
    }
}
