import SwiftUI
import LedgerCore

struct TransactionDetailView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var transaction: LedgerTransaction
    @State private var editing = false
    @State private var merchantEditing = false
    @State private var deleting = false
    private var current: LedgerTransaction { store.presented.transactions.first { $0.id == transaction.id } ?? transaction }
    var body: some View {
        List {
            Section {
                VStack(spacing: 16) {
                    CategoryIcon(category: store.presented.category(for: current))
                    Text(store.presented.merchantName(for: current)).font(.title2.weight(.semibold))
                    MoneyText(amount: current.amount).font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    Text(current.direction.title).foregroundStyle(current.direction == .credit ? LedgerTheme.income : LedgerTheme.expense)
                }.frame(maxWidth: .infinity).padding(.vertical, 20)
            }.listRowBackground(Color.clear)
            if store.isPreview { PreviewBanner() }
            Section("Details") {
                LabeledContent("Account", value: store.presented.accounts.first { $0.bankID == current.bankID }?.bankName ?? current.bankID)
                LabeledContent("Date", value: current.occurredAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Category", value: store.presented.category(for: current)?.name ?? "Uncategorized")
                LabeledContent("Changes balance", value: current.affectsBalance ? "Yes" : "No")
                LabeledContent("Source", value: current.origin == .alert ? "Imported bank alert" : (current.origin == .csv ? "CSV import" : "Manual entry"))
                if let reference = current.reference { LabeledContent("Reference", value: reference).textSelection(.enabled) }
                if !current.note.isEmpty { Text(current.note) }
            }
            Section("Effective tags") {
                let effective = store.presented.effectiveTags(for: current)
                if effective.isEmpty { Text("No tags yet").foregroundStyle(.secondary) }
                ForEach(store.presented.tags.filter { effective.contains($0.id) }) { tag in
                    Label(tag.name, systemImage: current.tagIDs.contains(tag.id) ? "tag" : "tag.circle").foregroundStyle(Color(hex: tag.color))
                }
                Text("Includes tags inherited from this merchant and category.").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button("Edit transaction", systemImage: "pencil") { editing = true }
                Button("Merchant nickname, category & tags", systemImage: "storefront") { merchantEditing = true }
                NavigationLink("All transactions for this merchant") { TransactionListView(title: store.presented.merchantName(for: current), merchantKey: current.merchantKey) }
            }
            if current.origin == .alert {
                Section("Parser") {
                    LabeledContent("Profile", value: current.parserID)
                    LabeledContent("Confidence", value: "\(current.confidence)%")
                    Text("Message bodies are discarded after parsing. A recognized sender header is an allowlist match, not proof of authenticity.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section { Button("Delete transaction", role: .destructive) { deleting = true }.disabled(!store.canEdit) }
        }.navigationTitle("Transaction").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $editing) { TransactionEditor(transaction: current).ledgerSheet() }
            .sheet(isPresented: $merchantEditing) { MerchantEditor(transaction: current).ledgerSheet() }
            .confirmationDialog("Delete this transaction? Its balance effect will also be removed.", isPresented: $deleting, titleVisibility: .visible) {
                Button("Delete transaction", role: .destructive) {
                    let id = current.id
                    Task { if await store.commit({ $0.transactions.removeAll { $0.id == id } }) { dismiss() } }
                }
            }
    }
}

struct TransactionEditor: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var transaction: LedgerTransaction?
    @State private var amount = ""
    @State private var direction = Direction.debit
    @State private var bankID = ""
    @State private var merchant = ""
    @State private var date = Date.now
    @State private var categoryID: UUID?
    @State private var tags: Set<UUID> = []
    @State private var note = ""
    @State private var affectsBalance = true
    var body: some View {
        NavigationStack {
            Form {
                if store.isPreview { PreviewBanner(); Text("Explore the editor with sample data. Return to Visible mode to save.").font(.caption) }
                Section {
                    Picker("Type", selection: $direction) { ForEach(Direction.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                    HStack(alignment: .firstTextBaseline) { Text("₹").foregroundStyle(.secondary); TextField("0.00", text: $amount).keyboardType(.decimalPad) }.font(.system(.largeTitle, design: .rounded, weight: .medium))
                    Picker("Account", selection: $bankID) { ForEach(store.presented.accounts) { Text($0.bankName).tag($0.bankID) } }
                }
                Section("The details") {
                    TextField(direction == .debit ? "Merchant or description" : "Income source", text: $merchant).textInputAutocapitalization(.words)
                    DatePicker("When", selection: $date, in: ...Date.now)
                    Picker("Category", selection: $categoryID) { Text("Use merchant category").tag(nil as UUID?); ForEach(store.presented.categories) { Text($0.name).tag(Optional($0.id)) } }
                    TextField("Note (optional)", text: $note, axis: .vertical).lineLimit(3...6)
                }
                Section("Payment-only tags") { TagSelection(selected: $tags) }
                Section { Toggle("Adjust account balance", isOn: $affectsBalance) } footer: { Text("Turn off for entries already included in your account’s opening balance.") }
                if transaction?.origin == .alert { Text("Editing preserves the original import fingerprint and reference to prevent duplicate alerts.").font(.caption).foregroundStyle(.secondary) }
            }.navigationTitle(transaction == nil ? "New transaction" : "Edit transaction").navigationBarTitleDisplayMode(.inline)
                .toolbar { SaveToolbar { await save() } }
                .onAppear {
                    bankID = transaction?.bankID ?? store.presented.accounts.first?.bankID ?? ""
                    if let tx = transaction { amount = Money.decimal(tx.amount); direction = tx.direction; merchant = tx.merchant; date = tx.occurredAt; categoryID = tx.categoryID; tags = tx.tagIDs; note = tx.note; affectsBalance = tx.affectsBalance }
                }
        }
    }
    private func save() async {
        do {
            let money = try Money.parse(amount)
            let name = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
            var tx = transaction ?? LedgerTransaction(bankID: bankID, amount: money, direction: direction, merchant: name.isEmpty ? (direction == .debit ? "Cash expense" : "Manual income") : name)
            tx.amount = money; tx.direction = direction; tx.bankID = bankID; tx.occurredAt = date
            if !name.isEmpty { tx.merchant = name; tx.merchantKey = TransactionParser.normalizeMerchant(name) }
            tx.categoryID = categoryID; tx.tagIDs = tags; tx.note = note; tx.affectsBalance = affectsBalance
            let saved = tx
            if await store.commit({ try $0.saveTransaction(saved) }) { dismiss() }
        } catch { store.error = error.localizedDescription }
    }
}

struct TagSelection: View {
    @Environment(LedgerStore.self) private var store
    @Binding var selected: Set<UUID>
    var body: some View {
        if store.presented.tags.isEmpty { Text("Create tags in Settings → Categories & tags.").foregroundStyle(.secondary).font(.subheadline) }
        ForEach(store.presented.tags) { tag in
            Toggle(tag.name, isOn: Binding(get: { selected.contains(tag.id) }, set: { if $0 { selected.insert(tag.id) } else { selected.remove(tag.id) } }))
        }
    }
}

struct MerchantEditor: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var transaction: LedgerTransaction
    @State private var nickname = ""
    @State private var categoryID: UUID?
    @State private var tags: Set<UUID> = []
    var body: some View {
        NavigationStack {
            Form {
                PreviewBanner()
                Section { Text(transaction.merchant).foregroundStyle(.secondary); TextField("Nickname", text: $nickname)
                    Picker("Default category", selection: $categoryID) { Text("Uncategorized").tag(nil as UUID?); ForEach(store.presented.categories) { Text($0.name).tag(Optional($0.id)) } }
                } footer: { Text("Applies to all payments for this merchant. A transaction’s explicit category takes precedence.") }
                Section("Inherited tags") { TagSelection(selected: $tags) }
            }.navigationTitle("Merchant").navigationBarTitleDisplayMode(.inline)
                .toolbar { SaveToolbar {
                    let rule = MerchantRule(merchantKey: transaction.merchantKey, nickname: nickname, categoryID: categoryID, tagIDs: tags)
                    if await store.commit({ try $0.saveMerchant(rule) }) { dismiss() }
                } }
                .onAppear { if let rule = store.presented.merchants.first(where: { $0.merchantKey == transaction.merchantKey }) { nickname = rule.nickname; categoryID = rule.categoryID; tags = rule.tagIDs } }
        }
    }
}
