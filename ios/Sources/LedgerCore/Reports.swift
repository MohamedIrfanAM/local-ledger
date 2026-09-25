import Foundation

public enum CSVError: Error, LocalizedError {
    case malformed, missingColumns, invalidRow(Int), unknownBank(Int)
    public var errorDescription: String? {
        switch self {
        case .malformed: "This CSV is malformed or exceeds the 20 MB import limit."
        case .missingColumns: "Choose a Local Ledger CSV export with date, direction, amount_inr, bank, and merchant columns."
        case .invalidRow(let row): "Row \(row) contains an invalid date, amount, direction, or merchant. Nothing was imported."
        case .unknownBank(let row): "Add the bank used in row \(row) to Accounts first. Nothing was imported."
        }
    }
}

public enum LedgerCSV {
    public static func export(state: LedgerState, transactions: [LedgerTransaction]) -> String {
        let header = "date,direction,amount_inr,bank,merchant,official_merchant,category,tags,reference,source,affects_balance,note,transaction_id"
        return header + "\r\n" + transactions.map { tx in
            [tx.occurredAt.ISO8601Format(), tx.direction.rawValue, Money.decimal(tx.amount),
             state.accounts.first { $0.bankID == tx.bankID }?.bankName ?? tx.bankID,
             state.merchantName(for: tx), tx.merchant, state.category(for: tx)?.name ?? "Uncategorized",
             state.tags.filter { state.effectiveTags(for: tx).contains($0.id) }.map(\.name).sorted().joined(separator: "|"),
             tx.reference ?? "", tx.origin.rawValue, String(tx.affectsBalance), tx.note, tx.id.uuidString].map(escape).joined(separator: ",")
        }.joined(separator: "\r\n") + "\r\n"
    }
    public static func escape(_ field: String) -> String {
        let leading = field.drop(while: { $0 == " " })
        let safe = leading.first.map { "=+-@\t\r\n".contains($0) } == true ? "'" + field : field
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    public static func rows(_ input: String) throws -> [[String]] {
        guard input.utf8.count <= 20_000_000 else { throw CSVError.malformed }
        let text = input.replacingOccurrences(of: "\u{FEFF}", with: "")
        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false, closed = false
        let chars = Array(text); var i = 0
        while i < chars.count {
            let c = chars[i]
            if quoted {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" { field.append("\""); i += 1 }
                    else { quoted = false; closed = true }
                } else { field.append(c) }
            } else {
                if c == "," { row.append(field); field = ""; closed = false }
                else if c == "\n" || c == "\r" || c == "\r\n" {
                    row.append(field); if row.contains(where: { !$0.isEmpty }) { rows.append(row) }; row = []; field = ""; closed = false
                    if c == "\r", i + 1 < chars.count, chars[i + 1] == "\n" { i += 1 }
                } else if c == "\"", field.isEmpty, !closed { quoted = true }
                else { guard !closed && c != "\"" else { throw CSVError.malformed }; field.append(c) }
            }
            i += 1
        }
        guard !quoted else { throw CSVError.malformed }
        row.append(field); if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
        return rows
    }
    /// Imports are staged on a copy and committed only if every row validates.
    @discardableResult
    public static func importReport(_ text: String, into state: inout LedgerState, affectsBalances: Bool = false) throws -> Int {
        let rows = try rows(text)
        guard let header = rows.first else { throw CSVError.missingColumns }
        let required = ["date", "direction", "amount_inr", "bank", "merchant"]
        guard required.allSatisfy(header.contains), Set(header).count == header.count else { throw CSVError.missingColumns }
        var next = state, imported = 0
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd HH:mm"; formatter.isLenient = false
        for (offset, row) in rows.dropFirst().enumerated() {
            let number = offset + 2
            guard row.count == header.count else { throw CSVError.invalidRow(number) }
            let values = Dictionary(uniqueKeysWithValues: zip(header, row))
            func value(_ key: String) -> String {
                let text = values[key] ?? ""
                if text.first == "'", text.dropFirst().first.map({ "=+-@\t\r\n ".contains($0) }) == true { return String(text.dropFirst()) }
                return text
            }
            guard let amount = try? Money.parse(value("amount_inr")), let direction = Direction(rawValue: value("direction")),
                  let date = (try? Date(value("date"), strategy: .iso8601)) ?? formatter.date(from: value("date")),
                  !value("merchant").isEmpty, value("merchant").count <= 80 else { throw CSVError.invalidRow(number) }
            guard let account = next.accounts.first(where: { $0.bankName == value("bank") || $0.bankID == value("bank") }) else { throw CSVError.unknownBank(number) }
            let source = "csv:" + TransactionParser.fingerprint(row.map { "\($0.utf8.count):\($0)" }.joined())
            let reference = value("reference").isEmpty ? nil : value("reference")
            let transactionID = UUID(uuidString: value("transaction_id"))
            if next.transactions.contains(where: { $0.id == transactionID || $0.sourceKey == source ||
                (reference != nil && $0.bankID == account.bankID && $0.direction == direction && $0.reference == reference) }) { continue }
            var categoryID: UUID?
            let categoryName = value("category")
            if !categoryName.isEmpty && categoryName != "Uncategorized" {
                if let category = next.categories.first(where: { $0.name.caseInsensitiveCompare(categoryName) == .orderedSame }) { categoryID = category.id }
                else { let category = Category(name: categoryName); try next.saveCategory(category); categoryID = category.id }
            }
            var tagIDs: Set<UUID> = []
            for name in value("tags").split(separator: "|").map(String.init) {
                if let tag = next.tags.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { tagIDs.insert(tag.id) }
                else { let tag = LedgerTag(name: name); try next.saveTag(tag); tagIDs.insert(tag.id) }
            }
            let official = value("official_merchant").isEmpty ? value("merchant") : value("official_merchant")
            var tx = LedgerTransaction(bankID: account.bankID, occurredAt: date, amount: amount, direction: direction,
                merchant: official, categoryID: categoryID, tagIDs: tagIDs, note: value("note"),
                affectsBalance: affectsBalances && value("affects_balance") != "false")
            tx.origin = .csv; tx.sourceKey = source; tx.reference = reference; tx.parserID = "csv-import-v1"
            if let transactionID { tx.id = transactionID }
            if value("merchant") != official {
                var rule = next.merchants.first { $0.merchantKey == tx.merchantKey } ?? MerchantRule(merchantKey: tx.merchantKey, nickname: value("merchant"))
                rule.nickname = value("merchant"); try next.saveMerchant(rule)
            }
            try next.saveTransaction(tx); imported += 1
        }
        state = next; return imported
    }
}
