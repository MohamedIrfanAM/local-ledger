import SwiftUI
import Observation
import LocalAuthentication
import UserNotifications
import LedgerCore

@MainActor @Observable
final class LedgerStore {
    static let shared = LedgerStore()
    private(set) var state = LedgerState()
    private(set) var presented = LedgerState()
    private(set) var summary = LedgerSummary(state: LedgerState(), filter: LedgerFilter())
    private(set) var progress: [BudgetProgress] = []
    private(set) var accountBalances: [String: Int64] = [:]
    private(set) var loaded = false
    private(set) var isSaving = false
    private(set) var isLocked = true
    var error: String?
    var notice: String?
    var route: AppRoute?
    var presentedSheets = 0
    var filter = LedgerFilter() { didSet { refreshSummary() } }
    let registry: BankRegistry?
    private let vault: LedgerVault
    private var summaryTask: Task<Void, Never>?
    private var loadTask: Task<LedgerState, Error>?
    private var summaryRevision = 0
    private var notifyingBudgets = false
    private var needsNotificationCheck = false
    private var demo = DemoLedger.make()

    init() {
        let base = URL.applicationSupportDirectory.appending(path: "LocalLedger", directoryHint: .isDirectory)
        vault = LedgerVault(url: base.appending(path: "ledger-v1.json"))
        registry = try? BankRegistry()
        let interval = Calendar.current.dateInterval(of: .month, for: .now)!
        filter.start = interval.start; filter.end = interval.end
    }
    var privacy: PrivacyMode { state.preferences.privacy }
    var canEdit: Bool { loaded && !isLocked && privacy == .visible && !isSaving }
    var canExport: Bool { canEdit }
    var isPreview: Bool { privacy != .visible }

    func load() async {
        guard !loaded else { return }
        if loadTask == nil { let vault = vault; loadTask = Task { try await vault.load() } }
        do {
            let saved = try await loadTask!.value
            guard !loaded else { return }
            state = saved; loaded = true; isLocked = saved.preferences.appLock
            apply(saved)
        } catch { self.error = error.localizedDescription; loadTask = nil }
    }
    private func apply(_ next: LedgerState) {
        guard next.revision >= state.revision else { return }
        if state.preferences.privacy != next.preferences.privacy {
            summary = LedgerSummary(state: LedgerState(), filter: LedgerFilter())
            progress = []
            accountBalances = [:]
            route = nil
        }
        state = next
        presented = next.preferences.privacy == .visible ? next : demo
        refreshSummary()
    }
    func refreshSummary() {
        summaryTask?.cancel(); summaryRevision += 1
        let revision = summaryRevision, snapshot = presented, selected = filter
        summaryTask = Task {
            let result = await Task.detached(priority: .userInitiated) {
                var balances = Dictionary(uniqueKeysWithValues: snapshot.accounts.map { ($0.bankID, $0.openingBalance) })
                for tx in snapshot.transactions where tx.affectsBalance { balances[tx.bankID, default: 0] += tx.direction == .credit ? tx.amount : -tx.amount }
                return (LedgerSummary(state: snapshot, filter: selected), snapshot.budgetProgress(), balances)
            }.value
            guard !Task.isCancelled, summaryRevision == revision else { return }
            summary = result.0; progress = result.1; accountBalances = result.2
        }
    }
    @discardableResult
    func commit(_ change: @escaping @Sendable (inout LedgerState) throws -> Void) async -> Bool {
        guard canEdit else { error = LedgerError.readOnly.localizedDescription; return false }
        isSaving = true
        do {
            let next = try await vault.update(change)
            apply(next); isSaving = false
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            await notifyBudgets()
            return true
        } catch { self.error = error.localizedDescription; isSaving = false; return false }
    }
    func setPreferences(_ change: @escaping @Sendable (inout Preferences) -> Void) async {
        guard loaded, !isLocked else { return }
        do { apply(try await vault.update { change(&$0.preferences) }) }
        catch { self.error = error.localizedDescription }
    }
    func setPrivacy(_ mode: PrivacyMode) async {
        // Clear every filter that could contain a real merchant/category/tag before presenting samples.
        var clean = LedgerFilter(); clean.start = filter.start; clean.end = filter.end; filter = clean
        await setPreferences { $0.privacy = mode }
        UISelectionFeedbackGenerator().selectionChanged()
    }
    func lock() { if state.preferences.appLock { isLocked = true; route = nil } }
    @discardableResult
    func authenticate() async -> Bool {
        if !isLocked { return true }
        do {
            let context = LAContext()
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock your private ledger")
            if success { isLocked = false }
            return success
        } catch { self.error = error.localizedDescription; return false }
    }
    func toggleAppLock(_ enabled: Bool) async {
        do {
            let context = LAContext()
            guard try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Change Local Ledger app lock") else { return }
            await setPreferences { $0.appLock = enabled }
        } catch { self.error = error.localizedDescription }
    }
    func toggleNotifications(_ enabled: Bool) async {
        do {
            if enabled {
                guard try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge]) else {
                    error = "Notifications are disabled. Enable them for Local Ledger in iOS Settings."; return
                }
            } else {
                UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
                UNUserNotificationCenter.current().removeAllDeliveredNotifications()
            }
            await setPreferences { $0.budgetNotifications = enabled }
            if enabled { await notifyBudgets() }
        } catch { self.error = error.localizedDescription }
    }
    private func notifyBudgets() async {
        guard state.preferences.budgetNotifications, privacy == .visible else { return }
        guard !notifyingBudgets else { needsNotificationCheck = true; return }
        notifyingBudgets = true
        defer { notifyingBudgets = false }
        let center = UNUserNotificationCenter.current()
        repeat {
          needsNotificationCheck = false
          for item in state.budgetProgress() where item.fraction * 100 >= Double(item.budget.alertPercent) && !state.alertedCycles.contains(item.cycleKey) {
            guard state.preferences.budgetNotifications, privacy == .visible else { return }
            let key = item.cycleKey
            let content = UNMutableNotificationContent()
            content.title = "A moment for your budget"
            content.body = "A budget reached its alert threshold. Open Local Ledger to review it."
            do {
                // Claim first to avoid racing another import. Release on delivery failure.
                apply(try await vault.update { $0.alertedCycles.insert(key) })
                try await center.add(UNNotificationRequest(identifier: key, content: content, trigger: nil))
            } catch {
                if let next = try? await vault.update({ $0.alertedCycles.remove(key) }) { apply(next) }
            }
          }
        } while needsNotificationCheck
    }
    func importAlert(sender: String, body: String, receivedAt: Date) async -> String? {
        guard let registry else { error = "The bundled bank registry could not be loaded."; return nil }
        guard canEdit else { error = LedgerError.readOnly.localizedDescription; return nil }
        isSaving = true
        do {
            let next = try await vault.update { state in try state.ingest(sender: sender, body: body, receivedAt: receivedAt, registry: registry) }
            let result = next.diagnostics.last?.outcome.message
            apply(next); isSaving = false; await notifyBudgets(); return result
        } catch { self.error = error.localizedDescription; isSaving = false; return nil }
    }
    func money(_ amount: Int64) -> String { privacy == .hidden ? "••••" : Money.formatted(amount) }
    func balance(for account: Account) -> Int64 { accountBalances[account.bankID] ?? account.openingBalance }
    func open(_ url: URL) {
        guard url.scheme == "localledger" else { return }
        switch url.host { case "add": route = .add; case "import": route = .importAlert; case "budgets": route = .budgets; default: break }
    }
}

enum AppRoute: String, Identifiable { case add, importAlert, budgets, accounts; var id: String { rawValue } }
