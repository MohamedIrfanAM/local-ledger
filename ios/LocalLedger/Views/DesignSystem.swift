import SwiftUI
import LedgerCore

enum LedgerTheme {
    static let accent = Color(hex: "347864")
    static let income = Color(hex: "438B70")
    static let expense = Color(hex: "C47B56")
    static let canvas = Color(uiColor: .systemGroupedBackground)
}
extension Color {
    init(hex: String) {
        let number = UInt64(hex, radix: 16) ?? 0x738A80
        self.init(red: Double((number >> 16) & 255) / 255, green: Double((number >> 8) & 255) / 255, blue: Double(number & 255) / 255)
    }
}
struct LedgerCard<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let title { Text(title).font(.headline).foregroundStyle(.secondary) }
            content
        }
        .padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 28))
    }
}
struct MoneyText: View {
    @Environment(LedgerStore.self) private var store
    var amount: Int64
    var body: some View { Text(store.money(amount)).monospacedDigit().contentTransition(.numericText()).privacySensitive() }
}
struct CategoryIcon: View {
    var category: LedgerCore.Category?
    var body: some View {
        Image(systemName: category?.symbol ?? "arrow.left.arrow.right")
            .font(.system(size: 18, weight: .medium)).foregroundStyle(Color(hex: category?.color ?? "738A80"))
            .frame(width: 44, height: 44).background(Color(hex: category?.color ?? "738A80").opacity(0.12), in: .rect(cornerRadius: 15))
            .accessibilityHidden(true)
    }
}
struct TransactionRow: View {
    @Environment(LedgerStore.self) private var store
    var transaction: LedgerTransaction
    var body: some View {
        HStack(spacing: 13) {
            CategoryIcon(category: store.presented.category(for: transaction))
            VStack(alignment: .leading, spacing: 4) {
                Text(store.presented.merchantName(for: transaction)).font(.body.weight(.medium)).lineLimit(1)
                Text("\(store.presented.category(for: transaction)?.name ?? "Uncategorized") · \(transaction.occurredAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            Text((transaction.direction == .credit ? "+" : "−") + store.money(transaction.amount))
                .font(.subheadline.weight(.semibold)).monospacedDigit()
                .foregroundStyle(transaction.direction == .credit ? LedgerTheme.income : Color.primary)
                .lineLimit(1).minimumScaleFactor(0.7).privacySensitive()
        }.padding(.vertical, 5).accessibilityElement(children: .combine)
    }
}
struct PreviewBanner: View {
    @Environment(LedgerStore.self) private var store
    var body: some View {
        if store.isPreview {
            Label(store.privacy == .demo ? "Demo · sample data only" : "Hidden · sample labels and charts", systemImage: store.privacy == .demo ? "sparkles" : "eye.slash")
                .font(.caption.weight(.medium)).frame(maxWidth: .infinity).padding(10)
                .background(LedgerTheme.accent.opacity(0.1), in: .capsule)
        }
    }
}
struct SaveToolbar: ToolbarContent {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var title: String = "Save"
    var action: () async -> Void
    var body: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel", role: .cancel) { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
            Button(title, systemImage: "checkmark") { Task { await action() } }.disabled(!store.canEdit)
        }
    }
}

private struct LedgerSheetErrors: ViewModifier {
    @Environment(LedgerStore.self) private var store
    @State private var level: Int?
    func body(content: Content) -> some View {
        content
            .onAppear { if level == nil { store.presentedSheets += 1; level = store.presentedSheets } }
            .onDisappear { if level != nil { store.presentedSheets = max(0, store.presentedSheets - 1); level = nil } }
            .alert("Local Ledger", isPresented: Binding(get: { store.error != nil && level == store.presentedSheets }, set: { if !$0 { store.error = nil } })) {
                Button("OK") { store.error = nil }
            } message: { Text(store.error ?? "") }
    }
}
extension View {
    func ledgerSheet() -> some View { modifier(LedgerSheetErrors()) }
}
