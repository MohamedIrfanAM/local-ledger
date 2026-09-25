import SwiftUI
import LedgerCore

struct RootView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = 0
    var body: some View {
        @Bindable var store = store
        ZStack {
            if !store.loaded {
                VStack(spacing: 20) {
                    Image(systemName: "leaf.circle").font(.system(size: 64)).foregroundStyle(LedgerTheme.accent)
                    Text("Local Ledger").font(.largeTitle.bold())
                    if store.error == nil { ProgressView("Opening your ledger") }
                    else { Text("Your saved ledger has been preserved.").foregroundStyle(.secondary); Button("Try again") { Task { await store.load() } } }
                }
            } else if store.isLocked { lockScreen }
            else if store.state.accounts.isEmpty && store.privacy == .visible { WelcomeView() }
            else { tabs.id(store.privacy) }
            if scenePhase != .active {
                LedgerTheme.canvas.ignoresSafeArea()
                Label("Local Ledger", systemImage: "lock.shield").font(.title2.weight(.medium))
            }
        }
        .background(PrivacyShield(active: scenePhase != .active).frame(width: 0, height: 0))
        .task { await store.load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { store.lock() }
            if phase == .active { store.refreshSummary() }
        }
        .onOpenURL { store.open($0) }
        .alert("Local Ledger", isPresented: Binding(get: { store.error != nil && store.presentedSheets == 0 }, set: { if !$0 && store.presentedSheets == 0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
        .sheet(item: $store.route) { route in
          Group {
            if store.isLocked { Text("Unlock Local Ledger to continue.").padding() }
            else {
                switch route {
                case .add: TransactionEditor()
                case .importAlert: ImportAlertView()
                case .accounts: NavigationStack { AccountsView() }
                case .budgets: NavigationStack { BudgetsView() }
                }
            }
          }.ledgerSheet()
        }
    }
    private var tabs: some View {
        TabView(selection: $selectedTab) {
            Tab("Overview", systemImage: "square.grid.2x2", value: 0) { NavigationStack { DashboardView() } }
            Tab("Activity", systemImage: "list.bullet.rectangle", value: 1) { NavigationStack { ActivityView() } }
            Tab("Budgets", systemImage: "chart.pie", value: 2) { NavigationStack { BudgetsView() } }
            Tab("Settings", systemImage: "slider.horizontal.3", value: 3) { NavigationStack { SettingsView() } }
        }.tabBarMinimizeBehavior(.onScrollDown)
    }
    private var lockScreen: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.shield").font(.system(size: 64, weight: .light)).foregroundStyle(LedgerTheme.accent)
            Text("Just for you.").font(.largeTitle.weight(.semibold))
            Text("Unlock to return to your ledger.").foregroundStyle(.secondary)
            Button("Unlock ledger", systemImage: "faceid") { Task { await store.authenticate() } }
                .buttonStyle(.glassProminent).controlSize(.large)
        }.padding(28)
    }
}

struct WelcomeView: View {
    @Environment(LedgerStore.self) private var store
    @State private var addAccount = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    Image(systemName: "leaf.circle.fill").font(.system(size: 76, weight: .light)).foregroundStyle(LedgerTheme.accent).padding(.top, 44)
                    Text("Your money.\nA little clearer.").font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text("A quiet place for everyday finances.\nPrivate, offline, and entirely yours.").font(.title3).foregroundStyle(.secondary)
                    LedgerCard {
                        Label("Accounts, spending, and flexible budgets", systemImage: "chart.bar.xaxis")
                        Label("Your data stays on this device", systemImage: "lock.shield")
                        Label("No sign-up. No tracking. No cloud.", systemImage: "leaf")
                    }
                    Text("On iPhone, import bank alerts by pasting them or using a Shortcuts message automation. iOS does not give this app access to your Messages inbox.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Add your first account", systemImage: "plus") { addAccount = true }
                        .buttonStyle(.glassProminent).controlSize(.large).frame(maxWidth: .infinity)
                    Button("Take a look around", systemImage: "sparkles") { Task { await store.setPrivacy(.demo) } }
                        .buttonStyle(.glass).controlSize(.large).frame(maxWidth: .infinity)
                }.padding(26).frame(maxWidth: 620)
            }.background(LedgerTheme.canvas).sheet(isPresented: $addAccount) { AccountEditor().ledgerSheet() }
        }
    }
}
