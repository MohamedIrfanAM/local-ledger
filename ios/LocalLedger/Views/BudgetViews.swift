import SwiftUI
import LedgerCore

struct BudgetsView: View {
    @Environment(LedgerStore.self) private var store
    @State private var adding = false
    var body: some View {
        List {
            if store.isPreview { PreviewBanner() }
            Section {
                Text("Make room for what matters.").font(.system(.title2, design: .rounded, weight: .semibold))
                Text("Choose your own limits. Budgets follow their current calendar cycle across all accounts.").font(.subheadline).foregroundStyle(.secondary)
            }.listRowBackground(Color.clear)
            ForEach(store.presented.budgets) { budget in
                NavigationLink { BudgetDetailView(budget: budget) } label: {
                    if let progress = store.progress.first(where: { $0.id == budget.id }) { BudgetProgressRow(progress: progress) }
                    else { Label("\(budget.label) · Paused", systemImage: "pause.circle").foregroundStyle(.secondary) }
                }
            }
            if store.presented.budgets.isEmpty {
                ContentUnavailableView("A budget that fits you", systemImage: "chart.pie", description: Text("Set a daily, weekly, monthly, or yearly cap for a category, merchant, or tag."))
                Button("Create your first budget", systemImage: "plus") { adding = true }
            }
        }.navigationTitle("Budgets").toolbar { Button("Create budget", systemImage: "plus") { adding = true } }
            .sheet(isPresented: $adding) { BudgetEditor().ledgerSheet() }
    }
}
struct BudgetProgressRow: View {
    @Environment(LedgerStore.self) private var store
    var progress: BudgetProgress
    private var color: Color { progress.status == .onTrack ? LedgerTheme.accent : LedgerTheme.expense }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text(progress.budget.label).fontWeight(.medium); Spacer(); Text(progress.status.rawValue).font(.caption).foregroundStyle(color) }
            ProgressView(value: min(progress.fraction, 1)).tint(color).accessibilityLabel("Budget used").accessibilityValue(store.privacy == .hidden ? "Hidden" : "\(Int(progress.fraction * 100)) percent")
            HStack { Text("\(store.money(progress.spent)) of \(store.money(progress.budget.amount))"); Spacer(); Text(progress.budget.period.rawValue.capitalized) }.font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 8)
    }
}
struct BudgetDetailView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var budget: Budget
    @State private var editing = false
    @State private var deleting = false
    private var current: Budget { store.presented.budgets.first { $0.id == budget.id } ?? budget }
    var body: some View {
        List {
            if store.isPreview { PreviewBanner() }
            if let progress = store.progress.first(where: { $0.id == budget.id }) {
                Section { BudgetProgressRow(progress: progress)
                    LabeledContent("Projected total") { MoneyText(amount: progress.projected) }
                    LabeledContent("Period elapsed", value: "\(Int(progress.elapsed * 100))%")
                    LabeledContent("Cycle ends", value: progress.interval.end.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted))
                } footer: { Text("Projection follows your average pace so far. Warnings start after 20% of both the cycle and budget are used.") }
            }
            NavigationLink("Transactions in this budget") { TransactionListView(title: current.label, budget: current) }
            Button("Edit budget", systemImage: "pencil") { editing = true }
            Button(current.enabled ? "Pause budget" : "Resume budget", systemImage: current.enabled ? "pause" : "play") {
                var changed = current; changed.enabled.toggle(); let saved = changed
                Task { await store.commit { try $0.saveBudget(saved) } }
            }.disabled(!store.canEdit)
            Button("Delete budget", role: .destructive) { deleting = true }.disabled(!store.canEdit)
        }.navigationTitle(current.label)
            .sheet(isPresented: $editing) { BudgetEditor(budget: current).ledgerSheet() }
            .confirmationDialog("Delete this budget? Transactions will be kept.", isPresented: $deleting, titleVisibility: .visible) {
                Button("Delete budget", role: .destructive) { let id = current.id; Task { if await store.commit({ $0.budgets.removeAll { $0.id == id } }) { dismiss() } } }
            }
    }
}
struct BudgetEditor: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var budget: Budget?
    @State private var label = ""
    @State private var amount = ""
    @State private var scope = BudgetScope.category
    @State private var scopeKey = ""
    @State private var period = BudgetPeriod.month
    @State private var alertPercent = 80
    private var choices: [(String, String)] {
        switch scope {
        case .category: store.presented.categories.map { ($0.id.uuidString, $0.name) }
        case .tag: store.presented.tags.map { ($0.id.uuidString, $0.name) }
        case .merchant: Array(Set(store.presented.transactions.map(\.merchantKey))).sorted().map { key in (key, store.presented.merchants.first { $0.merchantKey == key }?.nickname ?? key.capitalized) }
        }
    }
    var body: some View {
        NavigationStack {
            Form {
                if store.isPreview { PreviewBanner() }
                Section("Your priorities") {
                    TextField("Budget name", text: $label)
                    Picker("Track a", selection: $scope) { ForEach(BudgetScope.allCases) { Text($0.rawValue.capitalized).tag($0) } }
                    Picker("For", selection: $scopeKey) { Text("Choose one").tag(""); ForEach(choices, id: \.0) { Text($0.1).tag($0.0) } }
                    TextField("Limit in ₹", text: $amount).keyboardType(.decimalPad)
                    Picker("Period", selection: $period) { ForEach(BudgetPeriod.allCases) { Text($0.rawValue.capitalized).tag($0) } }
                }
                Section {
                    Stepper("Alert at \(alertPercent)%", value: $alertPercent, in: 5...100, step: 5)
                } footer: { Text("One quiet notification per cycle when alerts are enabled in Settings. Notifications are checked when you add or change ledger entries.") }
                Text("A 50/30/20 split is one possible starting point. Your categories and caps are yours to choose.").font(.footnote).foregroundStyle(.secondary)
            }.navigationTitle(budget == nil ? "New budget" : "Edit budget").navigationBarTitleDisplayMode(.inline)
                .toolbar { SaveToolbar {
                    do {
                        var saved = budget ?? Budget(label: label, scope: scope, scopeKey: scopeKey, amount: 1)
                        saved.label = label; saved.scope = scope; saved.scopeKey = scopeKey; saved.amount = try Money.parse(amount); saved.period = period; saved.alertPercent = alertPercent
                        let value = saved
                        if await store.commit({ try $0.saveBudget(value) }) { dismiss() }
                    } catch { store.error = error.localizedDescription }
                } }
                .onChange(of: scope) { _, _ in if !choices.contains(where: { $0.0 == scopeKey }) { scopeKey = "" } }
                .onAppear { if let budget { label = budget.label; amount = Money.decimal(budget.amount); scope = budget.scope; period = budget.period; alertPercent = budget.alertPercent; scopeKey = budget.scopeKey } }
        }
    }
}
