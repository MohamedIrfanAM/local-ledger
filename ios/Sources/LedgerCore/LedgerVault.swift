import Foundation

/// One serialized owner. A failed write never publishes a successful mutation to the UI.
public actor LedgerVault {
    private let url: URL
    private var cached: LedgerState?
    public init(url: URL) { self.url = url }
    public func load() throws -> LedgerState {
        if let cached { return cached }
        guard FileManager.default.fileExists(atPath: url.path) else {
            let initial = LedgerState(); try persist(initial); cached = initial; return initial
        }
        let state: LedgerState
        do { state = try JSONDecoder().decode(LedgerState.self, from: Data(contentsOf: url)) }
        catch { throw LedgerError.corruptStore }
        guard state.schemaVersion == 1 else { throw LedgerError.unsupportedVersion }
        guard state.transactions.count <= 100_000,
              state.transactions.allSatisfy({ $0.amount > 0 && $0.amount <= Money.maximum }),
              state.accounts.allSatisfy({ $0.openingBalance >= -Money.maximum && $0.openingBalance <= Money.maximum }),
              state.budgets.allSatisfy({ $0.amount > 0 && $0.amount <= Money.maximum }) else { throw LedgerError.corruptStore }
        cached = state; return state
    }
    @discardableResult
    public func update(_ change: @Sendable (inout LedgerState) throws -> Void) throws -> LedgerState {
        var next = try load()
        try change(&next); next.pruneDiagnostics(); next.revision += 1
        try persist(next); cached = next; return next
    }
    private func persist(_ state: LedgerState) throws {
        let manager = FileManager.default
        var directory = url.deletingLastPathComponent()
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(state)
        #if os(iOS)
        try manager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: directory.path)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: .atomic)
        #endif
        var protectedURL = url; try protectedURL.setResourceValues(values)
    }
}
