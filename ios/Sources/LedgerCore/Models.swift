import Foundation

public enum LedgerError: Error, LocalizedError, Equatable {
    case invalidAmount, invalidName, accountExists, accountMissing, invalidReference, corruptStore, unsupportedVersion, readOnly
    public var errorDescription: String? {
        switch self {
        case .invalidAmount: "Enter a valid amount with at most two decimal places."
        case .invalidName: "Enter a name between 1 and 80 characters."
        case .accountExists: "This bank already has an account in your ledger."
        case .accountMissing: "Add this bank in Accounts before importing its alerts."
        case .invalidReference: "The selected category, tag, merchant, or account is no longer available."
        case .corruptStore: "The ledger could not be read. Your saved file has been preserved."
        case .unsupportedVersion: "This ledger was saved by a newer version of Local Ledger."
        case .readOnly: "Return to Visible mode and unlock your ledger to make changes."
        }
    }
}

/// Money is always integer paise. The limit leaves ample headroom for aggregate arithmetic.
public enum Money {
    public static let maximum: Int64 = 9_000_000_000_000
    public static func parse(_ text: String, allowNegative: Bool = false) throws -> Int64 {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "")
        guard value.range(of: allowNegative ? #"^-?\d+(?:\.\d{1,2})?$"# : #"^\d+(?:\.\d{1,2})?$"#, options: .regularExpression) != nil,
              let decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) else { throw LedgerError.invalidAmount }
        let minor = decimal * 100
        guard minor <= Decimal(maximum), minor >= Decimal(allowNegative ? -maximum : 1) else { throw LedgerError.invalidAmount }
        return NSDecimalNumber(decimal: minor).int64Value
    }
    public static func decimal(_ minor: Int64) -> String {
        String(format: "%@%lld.%02lld", minor < 0 ? "-" : "", abs(minor) / 100, abs(minor) % 100)
    }
    public static func formatted(_ minor: Int64) -> String {
        (Decimal(minor) / 100).formatted(.currency(code: "INR").locale(Locale(identifier: "en_IN")))
    }
}

public struct BankDefinition: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var headers: [String]
    public var observedHeaders: [String]?
}

public struct Account: Codable, Identifiable, Equatable, Sendable {
    public var id: String { bankID }
    public var bankID: String
    public var bankName: String
    public var openingBalance: Int64
    public var createdAt: Date
    public init(bankID: String, bankName: String, openingBalance: Int64, createdAt: Date = .now) {
        self.bankID = bankID; self.bankName = bankName; self.openingBalance = openingBalance; self.createdAt = createdAt
    }
}
public enum Direction: String, Codable, CaseIterable, Identifiable, Sendable {
    case debit = "DEBIT", credit = "CREDIT"
    public var id: String { rawValue }
    public var title: String { self == .debit ? "Expense" : "Income" }
}
public enum Origin: String, Codable, Sendable { case alert = "SMS", manual = "MANUAL", csv = "CSV" }

public struct LedgerTransaction: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID = UUID()
    public var bankID: String
    public var occurredAt: Date
    public var receivedAt: Date = .now
    public var amount: Int64
    public var direction: Direction
    public var merchant: String
    public var merchantKey: String
    public var categoryID: UUID?
    public var tagIDs: Set<UUID> = []
    public var note: String = ""
    public var origin: Origin = .manual
    public var affectsBalance: Bool = true
    public var reference: String?
    public var senderHeader: String = ""
    public var sourceKey: String?
    public var parserID: String = "manual"
    public var confidence: Int = 100
    public init(bankID: String, occurredAt: Date = .now, amount: Int64, direction: Direction, merchant: String,
                categoryID: UUID? = nil, tagIDs: Set<UUID> = [], note: String = "", affectsBalance: Bool = true) {
        self.bankID = bankID; self.occurredAt = occurredAt; self.amount = amount; self.direction = direction
        self.merchant = merchant; self.merchantKey = TransactionParser.normalizeMerchant(merchant)
        self.categoryID = categoryID; self.tagIDs = tagIDs; self.note = note; self.affectsBalance = affectsBalance
    }
}

