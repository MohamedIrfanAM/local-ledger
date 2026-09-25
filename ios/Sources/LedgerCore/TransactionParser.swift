import Foundation
import CryptoKit

public struct ParsedTransaction: Sendable {
    public var amount: Int64
    public var direction: Direction
    public var occurredAt: Date
    public var merchant: String
    public var reference: String?
    public var parserID: String
    public var confidence: Int
    public var usedReceivedTime: Bool
}

/// A direct port of the Android conservative parser and its six reviewed profiles.
public enum TransactionParser {
    private static let amountPattern = Pattern(#"(?:₹|(?i:rs\.?|inr))\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)"#)
    private static let directionAmountPattern = Pattern(#"(?i)\b(?:debited|credited)\s+(?:by|for|with)?\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)"#)
    private static let creditPattern = Pattern(#"(?i)\b(credited|received|deposited|refund(?:ed)?|reversal|reversed|cashback|cr)\b"#)
    private static let debitPattern = Pattern(#"(?i)\b(debited|spent|paid|purchase(?:d)?|withdrawn|sent|transferred|dr)\b"#)
    private static let accountContextPattern = Pattern(#"(?i)\b(a/?c|acct|account)\b"#)
    private static let failurePattern = Pattern(#"(?i)\b(declined|failed|unsuccessful|could not be processed|cancelled)\b"#)
    private static let upcomingPattern = Pattern(#"(?i)\b(?:will|would|shall)\s+(?:be\s+)?(?:debited|deducted|charged|auto[- ]?debited)|\b(?:scheduled for|due on|is due)\b"#)
    private static let otpPattern = Pattern(#"(?i)(?:\botp\s*:?\s*\d{3,8}\b)|(?:\b(?:otp|one[- ]time password|verification code)\b.{0,60}?(?:is|:)\s*\d{3,8}\b)|(?:\b\d{3,8}\s+(?:is\s+)?(?:the\s+|your\s+|an?\s+)?(?:otp|one[- ]time password|verification code)\b)|(?:\b(?:use|enter)\s+(?:otp|one[- ]time password)\s*:?\s*\d{3,8}\b)"#)
    private static let nonTransactionPattern = Pattern(#"(?i)\b(available credit limit|payment due|statement generated|offer|apply now|pre-approved|eligible for|instant loan|discount|shop now|buy now|lucky draw|you have won|spend summary)\b|\b(?:flat|up to|upto)\s+(?:rs\.?|inr|₹)|\bget\s+(?:a\s+)?cashback\b"#)
    private static let unsupportedInstrumentPattern = Pattern(#"(?i)\b(credit card|card account|card ending|cc ending)\b"#)
    private static let referencePatterns: [Pattern] = [
        Pattern(#"(?i)\bupi(?:\s+ref\.?)?[: ]+([a-z]{0,5}[0-9]{8,18})\b"#),
        Pattern(#"(?i)\bref(?:no|erence)?[.: -]*([a-z]{0,5}[0-9]{8,18})\b"#),
        Pattern(#"(?i)\butr(?:\s+(?:no|number))?[.: -]*([a-z]{0,5}[0-9]{8,18})\b"#),
    ]
    private static let balanceClausePatterns: [Pattern] = [
        Pattern(#"(?i)\b(?:avl|avbl|available|total|updated|remaining)\.?\s*(?:credit\s+)?(?:bal(?:ance)?|lmt|limit)\b[^0-9\n]{0,30}(?:rs\.?|inr|₹)?\s*[0-9][0-9,]*(?:\.[0-9]{1,2})?"#),
        Pattern(#"(?i)\b(?:balance|credit\s+limit)\s*(?:is|:)[^0-9\n]{0,20}(?:rs\.?|inr|₹)?\s*[0-9][0-9,]*(?:\.[0-9]{1,2})?"#),
        Pattern(#"(?i)\bbal(?:ance)?\s*(?:is|:)?\s*(?:rs\.?|inr|₹)\s*[0-9][0-9,]*(?:\.[0-9]{1,2})?"#),
    ]
    private static let merchantPatterns: [Pattern] = [
        Pattern(#"(?i);\s*(?:to\s+)?([a-z0-9][a-z0-9@._&+*/ -]{1,47}?)\s+credited\b"#),
        Pattern(#"(?i)\btrf\s+to\s+([a-z0-9][a-z0-9@._&+*/ -]{1,47}?)(?=\s+ref(?:no)?\b|[.;,]|$)"#),
        Pattern(#"(?i)\bfrom\s+(?:upi\s+id\s*)?([a-z0-9._-]+@[a-z0-9._-]+)"#),
        Pattern(#"(?i)\b(?:paid|sent|transferred)\s+(?:to\s+)?([a-z0-9][a-z0-9@._&+*/ -]{1,47}?)(?=\s+(?:on|via|using|ref|upi|txn)\b|[.;,]|$)"#),
        Pattern(#"(?i)\b(?:at|to|towards|info[: -])\s*([a-z0-9][a-z0-9@._&+*/ -]{1,47}?)(?=\s+(?:on|via|using|ref|upi|avl|available|balance|txn|transaction|from)\b|[.;,]|$)"#),
        Pattern(#"(?i)\b(?:vpa|upi id)[: -]+([a-z0-9._-]+@[a-z0-9._-]+)"#),
    ]
    private static let templates: [Template] = [
        Template(id: "icici-account-debit-v1", bank: "icici-bank", direction: .debit, pattern: Pattern(#"(?i)\bacct\s+\S+\s+debited\s+for\s+(?:rs\.?|inr|₹)\s*(?<amount>[0-9][0-9,]*(?:\.[0-9]{1,2})?).*?;\s*(?<merchant>[a-z0-9][a-z0-9@._&+*/ -]{1,60}?)\s+credited\b"#)),
        Template(id: "icici-salary-credit-v1", bank: "icici-bank", direction: .credit, pattern: Pattern(#"(?i)\bacc(?:t)?\s+\S+\s+is\s+credited\s+with\s+salary\s+of\s+(?:rs\.?|inr|₹)\s*(?<amount>[0-9][0-9,]*(?:\.[0-9]{1,2})?)"#)),
        Template(id: "dcb-upi-debit-v1", bank: "dcb-bank", direction: .debit, pattern: Pattern(#"(?i)^inr\s*(?<amount>[0-9][0-9,]*(?:\.[0-9]{1,2})?)\s+debited\s+dcb\s+a/?c\s+\S+;\s*to\s+(?<merchant>[^;]{2,64});"#)),
        Template(id: "dcb-upi-credit-v1", bank: "dcb-bank", direction: .credit, pattern: Pattern(#"(?i)^inr\s*(?<amount>[0-9][0-9,]*(?:\.[0-9]{1,2})?)\s+credited\s+to\s+your\s+dcb\s+bank\s+a/?c\s+\S+\s+from\s+upi\s+id\s+(?<merchant>[a-z0-9._-]+@[a-z0-9._-]+)"#)),
        Template(id: "sbi-upi-debit-v1", bank: "state-bank-of-india", direction: .debit, pattern: Pattern(#"(?i)\ba/?c\s+\S+\s+debited\s+by\s+(?<amount>[0-9][0-9,]*(?:\.[0-9]{1,2})?).*?\btrf\s+to\s+(?<merchant>.+?)\s+refno\s*(?<reference>[0-9]{8,18})"#)),
        Template(id: "sbi-upi-credit-v1", bank: "state-bank-of-india", direction: .credit, pattern: Pattern(#"(?i)\ba/?c\s+\S+\s+has\s+credit\s+for\s+.*?\bof\s+(?:rs\.?|inr|₹)\s*(?<amount>[0-9][0-9,]*(?:\.[0-9]{1,2})?)"#)),
    ]

    public static func parse(_ body: String, receivedAt: Date, bankID: String? = nil,
                             timeZone: TimeZone = .current) -> ParsedTransaction? {
        guard body.utf8.count <= 16_384 else { return nil }
        let compact = canonicalBody(body)
        guard ![unsupportedInstrumentPattern, otpPattern, failurePattern, upcomingPattern, nonTransactionPattern]
            .contains(where: { $0.has(compact) }) else { return nil }
        let template = templates.first { $0.bank == bankID && $0.pattern.has(compact) }
        let account = accountContextPattern.has(compact)
        let credit = creditPattern.has(compact) || (account && Pattern(#"(?i)\bcredit\b"#).has(compact))
        let debit = debitPattern.has(compact) || (account && Pattern(#"(?i)\bdebit\b"#).has(compact))
        guard credit || debit || template != nil else { return nil }
        let masked = balanceClausePatterns.reduce(compact) { $1.replacing($0, with: " ") }
        guard let amountText = template?.pattern.group(compact, name: "amount") ?? amountPattern.group(masked) ?? directionAmountPattern.group(masked),
              let amount = try? Money.parse(amountText) else { return nil }
        let direction = template?.direction ?? (Pattern(#"(?i)\b(refund(?:ed)?|reversal|reversed|cashback)\b"#).has(compact) ? .credit : (debit ? .debit : .credit))
        let merchant = cleanMerchant(template?.pattern.group(compact, name: "merchant")) ??
            merchantPatterns.lazy.compactMap { cleanMerchant($0.group(compact)) }.first ??
            (direction == .credit ? "Incoming transfer" : "Digital payment")
        let parsedDate = parseDate(compact, receivedAt: receivedAt, timeZone: timeZone)
        return ParsedTransaction(amount: amount, direction: direction, occurredAt: parsedDate ?? receivedAt,
            merchant: merchant, reference: template?.pattern.group(compact, name: "reference") ?? referencePatterns.lazy.compactMap { $0.group(compact) }.first,
            parserID: template?.id ?? "generic-v2", confidence: template != nil ? 95 : (merchant.contains("transfer") || merchant.contains("payment") ? 60 : 75),
            usedReceivedTime: parsedDate == nil)
    }

    public static func profileIDs(bankID: String) -> [String] { templates.filter { $0.bank == bankID }.map(\.id) }
    public static func normalizeMerchant(_ value: String) -> String {
        let key = Pattern(#"[^a-z0-9@]+"#).replacing(value.lowercased(), with: " ").trimmingCharacters(in: .whitespaces)
        return key.isEmpty ? "unknown" : key
    }
    public static func canonicalBody(_ body: String) -> String {
        Pattern(#"\s+"#).replacing(body, with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    /// Date remains part of the key so genuinely repeated reference-free payments can coexist.
    public static func sourceKey(sender: String, body: String, receivedAt: Date) -> String {
        fingerprint("\(BankRegistry.normalize(sender))\u{0}\(canonicalBody(body))\u{0}\(Int64(receivedAt.timeIntervalSince1970 * 1000))")
    }
    public static func fingerprint(_ value: String) -> String { SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined() }
    public static func diagnosticSignals(_ body: String) -> String {
        let compact = canonicalBody(String(body.prefix(16_384)))
        return [("amount", amountPattern.has(compact) || directionAmountPattern.has(compact)),
                ("direction", creditPattern.has(compact) || debitPattern.has(compact)),
                ("account", accountContextPattern.has(compact)), ("otp", otpPattern.has(compact)),
                ("failed", failurePattern.has(compact)), ("upcoming", upcomingPattern.has(compact)),
                ("nonTransaction", nonTransactionPattern.has(compact)), ("unsupportedInstrument", unsupportedInstrumentPattern.has(compact))]
            .map { "\($0.0)=\($0.1)" }.joined(separator: ",")
    }
    private static func cleanMerchant(_ value: String?) -> String? {
        guard let text = value?.trimmingCharacters(in: CharacterSet(charactersIn: " -:.,;")), text.count >= 2 else { return nil }
        return String(text.prefix(64))
    }
    private static func parseDate(_ body: String, receivedAt: Date, timeZone: TimeZone) -> Date? {
        let pattern = Pattern(#"(?i)\b(\d{1,2}[-/]\d{1,2}[-/](?:20)?\d{2}|\d{1,2}-[a-z]{3}-(?:20)?\d{2}|\d{1,2}[a-z]{3}(?:20)?\d{2})(?:[ ,T]+(\d{1,2}:\d{2}(?::\d{2})?))?\b"#)
        guard let dateText = pattern.group(body) else { return nil }
        let timeText = pattern.group(body, index: 2)
        let formats = ["d/M/yyyy", "d/M/yy", "d-M-yyyy", "d-M-yy", "d-MMM-yyyy", "d-MMM-yy", "dMMMyyyy", "dMMMyy"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.isLenient = false
        formatter.twoDigitStartDate = Date(timeIntervalSince1970: 946_684_800)
        let fourDigitYear = dateText.range(of: #"\d{4}$"#, options: .regularExpression) != nil
        for format in formats where format.contains("yyyy") == fourDigitYear {
            formatter.dateFormat = format + (timeText == nil ? "" : (timeText!.count > 5 ? " H:mm:ss" : " H:mm"))
            if let parsed = formatter.date(from: dateText + (timeText.map { " " + $0 } ?? "")) {
                guard timeText == nil else { return parsed }
                var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
                let time = calendar.dateComponents([.hour, .minute, .second], from: receivedAt)
                return calendar.date(bySettingHour: time.hour!, minute: time.minute!, second: time.second!, of: parsed)
            }
        }
        return nil
    }
    private struct Template: Sendable { let id: String; let bank: String; let direction: Direction; let pattern: Pattern }
}

private struct Pattern: Sendable {
    let regex: NSRegularExpression
    init(_ expression: String) { regex = try! NSRegularExpression(pattern: expression) }
    func has(_ text: String) -> Bool { regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil }
    func group(_ text: String, index: Int = 1, name: String? = nil) -> String? {
        guard let result = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        let nsRange = name.map { result.range(withName: $0) } ?? result.range(at: index)
        guard let range = Range(nsRange, in: text) else { return nil }
        return String(text[range])
    }
    func replacing(_ text: String, with replacement: String) -> String {
        regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: replacement)
    }
}
