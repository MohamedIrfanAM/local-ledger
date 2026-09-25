import SwiftUI
import WidgetKit

struct LedgerEntry: TimelineEntry { let date: Date }
struct LedgerProvider: TimelineProvider {
    func placeholder(in context: Context) -> LedgerEntry { .init(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (LedgerEntry) -> Void) { completion(.init(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<LedgerEntry>) -> Void) { completion(.init(entries: [.init(date: .now)], policy: .never)) }
}
struct LedgerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: LedgerEntry
    var body: some View {
        Group {
            if family == .accessoryCircular {
                Image(systemName: "plus").font(.title2).widgetURL(URL(string: "localledger://add"))
            } else if family == .accessoryRectangular {
                Label("Add to your ledger", systemImage: "plus.circle").widgetURL(URL(string: "localledger://add"))
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Local Ledger", systemImage: "leaf").font(.headline)
                    Text("A little clearer.").font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    HStack {
                        Link(destination: URL(string: "localledger://add")!) { Label("Add", systemImage: "plus.circle.fill").font(.subheadline.weight(.semibold)) }
                        if family == .systemMedium {
                            Spacer(); Link(destination: URL(string: "localledger://import")!) { Label("Import", systemImage: "text.bubble") }
                            Spacer(); Link(destination: URL(string: "localledger://budgets")!) { Label("Budgets", systemImage: "chart.pie") }
                        }
                    }
                }.widgetURL(URL(string: "localledger://add"))
            }
        }.containerBackground(for: .widget) { Color(red: 0.16, green: 0.37, blue: 0.31).opacity(0.12) }
    }
}
@main struct LocalLedgerWidget: Widget {
    let kind = "LocalLedgerQuickEntry"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LedgerProvider()) { LedgerWidgetView(entry: $0) }
            .configurationDisplayName("A little clearer")
            .description("Quick entry and bank alert import. Your financial details stay private.")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}
