import SwiftUI
import LedgerCore

struct SettingsView: View {
    @Environment(LedgerStore.self) private var store
    var body: some View {
        List {
            Section("Your ledger") {
                NavigationLink { AccountsView() } label: { Label("Accounts", systemImage: "building.columns") }
                NavigationLink { ClassificationView() } label: { Label("Categories & tags", systemImage: "tag") }
                NavigationLink { DashboardLayoutView() } label: { Label("Dashboard layout", systemImage: "rectangle.3.group") }
            }
            Section("Privacy") {
                Picker("Display", selection: Binding(get: { store.privacy }, set: { mode in Task { await store.setPrivacy(mode) } })) {
                    ForEach(PrivacyMode.allCases) { Text($0.rawValue.capitalized).tag($0) }
                }
                Toggle("Require Face ID or passcode", isOn: Binding(get: { store.state.preferences.appLock }, set: { value in Task { await store.toggleAppLock(value) } }))
                Text("Hidden and Demo use sample labels and charts. Editing and exports are disabled until Visible mode is restored.").font(.caption).foregroundStyle(.secondary)
            }
            Section("On your iPhone") {
                Toggle("Budget notifications", isOn: Binding(get: { store.state.preferences.budgetNotifications }, set: { value in Task { await store.toggleNotifications(value) } }))
                NavigationLink { IntegrationsGuide() } label: { Label("Shortcuts & widgets", systemImage: "square.stack.3d.up") }
                Button("Import a bank alert", systemImage: "text.bubble") { store.route = .importAlert }
                NavigationLink { CSVImportView() } label: { Label("Import CSV report", systemImage: "square.and.arrow.down") }.disabled(!store.canEdit)
                NavigationLink { ReportsView(embedded: true) } label: { Label("Export reports", systemImage: "square.and.arrow.up") }.disabled(!store.canExport)
            }
            Section("About") {
                NavigationLink { DiagnosticsView() } label: { Label("Import diagnostics", systemImage: "waveform.path.ecg") }
                NavigationLink { PrivacyInfoView() } label: { Label("Privacy & limitations", systemImage: "lock.shield") }
                LabeledContent("Bank registry", value: "\(store.registry?.banks.count ?? 0) banks")
                LabeledContent("Registry source date", value: store.registry?.published ?? "Unavailable")
                LabeledContent("Version", value: "0.1.0 · iOS preview")
            }
        }.navigationTitle("Settings")
    }
}
struct DashboardLayoutView: View {
    @Environment(LedgerStore.self) private var store
    var body: some View {
        List {
            Section { Text("Drag to reorder. Toggle modules to make this space your own.").font(.subheadline).foregroundStyle(.secondary) }
            ForEach(store.state.preferences.dashboardOrder) { module in
                Toggle(module.title, isOn: Binding(get: { !store.state.preferences.hiddenModules.contains(module) }, set: { visible in
                    Task { await store.setPreferences { if visible { $0.hiddenModules.remove(module) } else { $0.hiddenModules.insert(module) } } }
                }))
            }.onMove { source, destination in
                var order = store.state.preferences.dashboardOrder; order.move(fromOffsets: source, toOffset: destination); let updated = order
                Task { await store.setPreferences { $0.dashboardOrder = updated } }
            }
            Button("Restore default layout") { Task { await store.setPreferences { $0.dashboardOrder = DashboardModule.allCases; $0.hiddenModules = [] } } }
        }.navigationTitle("Dashboard layout").environment(\.editMode, .constant(.active))
    }
}
struct ClassificationView: View {
    @Environment(LedgerStore.self) private var store
    @State private var newCategory = false
    @State private var newTag = false
    var body: some View {
        List {
            if store.isPreview { PreviewBanner() }
            Section("Categories") {
                ForEach(store.presented.categories) { category in
                    NavigationLink { CategoryEditor(category: category) } label: { Label(category.name, systemImage: category.symbol).foregroundStyle(Color(hex: category.color)) }
                }
                Button("Add category", systemImage: "plus") { newCategory = true }
            }
            Section("Tags") {
                ForEach(store.presented.tags) { tag in NavigationLink { TagEditor(tag: tag) } label: { Label(tag.name, systemImage: "tag").foregroundStyle(Color(hex: tag.color)) } }
                Button("Add tag", systemImage: "plus") { newTag = true }
            }
        }.navigationTitle("Categories & tags")
            .sheet(isPresented: $newCategory) { NavigationStack { CategoryEditor() }.ledgerSheet() }
            .sheet(isPresented: $newTag) { NavigationStack { TagEditor() }.ledgerSheet() }
    }
}
private let palette = ["438B80", "D97D54", "6A89AD", "BF925B", "9581B7", "C4768C", "769EBB", "4F8B69", "88928B"]
struct CategoryEditor: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var category: LedgerCore.Category?
    @State private var name = ""
    @State private var color = "438B80"
    @State private var symbol = "square.grid.2x2"
    @State private var tags: Set<UUID> = []
    @State private var deleting = false
    var body: some View {
        Form {
            PreviewBanner()
            TextField("Category name", text: $name)
            ColorPickerRow(color: $color)
            Picker("Icon", selection: $symbol) { ForEach(["square.grid.2x2", "fork.knife", "house", "bag", "tram", "bolt", "heart", "play.rectangle", "arrow.down.left", "ellipsis", "airplane", "graduationcap"], id: \.self) { Label($0.replacingOccurrences(of: ".", with: " "), systemImage: $0).tag($0) } }
            Section("Tags inherited by this category") { TagSelection(selected: $tags) }
            if let category {
                NavigationLink("Category activity") { TransactionListView(title: category.name, categoryID: category.id) }
                Button("Delete category", role: .destructive) { deleting = true }.disabled(!store.canEdit)
            }
        }.navigationTitle(category == nil ? "New category" : "Edit category").navigationBarTitleDisplayMode(.inline)
            .toolbar { SaveToolbar {
                var updated = category ?? LedgerCore.Category(name: name); updated.name = name; updated.color = color; updated.symbol = symbol; updated.tagIDs = tags
                let saved = updated; if await store.commit({ try $0.saveCategory(saved) }) { dismiss() }
            } }
            .onAppear { if let category { name = category.name; color = category.color; symbol = category.symbol; tags = category.tagIDs } }
            .confirmationDialog("Delete this category and its budgets? Transactions will be kept.", isPresented: $deleting, titleVisibility: .visible) {
                Button("Delete category", role: .destructive) { if let id = category?.id { Task { if await store.commit({ $0.deleteCategory(id) }) { dismiss() } } } }
            }
    }
}
struct TagEditor: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var tag: LedgerTag?
    @State private var name = ""
    @State private var color = "438B80"
    @State private var deleting = false
    var body: some View {
        Form {
            PreviewBanner(); TextField("Tag name", text: $name); ColorPickerRow(color: $color)
            if let tag {
                NavigationLink("Tagged activity") { TransactionListView(title: tag.name, tagID: tag.id) }
                Button("Delete tag", role: .destructive) { deleting = true }.disabled(!store.canEdit)
            }
        }.navigationTitle(tag == nil ? "New tag" : "Edit tag").navigationBarTitleDisplayMode(.inline)
            .toolbar { SaveToolbar {
                var updated = tag ?? LedgerTag(name: name); updated.name = name; updated.color = color; let saved = updated
                if await store.commit({ try $0.saveTag(saved) }) { dismiss() }
            } }
            .onAppear { if let tag { name = tag.name; color = tag.color } }
            .confirmationDialog("Delete this tag and its budgets? Transactions will be kept.", isPresented: $deleting, titleVisibility: .visible) {
                Button("Delete tag", role: .destructive) { if let id = tag?.id { Task { if await store.commit({ $0.deleteTag(id) }) { dismiss() } } } }
            }
    }
}
struct ColorPickerRow: View {
    @Binding var color: String
    var body: some View {
        Picker("Color", selection: $color) {
            ForEach(Array(palette.enumerated()), id: \.element) { index, value in Label("Color \(index + 1)", systemImage: "circle.fill").foregroundStyle(Color(hex: value)).tag(value) }
        }
    }
}
struct DiagnosticsView: View {
    @Environment(LedgerStore.self) private var store
    private var report: String { store.isPreview ? "Demo diagnostic report\nimported | amount=true,direction=true,account=true,otp=false" : store.state.diagnosticReport() }
    var body: some View {
        ScrollView { Text(report).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding() }
            .navigationTitle("Diagnostics").toolbar { ShareLink(item: report) }
    }
}
struct PrivacyInfoView: View {
    var body: some View {
        List {
            Section("Private by design") {
                Text("No account, analytics, advertising SDK, network client, or cloud sync. Ledger files use complete iOS Data Protection and are excluded from iCloud and device backups.")
                Text("Bank alert bodies are processed in memory and discarded. Diagnostic events retain only parser flags for seven days, up to 120 events.")
                Text("Exported reports contain exact financial data. You choose where to save or share them. Uninstalling the app removes its local ledger.")
            }
            Section("Know the limits") {
                Text("iOS does not provide this app a Messages inbox scanner or Android-style SMS receiver. Import copied alerts or configure an explicit Shortcuts automation.")
                Text("One account per bank. Credit cards and pre-setup automatic activity are outside scope. Alerts and parsers can miss or misread transactions; reconcile with bank statements.")
                Text("The bank registry dates to June 2020 and can become stale. Sender matching is an allowlist, not cryptographic verification.")
                Text("This iOS port is a development preview. Physical-device testing and signing are required before distribution.")
            }
        }.navigationTitle("Privacy & limitations")
    }
}
struct IntegrationsGuide: View {
    var body: some View {
        List {
            Section("Shortcuts message automation") {
                Text("1. Open Shortcuts → Automation → New Automation → Message. Choose a bank sender or matching text.")
                Text("2. Add Local Ledger’s “Import bank alert” action. Set Sender to the bank header (for example AX-ICICIT-S), Message to the received message’s text, and Received at to its date.")
                Text("3. Test with one alert. The action opens Local Ledger and respects your app lock. iOS may require interaction; background delivery is not guaranteed.")
                Text("Use the original received date consistently: it participates in duplicate detection. Messages without a bank reference cannot be deduplicated reliably if you supply a different date each time.")
            }
            Section("Siri & Action button") { Text("Use “Add a transaction in Local Ledger” to open the entry sheet. You can assign the shortcut to your Action button or Control Center using the system Shortcuts control.") }
            Section("Widgets") { Text("Add the Local Ledger widget to your Home Screen or Lock Screen for quick entry and import. Widgets show no balances or transaction details.") }
            Section("Made for iOS") { Text("Native Liquid Glass navigation, Face ID or passcode, system sharing, Files import/export, keyboard shortcuts, Dynamic Type, VoiceOver, dark mode, haptics, and iPad layouts.") }
        }.navigationTitle("Shortcuts & widgets")
    }
}
