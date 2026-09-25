import Foundation

public extension LedgerState {
    func category(for tx: LedgerTransaction) -> Category? {
        let id = tx.categoryID ?? merchants.first { $0.merchantKey == tx.merchantKey }?.categoryID
        return categories.first { $0.id == id }
    }
    func merchantName(for tx: LedgerTransaction) -> String {
        let name = merchants.first { $0.merchantKey == tx.merchantKey }?.nickname ?? ""
        return name.isEmpty ? tx.merchant : name
    }
    func effectiveTags(for tx: LedgerTransaction) -> Set<UUID> {
        tx.tagIDs.union(merchants.first { $0.merchantKey == tx.merchantKey }?.tagIDs ?? []).union(category(for: tx)?.tagIDs ?? [])
    }
    func balance(for account: Account) -> Int64 {
        transactions.lazy.filter { $0.bankID == account.bankID && $0.affectsBalance }.reduce(account.openingBalance) {
            $0 + ($1.direction == .credit ? $1.amount : -$1.amount)
        }
    }
    func filtered(_ filter: LedgerFilter) -> [LedgerTransaction] {
        transactions.filter { tx in
            (filter.bankID == nil || filter.bankID == tx.bankID) &&
            (filter.categoryID == nil || filter.categoryID == category(for: tx)?.id) &&
            (filter.merchantKey == nil || filter.merchantKey == tx.merchantKey) &&
            (filter.tagID == nil || effectiveTags(for: tx).contains(filter.tagID!)) &&
            (filter.direction == nil || filter.direction == tx.direction) &&
            (filter.start == nil || tx.occurredAt >= filter.start!) &&
            (filter.end == nil || tx.occurredAt < filter.end!) &&
            (filter.search.isEmpty || [merchantName(for: tx), tx.merchant, tx.note, category(for: tx)?.name ?? "", tx.reference ?? ""]
                .joined(separator: " ").localizedCaseInsensitiveContains(filter.search))
        }.sorted { lhs, rhs in
            switch filter.sort {
            case .newest: lhs.occurredAt > rhs.occurredAt
            case .oldest: lhs.occurredAt < rhs.occurredAt
            case .largest: lhs.amount == rhs.amount ? lhs.occurredAt > rhs.occurredAt : lhs.amount > rhs.amount
            case .merchant: merchantName(for: lhs).localizedStandardCompare(merchantName(for: rhs)) == .orderedAscending
            }
        }
    }
    func budgetProgress(now: Date = .now, calendar: Calendar = .current) -> [BudgetProgress] {
        budgets.filter(\.enabled).map { budget in
            let interval = budget.period.interval(at: now, calendar: calendar)
            let spent = transactions.lazy.filter { tx in
                guard tx.direction == .debit, tx.occurredAt >= interval.start, tx.occurredAt < interval.end else { return false }
                switch budget.scope {
                case .category: return category(for: tx)?.id.uuidString == budget.scopeKey
                case .merchant: return tx.merchantKey == budget.scopeKey
                case .tag: return effectiveTags(for: tx).contains { $0.uuidString == budget.scopeKey }
                }
            }.reduce(Int64(0)) { $0 + $1.amount }
            let elapsed = min(1, max(0.001, now.timeIntervalSince(interval.start) / interval.duration))
            let projected = Int64(min(Double(Money.maximum) * 100_000, Double(spent) / elapsed))
            let fraction = Double(spent) / Double(budget.amount)
            let status: BudgetStatus = spent >= budget.amount ? .over :
                (elapsed >= 0.2 && fraction >= 0.2 && projected > budget.amount ? .projectedOver :
                    (fraction >= Double(budget.alertPercent) / 100 ? .watch : .onTrack))
            return .init(budget: budget, spent: spent, projected: projected, elapsed: elapsed, interval: interval, status: status)
        }
    }
    mutating func addAccount(_ account: Account) throws {
        guard !accounts.contains(where: { $0.bankID == account.bankID }) else { throw LedgerError.accountExists }
        guard abs(account.openingBalance) <= Money.maximum else { throw LedgerError.invalidAmount }
        accounts.append(account)
    }
    mutating func saveTransaction(_ transaction: LedgerTransaction) throws {
        guard accounts.contains(where: { $0.bankID == transaction.bankID }) else { throw LedgerError.accountMissing }
        guard transaction.amount > 0, transaction.amount <= Money.maximum, transactions.count < 100_000 else { throw LedgerError.invalidAmount }
        guard !transaction.merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, transaction.merchant.count <= 80 else { throw LedgerError.invalidName }
        guard transaction.categoryID == nil || categories.contains(where: { $0.id == transaction.categoryID }),
              transaction.tagIDs.isSubset(of: Set(tags.map(\.id))) else { throw LedgerError.invalidReference }
        if let index = transactions.firstIndex(where: { $0.id == transaction.id }) { transactions[index] = transaction }
        else { transactions.append(transaction) }
    }
    mutating func saveCategory(_ category: Category) throws {
        try validateName(category.name)
        guard !categories.contains(where: { $0.id != category.id && $0.name.caseInsensitiveCompare(category.name) == .orderedSame }) else { throw LedgerError.invalidName }
        if let index = categories.firstIndex(where: { $0.id == category.id }) { categories[index] = category } else { categories.append(category) }
    }
    mutating func saveTag(_ tag: LedgerTag) throws {
        try validateName(tag.name)
        guard !tags.contains(where: { $0.id != tag.id && $0.name.caseInsensitiveCompare(tag.name) == .orderedSame }) else { throw LedgerError.invalidName }
        if let index = tags.firstIndex(where: { $0.id == tag.id }) { tags[index] = tag } else { tags.append(tag) }
    }
    mutating func saveMerchant(_ merchant: MerchantRule) throws {
        if !merchant.nickname.isEmpty { try validateName(merchant.nickname) }
        guard merchant.categoryID == nil || categories.contains(where: { $0.id == merchant.categoryID }),
              merchant.tagIDs.isSubset(of: Set(tags.map(\.id))) else { throw LedgerError.invalidReference }
        if let index = merchants.firstIndex(where: { $0.id == merchant.id }) { merchants[index] = merchant } else { merchants.append(merchant) }
    }
    mutating func saveBudget(_ budget: Budget) throws {
        try validateName(budget.label)
        guard budget.amount > 0, budget.amount <= Money.maximum, (1...100).contains(budget.alertPercent) else { throw LedgerError.invalidAmount }
        let valid: Bool = switch budget.scope {
        case .category: categories.contains { $0.id.uuidString == budget.scopeKey }
        case .tag: tags.contains { $0.id.uuidString == budget.scopeKey }
        case .merchant: transactions.contains { $0.merchantKey == budget.scopeKey }
        }
        guard valid else { throw LedgerError.invalidReference }
        if let index = budgets.firstIndex(where: { $0.id == budget.id }) { budgets[index] = budget } else { budgets.append(budget) }
    }
    mutating func deleteCategory(_ id: UUID) {
        categories.removeAll { $0.id == id }
        for i in transactions.indices where transactions[i].categoryID == id { transactions[i].categoryID = nil }
        for i in merchants.indices where merchants[i].categoryID == id { merchants[i].categoryID = nil }
        budgets.removeAll { $0.scope == .category && $0.scopeKey == id.uuidString }
    }
    mutating func deleteTag(_ id: UUID) {
        tags.removeAll { $0.id == id }
        for i in transactions.indices { transactions[i].tagIDs.remove(id) }
        for i in categories.indices { categories[i].tagIDs.remove(id) }
        for i in merchants.indices { merchants[i].tagIDs.remove(id) }
        budgets.removeAll { $0.scope == .tag && $0.scopeKey == id.uuidString }
    }
    @discardableResult
    mutating func ingest(sender: String, body: String, receivedAt: Date, registry: BankRegistry, now: Date = .now) throws -> ImportOutcome {
        let outcome: ImportOutcome
        if sender.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().hasSuffix("-P") { outcome = .promotional }
        else if let bank = registry.bank(for: sender) {
            if let account = accounts.first(where: { $0.bankID == bank.id }) {
                if receivedAt < account.createdAt { outcome = .beforeTracking }
                else if let parsed = TransactionParser.parse(body, receivedAt: receivedAt, bankID: bank.id) {
                    if parsed.occurredAt < account.createdAt { outcome = .beforeTracking }
                    else {
                        let source = TransactionParser.sourceKey(sender: sender, body: body, receivedAt: receivedAt)
                        if transactions.contains(where: { $0.sourceKey == source ||
                            (parsed.reference != nil && $0.bankID == bank.id && $0.direction == parsed.direction && $0.reference?.uppercased() == parsed.reference?.uppercased()) }) { outcome = .duplicate }
                        else {
                            var tx = LedgerTransaction(bankID: bank.id, occurredAt: parsed.occurredAt, amount: parsed.amount, direction: parsed.direction, merchant: parsed.merchant)
                            tx.receivedAt = receivedAt; tx.origin = .alert; tx.reference = parsed.reference
                            tx.sourceKey = source; tx.senderHeader = BankRegistry.normalize(sender); tx.parserID = parsed.parserID; tx.confidence = parsed.confidence
                            try saveTransaction(tx); outcome = .imported
                        }
                    }
                } else { outcome = .notParsed }
            } else { outcome = .accountMissing }
        } else { outcome = .unknownSender }
        diagnostics.append(.init(date: now, outcome: outcome, signals: TransactionParser.diagnosticSignals(body)))
        pruneDiagnostics(now: now)
        return outcome
    }
    mutating func pruneDiagnostics(now: Date = .now) {
        diagnostics = Array(diagnostics.filter { $0.date >= now.addingTimeInterval(-7 * 86400) }.suffix(120))
    }
    func diagnosticReport(now: Date = .now) -> String {
        "Local Ledger · iOS\nNo bodies, names, senders, amounts, balances, or references.\n" +
        diagnostics.filter { $0.date >= now.addingTimeInterval(-7 * 86400) }.suffix(120).map {
            "\($0.date.ISO8601Format()) | \($0.outcome.rawValue) | \($0.signals)"
        }.joined(separator: "\n")
    }
    private func validateName(_ name: String) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 80 else { throw LedgerError.invalidName }
    }
}

