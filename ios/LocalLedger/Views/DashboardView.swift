import SwiftUI
import Charts
import LedgerCore

struct DashboardView: View {
    @Environment(LedgerStore.self) private var store
    @State private var filters = false
    private var modules: [DashboardModule] { store.state.preferences.dashboardOrder.filter { !store.state.preferences.hiddenModules.contains($0) } }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(Date.now.formatted(.dateTime.month(.wide).year()).uppercased()).font(.caption.weight(.semibold)).tracking(2).foregroundStyle(.secondary)
                        Text("Room to breathe.").font(.system(.title, design: .rounded, weight: .semibold))
                    }
                    Spacer()
                    Image(systemName: "leaf").font(.title).foregroundStyle(LedgerTheme.accent).accessibilityHidden(true)
                }.padding(.vertical, 8)
                PreviewBanner()
                Button { filters = true } label: {
                    Label(filterTitle, systemImage: "line.3.horizontal.decrease").font(.subheadline.weight(.medium))
                }.buttonStyle(.glass).controlSize(.regular)
                ForEach(modules) { module in moduleView(module) }
                Text("Made for awareness. Reconcile important totals with your bank statement.")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 6)
            }.padding(20).frame(maxWidth: 840)
                .frame(maxWidth: .infinity)
        }
        .background(LedgerTheme.canvas).navigationTitle("Local Ledger").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { privacyMenu }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Add transaction", systemImage: "plus") { store.route = .add }
                    Button("Import bank alert", systemImage: "text.bubble") { store.route = .importAlert }
                } label: { Image(systemName: "plus") }.accessibilityLabel("Add to ledger")
            }
        }
        .sheet(isPresented: $filters) { FilterView().ledgerSheet() }
    }
    private var filterTitle: String {
        let period = store.filter.start.map { $0.formatted(.dateTime.day().month(.abbreviated)) } ?? "All time"
        let bank = store.presented.accounts.first { $0.bankID == store.filter.bankID }?.bankName
        return period + (bank.map { " · " + $0 } ?? " · All accounts")
    }
    private var privacyMenu: some View {
        Menu {
            ForEach(PrivacyMode.allCases) { mode in
                Button { Task { await store.setPrivacy(mode) } } label: {
                    Label(mode.rawValue.capitalized, systemImage: mode == store.privacy ? "checkmark" : "circle")
                }
            }
        } label: { Image(systemName: store.privacy == .visible ? "eye" : (store.privacy == .demo ? "sparkles" : "eye.slash")) }
            .accessibilityLabel("Privacy mode, \(store.privacy.rawValue)")
    }
    @ViewBuilder private func moduleView(_ module: DashboardModule) -> some View {
        switch module {
        case .balance: balanceCard
        case .cashFlow: cashFlowCard
        case .trend: trendCard
        case .categories: categoriesCard
        case .moneyFlow: moneyFlowCard
        case .budgets: budgetCard
        case .insights: insightsCard
        case .recent: recentCard
        }
    }
    private var balanceCard: some View {
        NavigationLink { AccountsView() } label: {
            VStack(alignment: .leading, spacing: 22) {
                HStack { Label("AVAILABLE BALANCE", systemImage: "building.columns").font(.caption.weight(.semibold)).tracking(1.5); Spacer(); Image(systemName: "arrow.up.right") }
                MoneyText(amount: store.presented.accounts.filter { store.filter.bankID == nil || $0.bankID == store.filter.bankID }.reduce(0) { $0 + store.balance(for: $1) })
                    .font(.system(size: 40, weight: .semibold, design: .rounded)).minimumScaleFactor(0.5).lineLimit(1)
                HStack {
                    Text("Across \(store.filter.bankID == nil ? store.presented.accounts.count : 1) accounts").font(.subheadline)
                    Spacer(); Label("On device", systemImage: "lock.shield").font(.caption)
                }.foregroundStyle(.white.opacity(0.8))
            }.padding(26).foregroundStyle(.white)
                .background(LinearGradient(colors: [Color(hex: "285F51"), Color(hex: "45846E")], startPoint: .topLeading, endPoint: .bottomTrailing), in: .rect(cornerRadius: 30))
        }.buttonStyle(.plain)
    }
    private var cashFlowCard: some View {
        LedgerCard(title: "Cash flow") {
            HStack(alignment: .top, spacing: 20) {
                flowMetric("Money in", amount: store.summary.income, symbol: "arrow.down.left", color: LedgerTheme.income)
                Divider()
                flowMetric("Money out", amount: store.summary.spending, symbol: "arrow.up.right", color: LedgerTheme.expense)
            }.fixedSize(horizontal: false, vertical: true)
            HStack { Text("Net for this period").foregroundStyle(.secondary); Spacer(); MoneyText(amount: store.summary.income - store.summary.spending).fontWeight(.semibold) }.font(.subheadline)
        }
    }
    private func flowMetric(_ title: String, amount: Int64, symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol).font(.subheadline).foregroundStyle(color)
            MoneyText(amount: amount).font(.system(.title3, design: .rounded, weight: .semibold)).minimumScaleFactor(0.6).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var trendCard: some View {
        LedgerCard(title: "Spending pace") {
            if store.summary.transactions.isEmpty { emptyChart }
            else {
                Chart(store.summary.daily) { day in
                    AreaMark(x: .value("Day", day.date), y: .value("Spending", Double(day.amount) / 100))
                        .foregroundStyle(LinearGradient(colors: [LedgerTheme.accent.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Day", day.date), y: .value("Spending", Double(day.amount) / 100))
                        .foregroundStyle(LedgerTheme.accent).interpolationMethod(.monotone).lineStyle(.init(lineWidth: 2.5))
                }.chartYAxis(store.privacy == .hidden ? .hidden : .automatic)
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
                    .frame(height: 160).accessibilityHidden(store.privacy == .hidden)
                Text("Daily expenses for the selected period").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var categoriesCard: some View {
        LedgerCard(title: "Where it went") {
            if store.summary.categories.isEmpty { emptyChart }
            else {
                Chart(store.summary.categories) { category in
                    SectorMark(angle: .value("Spending", category.amount), innerRadius: .ratio(0.74), angularInset: 3)
                        .cornerRadius(4).foregroundStyle(Color(hex: category.color))
                        .accessibilityLabel(category.name).accessibilityValue(store.money(category.amount))
                }.frame(height: 190).chartLegend(.hidden).accessibilityHidden(store.privacy == .hidden)
                    .chartBackground { _ in VStack(spacing: 4) { Text("TOTAL SPENT").font(.caption2.weight(.semibold)).foregroundStyle(.secondary); MoneyText(amount: store.summary.spending).font(.headline) } }
                ForEach(store.summary.categories.prefix(5)) { total in
                    NavigationLink { TransactionListView(title: total.name, categoryID: total.categoryID, uncategorized: total.categoryID == nil) } label: {
                        HStack { Circle().fill(Color(hex: total.color)).frame(width: 8, height: 8); Text(total.name); Spacer(); MoneyText(amount: total.amount).foregroundStyle(.secondary); Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }.font(.subheadline)
                    }.buttonStyle(.plain)
                }
            }
        }
    }
    private var moneyFlowCard: some View {
        LedgerCard(title: "Money flow") {
            if store.summary.spending == 0 { emptyChart }
            else {
                MoneyFlowView(income: store.summary.income, spending: store.summary.spending, categories: store.summary.categories)
                Text(store.summary.spending > store.summary.income ? "Expenses exceed income in this period; the difference comes from your existing balance." : "Income flows into your spending categories, with the remainder left over.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var budgetCard: some View {
        LedgerCard(title: "Budget watch") {
            if store.progress.isEmpty { Text("Give your priorities a little space.").foregroundStyle(.secondary); Button("Create a budget", systemImage: "plus") { store.route = .budgets }.buttonStyle(.glass) }
            else {
                Text("Current budget cycles · all accounts").font(.caption).foregroundStyle(.secondary)
                ForEach(store.progress.prefix(3)) { item in
                    NavigationLink { BudgetDetailView(budget: item.budget) } label: { BudgetProgressRow(progress: item) }.buttonStyle(.plain)
                }
            }
        }
    }
    private var insightsCard: some View {
        LedgerCard(title: "A little perspective") {
            Label {
                if let top = store.summary.categories.first { Text("\(top.name) is your largest spending category for this period.") }
                else { Text("Your patterns will appear as you add transactions.") }
            } icon: { Image(systemName: "sparkles").foregroundStyle(LedgerTheme.accent) }
            if store.summary.income > 0 && store.privacy != .hidden {
                Text(store.summary.income > store.summary.spending ? "You have \(store.money(store.summary.income - store.summary.spending)) left from this period’s income." : "Your spending has reached this period’s income.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
    private var recentCard: some View {
        LedgerCard(title: "Recent activity") {
            if store.summary.transactions.isEmpty {
                ContentUnavailableView("A fresh page", systemImage: "tray", description: Text("Add a transaction or import a bank alert to get started."))
            } else {
                ForEach(Array(store.summary.transactions.prefix(5))) { tx in NavigationLink { TransactionDetailView(transaction: tx) } label: { TransactionRow(transaction: tx) }.buttonStyle(.plain) }
            }
        }
    }
    private var emptyChart: some View { Text("A clearer picture starts with your first transaction.").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 20) }
}

struct MoneyFlowView: View {
    @Environment(LedgerStore.self) private var store
    var income: Int64
    var spending: Int64
    var categories: [CategoryTotal]
    private var flows: [(String, Int64, Color)] {
        var values = categories.prefix(4).map { ($0.name, $0.amount, Color(hex: $0.color)) }
        let other = categories.dropFirst(4).reduce(Int64(0)) { $0 + $1.amount }
        if other > 0 { values.append(("Other expenses", other, .gray)) }
        if income > spending { values.append(("Left over", income - spending, LedgerTheme.income)) }
        return values
    }
    var body: some View {
        VStack(spacing: 14) {
            Canvas { context, size in
                let total = Double(max(income, spending)); guard total > 0 else { return }
                var y: CGFloat = 0
                for flow in flows {
                    let height = CGFloat(Double(flow.1) / total) * size.height
                    var path = Path(); path.move(to: CGPoint(x: 6, y: y))
                    path.addCurve(to: CGPoint(x: size.width - 6, y: y + 2), control1: CGPoint(x: size.width * 0.4, y: y), control2: CGPoint(x: size.width * 0.6, y: y + 2))
                    path.addLine(to: CGPoint(x: size.width - 6, y: y + max(3, height - 3)))
                    path.addCurve(to: CGPoint(x: 6, y: y + height), control1: CGPoint(x: size.width * 0.6, y: y + height - 3), control2: CGPoint(x: size.width * 0.4, y: y + height))
                    path.closeSubpath(); context.fill(path, with: .color(flow.2.opacity(0.45))); y += height
                }
            }.frame(height: 110).accessibilityHidden(true)
            ForEach(Array(flows.enumerated()), id: \.offset) { _, flow in
                HStack { Circle().fill(flow.2).frame(width: 7, height: 7); Text(flow.0); Spacer(); MoneyText(amount: flow.1) }.font(.caption)
            }
        }
    }
}
