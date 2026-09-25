import AppIntents
import LedgerCore

struct AddTransactionIntent: AppIntent {
    static let title: LocalizedStringResource = "Add a transaction"
    static let description = IntentDescription("Open the native entry sheet in Local Ledger.")
    static let openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        let store = LedgerStore.shared; await store.load()
        guard store.loaded, await store.authenticate() else { throw LedgerError.readOnly }
        store.route = .add
        return .result()
    }
}
struct ImportBankAlertIntent: AppIntent {
    static let title: LocalizedStringResource = "Import bank alert"
    static let description = IntentDescription("Parse an explicitly provided Indian bank alert on this device. Original sender and received time are required; this action cannot read your inbox.")
    static let openAppWhenRun = true
    @Parameter(title: "Sender", description: "Original sender header, for example AX-ICICIT-S") var sender: String
    @Parameter(title: "Message", description: "Bank alert text; never saved") var message: String
    @Parameter(title: "Received at", description: "Original receipt date; use the same date for repeat imports") var receivedAt: Date
    static var parameterSummary: some ParameterSummary { Summary("Import \(\.$message) from \(\.$sender) received \(\.$receivedAt)") }
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = LedgerStore.shared; await store.load()
        guard store.loaded, await store.authenticate(), store.canEdit else { throw LedgerError.readOnly }
        guard let result = await store.importAlert(sender: sender, body: message, receivedAt: receivedAt) else { throw LedgerError.invalidReference }
        return .result(dialog: IntentDialog(stringLiteral: result))
    }
}
struct OpenImportIntent: AppIntent {
    static let title: LocalizedStringResource = "Open bank alert import"
    static let openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        let store = LedgerStore.shared; await store.load()
        guard store.loaded, await store.authenticate() else { throw LedgerError.readOnly }
        store.route = .importAlert; return .result()
    }
}
struct LedgerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddTransactionIntent(), phrases: ["Add a transaction in \(.applicationName)", "Add an expense in \(.applicationName)"], shortTitle: "Add transaction", systemImageName: "plus.circle")
        AppShortcut(intent: OpenImportIntent(), phrases: ["Import a bank alert in \(.applicationName)"], shortTitle: "Import alert", systemImageName: "text.bubble")
    }
}
