import SwiftUI
import LedgerCore

struct ActivityView: View {
    @Environment(LedgerStore.self) private var store
    @State private var filters = false
    @State private var reports = false
    var body: some View {
        @Bindable var store = store
        List {
            if store.isPreview { PreviewBanner().listRowBackground(Color.clear) }
            Section {
                HStack { Text("\(store.summary.transactions.count) transactions"); Spacer(); MoneyText(amount: store.summary.income - store.summary.spending).foregroundStyle(.secondary) }.font(.subheadline)
            }
            ForEach(store.summary.transactions) { transaction in
                NavigationLink { TransactionDetailView(transaction: transaction) } label: { TransactionRow(transaction: transaction) }
            }
        }
        .overlay { if store.summary.transactions.isEmpty { ContentUnavailableView.search(text: store.filter.search) } }
        .navigationTitle("Activity")
        .searchable(text: $store.filter.search, prompt: "Merchant, note, or reference")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button("Filters", systemImage: "line.3.horizontal.decrease") { filters = true } }
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Export report", systemImage: "square.and.arrow.up") { reports = true }.disabled(!store.canExport)
                Button("Add transaction", systemImage: "plus") { store.route = .add }
            }
        }
        .sheet(isPresented: $filters) { FilterView().ledgerSheet() }
        .sheet(isPresented: $reports) { ReportsView().ledgerSheet() }
    }
}

struct TransactionListView: View {
    @Environment(LedgerStore.self) private var store
    var title: String
    var categoryID: UUID?
    var bankID: String?
    var merchantKey: String?
    var tagID: UUID?
    var uncategorized = false
    var budget: Budget?
    @State private var transactions: [LedgerTransaction] = []
    @State private var loading = true
    private struct QueryKey: Equatable { var revision: UInt64; var filter: LedgerFilter }
    private var queryFilter: LedgerFilter {
        var filter = store.filter
        if let categoryID { filter.categoryID = categoryID }
        if let bankID { filter.bankID = bankID }
        if let merchantKey { filter.merchantKey = merchantKey }
        if let tagID { filter.tagID = tagID }
        if let budget {
            filter = LedgerFilter()
            let interval = budget.period.interval(at: .now); filter.start = interval.start; filter.end = interval.end; filter.direction = .debit
            switch budget.scope { case .category: filter.categoryID = UUID(uuidString: budget.scopeKey); case .merchant: filter.merchantKey = budget.scopeKey; case .tag: filter.tagID = UUID(uuidString: budget.scopeKey) }
        }
        return filter
    }
    var body: some View {
        List(transactions) { tx in NavigationLink { TransactionDetailView(transaction: tx) } label: { TransactionRow(transaction: tx) } }
            .navigationTitle(title).overlay {
                if loading { ProgressView() }
                else if transactions.isEmpty { ContentUnavailableView("No transactions", systemImage: "tray", description: Text("Try a different period or filter.")) }
            }
            .task(id: QueryKey(revision: store.state.revision, filter: queryFilter)) {
                let snapshot = store.presented, filter = queryFilter, onlyUncategorized = uncategorized
                let result = await Task.detached(priority: .userInitiated) {
                    snapshot.filtered(filter).filter { !onlyUncategorized || snapshot.category(for: $0) == nil }
                }.value
                guard !Task.isCancelled else { return }
                transactions = result; loading = false
            }
    }
}

struct FilterView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var filter = LedgerFilter()
    @State private var period = "month"
    @State private var start = Date.now
    @State private var end = Date.now
    private var merchants: [String] { Array(Set(store.presented.transactions.map(\.merchantKey))).sorted() }
    var body: some View {
        NavigationStack {
            Form {
                Section("Period") {
                    Picker("Range", selection: $period) {
                        Text("Today").tag("day"); Text("This week").tag("week"); Text("This month").tag("month")
                        Text("This year").tag("year"); Text("All time").tag("all"); Text("Custom").tag("custom")
                    }
                    if period == "custom" { DatePicker("From", selection: $start, displayedComponents: .date); DatePicker("Through", selection: $end, in: start..., displayedComponents: .date) }
                }
                Section("Narrow it down") {
                    Picker("Account", selection: $filter.bankID) { Text("All accounts").tag(nil as String?); ForEach(store.presented.accounts) { Text($0.bankName).tag(Optional($0.bankID)) } }
                    Picker("Direction", selection: $filter.direction) { Text("Income and expenses").tag(nil as Direction?); ForEach(Direction.allCases) { Text($0.title).tag(Optional($0)) } }
                    Picker("Category", selection: $filter.categoryID) { Text("All categories").tag(nil as UUID?); ForEach(store.presented.categories) { Text($0.name).tag(Optional($0.id)) } }
                    Picker("Merchant", selection: $filter.merchantKey) { Text("All merchants").tag(nil as String?); ForEach(merchants, id: \.self) { Text($0.capitalized).tag(Optional($0)) } }
                    Picker("Tag", selection: $filter.tagID) { Text("All tags").tag(nil as UUID?); ForEach(store.presented.tags) { Text($0.name).tag(Optional($0.id)) } }
                    Picker("Sort", selection: $filter.sort) { ForEach(SortOrder.allCases) { Text($0.rawValue).tag($0) } }
                }
                Button("Reset filters") { filter = LedgerFilter(); period = "month" }
            }.navigationTitle("Filters").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Apply", systemImage: "checkmark") { apply(); dismiss() } }
                }
                .onAppear {
                    filter = store.filter
                    if let from = filter.start, let to = filter.end { start = from; end = to.addingTimeInterval(-1); period = "custom" }
                    else { period = "all" }
                }
        }.presentationDetents([.large])
    }
    private func apply() {
        if let selected = BudgetPeriod(rawValue: period) { let interval = selected.interval(at: .now); filter.start = interval.start; filter.end = interval.end }
        else if period == "custom" { filter.start = Calendar.current.startOfDay(for: start); filter.end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: max(end, start))) }
        else { filter.start = nil; filter.end = nil }
        store.filter = filter
    }
}