public struct Category: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID = UUID()
    public var name: String
    public var color: String
    public var symbol: String
    public var tagIDs: Set<UUID> = []
    public init(name: String, color: String = "738A80", symbol: String = "square.grid.2x2", tagIDs: Set<UUID> = []) {
        self.name = name; self.color = color; self.symbol = symbol; self.tagIDs = tagIDs
    }
    public static var defaults: [Category] { [
        .init(name: "Food", color: "D97D54", symbol: "fork.knife"),
        .init(name: "Rent", color: "6A89AD", symbol: "house"),
        .init(name: "Shopping", color: "BF925B", symbol: "bag"),
        .init(name: "Transport", color: "438B80", symbol: "tram"),
        .init(name: "Utilities", color: "9581B7", symbol: "bolt"),
        .init(name: "Health", color: "C4768C", symbol: "heart"),
        .init(name: "Entertainment", color: "769EBB", symbol: "play.rectangle"),
        .init(name: "Income", color: "4F8B69", symbol: "arrow.down.left"),
        .init(name: "Other", color: "88928B", symbol: "ellipsis")
    ] }
}
public struct LedgerTag: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID = UUID()
    public var name: String
    public var color: String
    public init(name: String, color: String = "438B80") { self.name = name; self.color = color }
}
public struct MerchantRule: Codable, Identifiable, Equatable, Sendable {
    public var id: String { merchantKey }
    public var merchantKey: String
    public var nickname: String
    public var categoryID: UUID?
    public var tagIDs: Set<UUID>
    public init(merchantKey: String, nickname: String, categoryID: UUID? = nil, tagIDs: Set<UUID> = []) {
        self.merchantKey = merchantKey; self.nickname = nickname; self.categoryID = categoryID; self.tagIDs = tagIDs
    }
}
public enum BudgetScope: String, Codable, CaseIterable, Identifiable, Sendable {
    case category, merchant, tag
    public var id: String { rawValue }
}
public enum BudgetPeriod: String, Codable, CaseIterable, Identifiable, Sendable {
    case day, week, month, year
    public var id: String { rawValue }
    public func interval(at date: Date, calendar: Calendar = .current) -> DateInterval {
        let component: Calendar.Component = switch self { case .day: .day; case .week: .weekOfYear; case .month: .month; case .year: .year }
        return calendar.dateInterval(of: component, for: date)!
    }
}
public struct Budget: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID = UUID()
    public var label: String
    public var scope: BudgetScope
    public var scopeKey: String
    public var amount: Int64
    public var period: BudgetPeriod
    public var alertPercent: Int
    public var enabled: Bool
    public init(label: String, scope: BudgetScope, scopeKey: String, amount: Int64,
                period: BudgetPeriod = .month, alertPercent: Int = 80, enabled: Bool = true) {
        self.label = label; self.scope = scope; self.scopeKey = scopeKey; self.amount = amount
        self.period = period; self.alertPercent = alertPercent; self.enabled = enabled
    }
}
public enum BudgetStatus: String, Sendable { case onTrack = "On track", watch = "Watch", projectedOver = "Projected over", over = "Over budget" }
public struct BudgetProgress: Identifiable, Sendable {
    public var id: UUID { budget.id }
    public var budget: Budget
    public var spent: Int64
    public var projected: Int64
    public var elapsed: Double
    public var interval: DateInterval
    public var status: BudgetStatus
    public var fraction: Double { Double(spent) / Double(budget.amount) }
    public var cycleKey: String { "\(id.uuidString):\(Int(interval.start.timeIntervalSince1970))" }
}
public enum PrivacyMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case visible, hidden, demo
    public var id: String { rawValue }
}
public enum DashboardModule: String, Codable, CaseIterable, Identifiable, Sendable {
    case balance, cashFlow, trend, categories, moneyFlow, budgets, insights, recent
    public var id: String { rawValue }
    public var title: String {
        switch self { case .balance: "Your balance"; case .cashFlow: "Cash flow"; case .trend: "Spending pace"
        case .categories: "Where it went"; case .moneyFlow: "Money flow"; case .budgets: "Budget watch"
        case .insights: "A little perspective"; case .recent: "Recent activity" }
    }
}
public struct Preferences: Codable, Equatable, Sendable {
    public var privacy: PrivacyMode = .visible
    public var dashboardOrder: [DashboardModule] = DashboardModule.allCases
    public var hiddenModules: Set<DashboardModule> = []
    public var appLock: Bool = false
    public var budgetNotifications: Bool = false
    public init() {}
}
public enum ImportOutcome: String, Codable, Sendable {
    case imported, duplicate, unknownSender, promotional, accountMissing, beforeTracking, notParsed
    public var message: String {
        switch self {
        case .imported: "Added to your ledger."
        case .duplicate: "This alert is already in your ledger."
        case .unknownSender: "Sender is not in the bank registry. Check the original sender header."
        case .promotional: "Promotional alerts are not imported."
        case .accountMissing: "Add this bank in Accounts first."
        case .beforeTracking: "This alert predates the account’s opening balance."
        case .notParsed: "No supported completed transaction found. You can add it manually."
        }
    }
}
public struct DiagnosticEvent: Codable, Identifiable, Sendable {
    public var id: UUID = UUID()
    public var date: Date
    public var outcome: ImportOutcome
    public var signals: String
}
public struct LedgerState: Codable, Sendable {
    public var schemaVersion: Int = 1
    public var revision: UInt64 = 0
    public var accounts: [Account] = []
    public var transactions: [LedgerTransaction] = []
    public var categories: [Category] = Category.defaults
    public var tags: [LedgerTag] = []
    public var merchants: [MerchantRule] = []
    public var budgets: [Budget] = []
    public var diagnostics: [DiagnosticEvent] = []
    public var alertedCycles: Set<String> = []
    public var preferences = Preferences()
    public init() {}
}
public enum SortOrder: String, CaseIterable, Identifiable, Sendable {
    case newest = "Newest first", oldest = "Oldest first", largest = "Largest first", merchant = "Merchant"
    public var id: String { rawValue }
}
public struct LedgerFilter: Equatable, Sendable {
    public var bankID: String?
    public var categoryID: UUID?
    public var merchantKey: String?
    public var tagID: UUID?
    public var direction: Direction?
    public var start: Date?
    public var end: Date?
    public var search: String = ""
    public var sort: SortOrder = .newest
    public init() {}
}
