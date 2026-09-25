import Foundation

public struct BankRegistry: Sendable {
    public let banks: [BankDefinition]
    public let published: String
    public let source: String
    private let headers: [String: BankDefinition]
    public init() throws {
        struct Registry: Decodable { var banks: [BankDefinition]; var published: String; var source: String }
        guard let url = Bundle.module.url(forResource: "bank_sender_registry", withExtension: "json") else { throw LedgerError.corruptStore }
        let registry = try JSONDecoder().decode(Registry.self, from: Data(contentsOf: url))
        banks = registry.banks.sorted { $0.name < $1.name }; published = registry.published; source = registry.source
        var index: [String: BankDefinition] = [:]
        for bank in banks { for header in bank.headers + (bank.observedHeaders ?? []) { index[header.uppercased()] = bank } }
        headers = index
    }
    public func bank(for sender: String) -> BankDefinition? { headers[Self.normalize(sender)] }
    public static func normalize(_ sender: String) -> String {
        var value = sender.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().replacingOccurrences(of: " ", with: "")
        value = value.replacingOccurrences(of: #"^[A-Z]{2}-"#, with: "", options: .regularExpression)
        return value.replacingOccurrences(of: #"-[PSTG]$"#, with: "", options: .regularExpression)
    }
}
