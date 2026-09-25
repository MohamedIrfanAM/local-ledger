import Foundation
import Testing
@testable import LedgerCore

struct LedgerTests {
    let now = Date(timeIntervalSince1970: 1_789_516_800) // September 2026
    func fixture() throws -> LedgerState {
        var state = LedgerState()
        try state.addAccount(.init(bankID: "icici-bank", bankName: "ICICI Bank", openingBalance: 100_000, createdAt: .distantPast))
        return state
    }
    @Test func exactMoney() throws {
        #expect(try Money.parse("1,249.50") == 124950)
        #expect(try Money.parse("0.01") == 1)
        #expect(try Money.parse("-1.01", allowNegative: true) == -101)
        #expect(try Money.parse("0", allowNegative: true) == 0)
        #expect(Money.decimal(124950) == "1249.50")
    }
    @Test(arguments: ["0", "-1", "1.001", "NaN", "inf", "1e5", "999999999999999999999999999", "", ".", "1.2.3"])
    func invalidMoney(_ amount: String) { #expect(throws: LedgerError.invalidAmount) { try Money.parse(amount) } }
    @Test func balancesRespectManualExclusions() throws {
        var state = try fixture()
        try state.saveTransaction(.init(bankID: "icici-bank", amount: 1000, direction: .debit, merchant: "Shop"))
        try state.saveTransaction(.init(bankID: "icici-bank", amount: 5000, direction: .credit, merchant: "Refund"))
        try state.saveTransaction(.init(bankID: "icici-bank", amount: 90000, direction: .debit, merchant: "Historical", affectsBalance: false))
        #expect(state.balance(for: state.accounts[0]) == 104000)
        #expect(throws: LedgerError.accountExists) { try state.addAccount(state.accounts[0]) }
    }
    @Test func tagInheritanceAndExplicitCategoryPrecedence() throws {
        var state = try fixture()
        let payment = LedgerTag(name: "Payment"), merchant = LedgerTag(name: "Merchant"), category = LedgerTag(name: "Category")
        state.tags = [payment, merchant, category]
        state.categories[0].tagIDs = [category.id]
        let tx = LedgerTransaction(bankID: "icici-bank", amount: 1000, direction: .debit, merchant: "Sample", tagIDs: [payment.id])
        try state.saveTransaction(tx)
        try state.saveMerchant(.init(merchantKey: tx.merchantKey, nickname: "Nickname", categoryID: state.categories[0].id, tagIDs: [merchant.id]))
        #expect(state.effectiveTags(for: tx) == [payment.id, merchant.id, category.id])
        #expect(state.merchantName(for: tx) == "Nickname")
        var changed = tx; changed.categoryID = state.categories[1].id
        #expect(state.category(for: changed)?.id == state.categories[1].id)
        #expect(state.effectiveTags(for: changed) == [payment.id, merchant.id])
        state.deleteTag(merchant.id); #expect(!state.effectiveTags(for: tx).contains(merchant.id))
        let categoryID = state.categories[0].id; state.deleteCategory(categoryID)
        #expect(state.category(for: tx) == nil)
    }
    @Test func filteredQueriesCombineAllConstraints() throws {
        var state = try fixture(); let tag = LedgerTag(name: "Shared"); state.tags = [tag]
        let tx = LedgerTransaction(bankID: "icici-bank", occurredAt: now, amount: 1000, direction: .debit, merchant: "Corner Cafe", categoryID: state.categories[0].id, tagIDs: [tag.id])
        try state.saveTransaction(tx)
        var filter = LedgerFilter(); filter.bankID = tx.bankID; filter.categoryID = tx.categoryID; filter.tagID = tag.id
        filter.direction = .debit; filter.merchantKey = tx.merchantKey; filter.start = now; filter.end = now.addingTimeInterval(1); filter.search = "cafe"
        #expect(state.filtered(filter).map(\.id) == [tx.id])
        filter.end = now; #expect(state.filtered(filter).isEmpty) // half-open periods
    }
    @Test func ingestionDeduplicatesAndChecksBoundaries() throws {
        var state = try fixture(); let registry = try BankRegistry()
        let body = "INR 75.00 debited from A/c XX1234 to SAMPLE STORE. UTR N123456789012."
        #expect(try state.ingest(sender: "AX-ICICIT-S", body: body, receivedAt: now, registry: registry, now: now) == .imported)
        #expect(try state.ingest(sender: "ICICIT", body: body, receivedAt: now, registry: registry, now: now) == .duplicate)
        #expect(try state.ingest(sender: "ICICIT", body: body + " Updated balance INR 500", receivedAt: now.addingTimeInterval(1), registry: registry, now: now) == .duplicate)
        #expect(try state.ingest(sender: "UNKNOWN", body: body, receivedAt: now, registry: registry, now: now) == .unknownSender)
        #expect(try state.ingest(sender: "AX-ICICIT-P", body: body, receivedAt: now, registry: registry, now: now) == .promotional)
        #expect(try state.ingest(sender: "JD-SBIUPI-S", body: body, receivedAt: now, registry: registry, now: now) == .accountMissing)
        state.accounts[0].createdAt = now.addingTimeInterval(1)
        #expect(try state.ingest(sender: "ICICIT", body: body, receivedAt: now, registry: registry, now: now) == .beforeTracking)
        #expect(state.transactions.count == 1)
    }
    @Test func diagnosticsAreBoundedAndExpire() throws {
        var state = try fixture(); let registry = try BankRegistry()
        for _ in 0..<125 { try state.ingest(sender: "UNKNOWN", body: "Private text", receivedAt: now, registry: registry, now: now) }
        #expect(state.diagnostics.count == 120)
        #expect(!state.diagnosticReport(now: now).contains("Private text"))
        state.pruneDiagnostics(now: now.addingTimeInterval(8 * 86400)); #expect(state.diagnostics.isEmpty)
    }
    @Test func budgetProjectionAndCycles() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .gmt
        let month = BudgetPeriod.month.interval(at: now, calendar: calendar)
        let halfway = month.start.addingTimeInterval(month.duration * 0.5)
        var state = try fixture(); let category = state.categories[0]
        try state.saveBudget(.init(label: "Food", scope: .category, scopeKey: category.id.uuidString, amount: 10000))
        try state.saveTransaction(.init(bankID: "icici-bank", occurredAt: month.start, amount: 7000, direction: .debit, merchant: "Lunch", categoryID: category.id))
        let progress = try #require(state.budgetProgress(now: halfway, calendar: calendar).first)
        #expect(progress.spent == 7000); #expect(progress.projected == 14000); #expect(progress.status == .projectedOver)
        #expect(state.budgetProgress(now: month.start.addingTimeInterval(60), calendar: calendar).first?.status == .onTrack)
        #expect(state.budgetProgress(now: month.end, calendar: calendar).first?.spent == 0)
        #expect(state.budgetProgress(now: month.end, calendar: calendar).first?.cycleKey != progress.cycleKey)
        state.transactions[0].amount = 10000; #expect(state.budgetProgress(now: halfway, calendar: calendar).first?.status == .over)
    }
    @Test func reportsRoundTripWithoutChangingOpeningBalance() throws {
        var state = try fixture(); let tag = LedgerTag(name: "Shared"); state.tags = [tag]
        try state.saveTransaction(.init(bankID: "icici-bank", occurredAt: now, amount: 124950, direction: .debit,
            merchant: "Cafe, \"Friends\"", categoryID: state.categories[0].id, tagIDs: [tag.id], note: "=FORMULA()\nSecond line"))
        let csv = LedgerCSV.export(state: state, transactions: state.transactions)
        #expect(csv.contains("'=FORMULA()"))
        var target = try fixture()
        #expect(try LedgerCSV.importReport(csv, into: &target) == 1)
        #expect(target.transactions[0].merchant == state.transactions[0].merchant)
        #expect(target.transactions[0].note == state.transactions[0].note)
        #expect(target.transactions[0].occurredAt == now)
        #expect(target.balance(for: target.accounts[0]) == 100000)
        #expect(try LedgerCSV.importReport(csv, into: &target) == 0)
        let exportedAgain = LedgerCSV.export(state: target, transactions: target.transactions)
        #expect(try LedgerCSV.importReport(exportedAgain, into: &target) == 0)
    }
    @Test func androidCSVAndAtomicFailure() throws {
        var state = try fixture()
        let csv = "date,direction,amount_inr,bank,merchant\n2026-09-05 12:30,DEBIT,25.50,ICICI Bank,Sample\n"
        #expect(try LedgerCSV.importReport(csv, into: &state) == 1)
        let before = state.transactions
        #expect(throws: CSVError.self) { try LedgerCSV.importReport(csv + "not-a-date,DEBIT,50,ICICI Bank,Invalid\n", into: &state) }
        #expect(state.transactions == before)
        #expect(throws: CSVError.self) { try LedgerCSV.rows("a,b\n\"unfinished") }
    }
    @Test func csvFormulaProtection() {
        for value in ["=1+1", "+CMD", "-1", "@SUM", "\t=1", "  =1"] { #expect(LedgerCSV.escape(value).hasPrefix("\"'")) }
    }
    @Test func demoContainsNoRealStateAndSummaryHasZeroDays() throws {
        let demo = DemoLedger.make(now: now)
        #expect(demo.accounts.allSatisfy { $0.bankID.hasPrefix("demo-") })
        #expect(!demo.transactions.isEmpty)
        var filter = LedgerFilter(); let interval = BudgetPeriod.month.interval(at: now); filter.start = interval.start; filter.end = interval.end
        let summary = LedgerSummary(state: demo, filter: filter)
        #expect(summary.daily.count >= 28); #expect(summary.income > 0); #expect(summary.spending > 0)
    }
    @Test func vaultPersistsAndDoesNotPublishFailedMutations() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("ledger.json"), vault = LedgerVault(url: dir.appendingPathComponent("ledger.json"))
        _ = try await vault.update { try $0.addAccount(.init(bankID: "test", bankName: "Test", openingBalance: 10000)) }
        do { _ = try await vault.update { $0.accounts.removeAll(); throw LedgerError.invalidAmount }; Issue.record("Mutation should throw") } catch {}
        #expect(try await vault.load().accounts.count == 1)
        let reopened = LedgerVault(url: url); #expect(try await reopened.load().accounts.count == 1)
        #expect(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }
    @Test func corruptAndNewerVaultsArePreserved() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("ledger.json"), corrupt = Data("not json".utf8)
        try corrupt.write(to: url)
        do { _ = try await LedgerVault(url: url).load(); Issue.record("Must reject corrupt data") } catch { #expect(error as? LedgerError == .corruptStore) }
        #expect(try Data(contentsOf: url) == corrupt)
        var state = LedgerState(); state.schemaVersion = 99; try JSONEncoder().encode(state).write(to: url)
        do { _ = try await LedgerVault(url: url).load(); Issue.record("Must reject future schema") } catch { #expect(error as? LedgerError == .unsupportedVersion) }
    }
}
