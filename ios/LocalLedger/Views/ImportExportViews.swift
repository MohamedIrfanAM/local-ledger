import SwiftUI
import UniformTypeIdentifiers
import LedgerCore

struct ImportAlertView: View {
    @Environment(LedgerStore.self) private var store
    @State private var sender = ""
    @State private var message = ""
    @State private var received = Date.now
    @State private var result: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                if store.isPreview { PreviewBanner() }
                Section {
                    TextField("Sender header, e.g. AX-ICICIT-S", text: $sender).textInputAutocapitalization(.characters).autocorrectionDisabled()
                    DatePicker("Originally received", selection: $received, in: ...Date.now)
                    TextField("Paste your bank alert here", text: $message, axis: .vertical).lineLimit(6...12).autocorrectionDisabled().textInputAutocapitalization(.never)
                    PasteButton(payloadType: String.self) { values in if let text = values.first { message = text } }
                } header: { Text("Bank alert") } footer: { Text("Use the original sender and received time. Parsing happens on this device; the message body is never saved.") }
                if let bank = store.registry?.bank(for: sender) { Label(bank.name, systemImage: "building.columns").foregroundStyle(LedgerTheme.accent) }
                if let result { Section("Import result") { Text(result) } }
                Button("Import alert", systemImage: "tray.and.arrow.down") {
                    let body = message, header = sender, date = received
                    Task { result = await store.importAlert(sender: header, body: body, receivedAt: date); if result != nil { message = "" } }
                }.disabled(!store.canEdit || sender.isEmpty || message.isEmpty)
                NavigationLink("Set up Shortcuts automation") { IntegrationsGuide() }
            }.navigationTitle("Import bank alert").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct CSVImportView: View {
    @Environment(LedgerStore.self) private var store
    @State private var choosing = false
    @State private var csv: String?
    @State private var filename = ""
    @State private var rowCount = 0
    @State private var adjustsBalance = false
    @State private var result: String?
    var body: some View {
        Form {
            Section {
                Text("Bring your Android ledger with you.").font(.headline)
                Text("Choose a detailed Local Ledger CSV report. Add its banks in Accounts first, using each account’s current balance.").foregroundStyle(.secondary)
                Button("Choose CSV file", systemImage: "doc") { choosing = true }
            }
            if csv != nil {
                Section("Ready to import") {
                    LabeledContent("File", value: filename)
                    LabeledContent("Rows", value: String(rowCount))
                    Toggle("Adjust account balances", isOn: $adjustsBalance)
                    Text("Leave off when historical entries are already included in your opening balances. Every row is validated before anything is saved.").font(.caption).foregroundStyle(.secondary)
                    Button("Import transactions", systemImage: "tray.and.arrow.down") {
                        guard let contents = csv else { return }
                        let before = store.state.transactions.count, affects = adjustsBalance
                        Task {
                            if await store.commit({ try LedgerCSV.importReport(contents, into: &$0, affectsBalances: affects) }) {
                                result = "Imported \(store.state.transactions.count - before) transactions. Duplicate rows were skipped."; csv = nil
                            }
                        }
                    }.disabled(!store.canEdit)
                }
            }
            if let result { Section("Result") { Text(result) } }
        }.navigationTitle("Import CSV")
            .fileImporter(isPresented: $choosing, allowedContentTypes: [.commaSeparatedText, .plainText]) { selection in
                Task {
                    do {
                        let url = try selection.get()
                        let staged = try await Task.detached(priority: .userInitiated) {
                            let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                            guard size <= 20_000_000 else { throw CSVError.malformed }
                            let contents = try String(contentsOf: url, encoding: .utf8)
                            return (contents, max(0, try LedgerCSV.rows(contents).count - 1))
                        }.value
                        csv = staged.0; rowCount = staged.1; filename = url.lastPathComponent; result = nil
                    } catch { store.error = error.localizedDescription }
                }
            }
    }
}

struct LedgerDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText, .pdf] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
struct ReportsView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var embedded = false
    @State private var document: LedgerDocument?
    @State private var contentType = UTType.commaSeparatedText
    @State private var exporting = false
    @State private var preparing = false
    @State private var result: String?
    var body: some View {
        Group { if embedded { form } else { NavigationStack { form.toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } } } } }
            .fileExporter(isPresented: $exporting, document: document, contentType: contentType,
                          defaultFilename: "Local-Ledger-\(Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash)))") { outcome in
                switch outcome { case .success: result = "Report saved."; case .failure(let error): store.error = error.localizedDescription }
                document = nil
            }
    }
    private var form: some View {
        Form {
            Section {
                LabeledContent("Transactions", value: String(store.summary.transactions.count))
                Text("Reports use the current Activity filters and include exact values, merchant names, tags, and notes.").font(.subheadline).foregroundStyle(.secondary)
            }
            Section {
                Button("Export detailed CSV", systemImage: "tablecells") { prepare(pdf: false) }
                Button("Export PDF report", systemImage: "doc.richtext") { prepare(pdf: true) }
            }.disabled(!store.canExport || preparing)
            if preparing { ProgressView("Preparing on your device…") }
            if let result { Text(result) }
        }.navigationTitle("Export report").navigationBarTitleDisplayMode(.inline)
    }
    private func prepare(pdf: Bool) {
        guard store.canExport else { return }
        preparing = true
        let snapshot = store.state, filter = store.filter
        Task {
            let data = await Task.detached(priority: .userInitiated) {
                let transactions = snapshot.filtered(filter)
                return pdf ? PDFReport.make(state: snapshot, transactions: transactions) : Data(LedgerCSV.export(state: snapshot, transactions: transactions).utf8)
            }.value
            preparing = false
            guard store.canExport else { return }
            document = LedgerDocument(data: data); contentType = pdf ? .pdf : .commaSeparatedText; exporting = true
        }
    }
}
