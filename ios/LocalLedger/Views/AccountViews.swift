import SwiftUI
import LedgerCore

struct AccountsView: View {
    @Environment(LedgerStore.self) private var store
    @State private var adding = false
    var body: some View {
        List {
            if store.isPreview { PreviewBanner() }
            ForEach(store.presented.accounts) { account in
                NavigationLink { AccountDetailView(account: account) } label: {
                    HStack {
                        Image(systemName: "building.columns").foregroundStyle(LedgerTheme.accent).frame(width: 36)
                        VStack(alignment: .leading, spacing: 5) { Text(account.bankName); Text("Since \(account.createdAt.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary) }
                        Spacer(); MoneyText(amount: store.balance(for: account)).font(.subheadline.weight(.semibold))
                    }.padding(.vertical, 8)
                }
            }
            Section { Text("Calculated balance = opening balance + income − expenses marked to adjust balance. One account per bank is supported.").font(.footnote).foregroundStyle(.secondary) }
        }.navigationTitle("Accounts").toolbar { Button("Add account", systemImage: "plus") { adding = true } }
            .sheet(isPresented: $adding) { AccountEditor().ledgerSheet() }
    }
}
struct AccountDetailView: View {
    @Environment(LedgerStore.self) private var store
    var account: Account
    @State private var editing = false
    private var current: Account { store.presented.accounts.first { $0.id == account.id } ?? account }
    var body: some View {
        List {
            Section {
                MoneyText(amount: store.balance(for: current)).font(.system(.largeTitle, design: .rounded, weight: .semibold)).padding(.vertical)
                LabeledContent("Opening balance") { MoneyText(amount: current.openingBalance) }
                LabeledContent("Tracking began", value: current.createdAt.formatted(date: .abbreviated, time: .shortened))
            }
            NavigationLink("Account activity") { TransactionListView(title: current.bankName, bankID: current.bankID) }
            Button("Correct opening balance") { editing = true }
        }.navigationTitle(current.bankName).sheet(isPresented: $editing) { AccountEditor(account: current).ledgerSheet() }
    }
}
struct AccountEditor: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var account: Account?
    @State private var bankID = ""
    @State private var balance = ""
    @State private var date = Date.now
    @State private var search = ""
    private var banks: [BankDefinition] { (store.registry?.banks ?? []).filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        NavigationStack {
            Form {
                if store.isPreview { PreviewBanner() }
                if let account { Text(account.bankName).font(.headline) }
                else {
                    Section("Choose your bank") {
                        TextField("Find a bank", text: $search)
                        Picker("Bank", selection: $bankID) {
                            Text("Select a bank").tag("")
                            ForEach(banks) { Text($0.name).tag($0.id) }
                        }
                    }
                }
                Section {
                    TextField("Balance in ₹", text: $balance).keyboardType(.numbersAndPunctuation)
                    if account == nil { DatePicker("Balance as of", selection: $date, in: ...Date.now) }
                } header: { Text(account == nil ? "Opening balance" : "Correct opening balance") }
                footer: { Text("Use the balance at this exact date and time. Older alerts are excluded to avoid counting transactions twice. You can import historical CSV reports without adjusting balances.") }
            }.navigationTitle(account == nil ? "Add account" : "Opening balance").navigationBarTitleDisplayMode(.inline)
                .toolbar { SaveToolbar {
                    do {
                        let amount = try Money.parse(balance, allowNegative: true)
                        if var changed = account {
                            changed.openingBalance = amount; let updated = changed
                            if await store.commit({ state in if let index = state.accounts.firstIndex(where: { $0.id == updated.id }) { state.accounts[index] = updated } }) { dismiss() }
                        } else if let bank = store.registry?.banks.first(where: { $0.id == bankID }) {
                            let newAccount = Account(bankID: bank.id, bankName: bank.name, openingBalance: amount, createdAt: date)
                            if await store.commit({ try $0.addAccount(newAccount) }) { dismiss() }
                        } else { store.error = "Select a bank first." }
                    } catch { store.error = error.localizedDescription }
                } }
                .onAppear { if let account { bankID = account.bankID; balance = Money.decimal(account.openingBalance); date = account.createdAt } }
        }
    }
}