public struct CategoryTotal: Identifiable, Sendable {
    public var id: String { name }
    public var categoryID: UUID?
    public var name: String
    public var color: String
    public var amount: Int64
}
public struct DailyTotal: Identifiable, Sendable {
    public var id: Date { date }
    public var date: Date
    public var amount: Int64
}
public struct LedgerSummary: Sendable {
    public var transactions: [LedgerTransaction]
    public var income: Int64
    public var spending: Int64
    public var categories: [CategoryTotal]
    public var daily: [DailyTotal]
    public init(state: LedgerState, filter: LedgerFilter, calendar: Calendar = .current) {
        transactions = state.filtered(filter)
        income = transactions.filter { $0.direction == .credit }.reduce(0) { $0 + $1.amount }
        spending = transactions.filter { $0.direction == .debit }.reduce(0) { $0 + $1.amount }
        var totals: [String: CategoryTotal] = [:]; var days: [Date: Int64] = [:]
        for tx in transactions where tx.direction == .debit {
            let category = state.category(for: tx); let key = category?.id.uuidString ?? "uncategorized"
            var total = totals[key] ?? CategoryTotal(categoryID: category?.id, name: category?.name ?? "Uncategorized", color: category?.color ?? "88928B", amount: 0)
            total.amount += tx.amount; totals[key] = total
            days[calendar.startOfDay(for: tx.occurredAt), default: 0] += tx.amount
        }
        categories = totals.values.sorted { $0.amount > $1.amount }
        // Include zero-spend days; chart spacing and daily averages must remain honest.
        if let start = filter.start, let end = filter.end, end.timeIntervalSince(start) <= 370 * 86400 {
            var day = calendar.startOfDay(for: start)
            while day < end { if days[day] == nil { days[day] = 0 }; day = calendar.date(byAdding: .day, value: 1, to: day)! }
        }
        daily = days.map { DailyTotal(date: $0.key, amount: $0.value) }.sorted { $0.date < $1.date }
    }
}
