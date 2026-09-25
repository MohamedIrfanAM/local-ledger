import SwiftUI
import LedgerCore

@main
struct LocalLedgerApp: App {
    @State private var store = LedgerStore.shared
    var body: some Scene {
        WindowGroup { RootView().environment(store).tint(LedgerTheme.accent) }
        .commands {
            CommandGroup(after: .newItem) {
                Button("New transaction") { store.route = .add }.keyboardShortcut("n")
                Button("Import bank alert") { store.route = .importAlert }.keyboardShortcut("i", modifiers: [.command, .shift])
            }
        }
    }
}
