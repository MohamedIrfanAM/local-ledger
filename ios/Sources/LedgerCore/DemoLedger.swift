import Foundation

public enum DemoLedger {
    /// Entirely independent of the real ledger, including names, dates, IDs, and chart geometry.
    public static func make(now: Date = .now, calendar: Calendar = .current) -> LedgerState {
        var state = LedgerState()
        let month = calendar.dateInterval(of: .month, for: now)!.start
        state.accounts = [Account(bankID: "demo-everyday", bankName: "Everyday account", openingBalance: 6_850_000, createdAt: month),
                          Account(bankID: "demo-savings", bankName: "Savings account", openingBalance: 12_500_000, createdAt: month)]
        state.tags = [LedgerTag(name: "Everyday"), LedgerTag(name: "Shared", color: "9581B7")]
        let entries: [(String, String, Int64)] = [("Sunday Coffee", "Food", 32_000), ("Green Basket", "Food", 185_000),
            ("City Metro", "Transport", 8_500), ("The Reading Room", "Shopping", 89_900), ("Home", "Rent", 2_400_000),
            ("Studio Cinema", "Entertainment", 64_000), ("Neighbourhood Market", "Food", 124_500), ("Electricity", "Utilities", 186_000)]
        let elapsed = max(1, calendar.component(.day, from: now))
        for i in 0..<24 {
            let entry = entries[i % entries.count]
            let date = calendar.date(byAdding: .day, value: i % elapsed, to: month)!
            var tx = LedgerTransaction(bankID: "demo-everyday", occurredAt: min(date.addingTimeInterval(12 * 3600), now), amount: entry.2,
                direction: .debit, merchant: entry.0, categoryID: state.categories.first { $0.name == entry.1 }?.id)
            if i % 3 == 0 { tx.tagIDs = [state.tags[0].id] }; state.transactions.append(tx)
        }
        state.transactions.append(.init(bankID: "demo-everyday", occurredAt: month, amount: 15_000_000, direction: .credit,
            merchant: "Monthly salary", categoryID: state.categories.first { $0.name == "Income" }?.id))
        for (name, amount) in [("Food", Int64(2_000_000)), ("Shopping", 1_200_000), ("Transport", 600_000)] {
            state.budgets.append(.init(label: name, scope: .category, scopeKey: state.categories.first { $0.name == name }!.id.uuidString, amount: amount))
        }
        return state
    }
}
