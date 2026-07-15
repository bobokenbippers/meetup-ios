import SwiftUI

struct PrivacyAuditLogView: View {
    @State private var events: [PrivacyAuditLog] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if isLoading && events.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                            .tint(Color.coral)
                        Spacer()
                    }
                    .listRowBackground(Color.appSurface)
                }
            } else if events.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Privacy Events",
                        systemImage: "lock.shield",
                        description: Text("Location sharing events will appear here.")
                    )
                    .listRowBackground(Color.appSurface)
                }
            } else {
                Section {
                    ForEach(events) { event in
                        PrivacyAuditLogRow(event: event)
                            .listRowBackground(Color.appSurface)
                    }
                } footer: {
                    Text("This log shows recent sensitive sharing changes for your account.")
                        .font(.caption2)
                        .foregroundStyle(DS.Color.textSecondary)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Color.statusLate)
                        .listRowBackground(Color.appSurface)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
        .navigationTitle("Privacy Log")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await load()
        }
        .task {
            await load()
        }
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            events = try await PrivacyAuditLogService.shared.fetchRecent()
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "Couldn't load privacy events."
        }
    }
}

private struct PrivacyAuditLogRow: View {
    let event: PrivacyAuditLog

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: event.eventType.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.coral)
                .frame(width: 28, height: 28)
                .background(Color.coral.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(event.eventType.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.Color.textPrimary)

                if let destinationName = event.metadata["destination_name"], !destinationName.isEmpty {
                    Text(destinationName)
                        .font(.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                }

                Text(event.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(DS.Color.textSecondary)
            }
        }
        .padding(.vertical, 4)
    }
}
