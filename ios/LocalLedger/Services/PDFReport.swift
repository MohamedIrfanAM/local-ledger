import UIKit
import LedgerCore

enum PDFReport {
    /// UIKit's offscreen PDF renderer; runs off the main actor and writes only to memory.
    static func make(state: LedgerState, transactions: [LedgerTransaction]) -> Data {
        let bounds = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        let bodyFont = UIFont.systemFont(ofSize: 10)
        let captionFont = UIFont.systemFont(ofSize: 8)
        let income = transactions.filter { $0.direction == .credit }.reduce(Int64(0)) { $0 + $1.amount }
        let spending = transactions.filter { $0.direction == .debit }.reduce(Int64(0)) { $0 + $1.amount }
        return renderer.pdfData { context in
            var y: CGFloat = 0; var page = 0
            func draw(_ text: String, x: CGFloat = 40, y: CGFloat, width: CGFloat = 515, height: CGFloat = 24, font: UIFont, color: UIColor = .darkGray) {
                let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
                (text as NSString).draw(in: CGRect(x: x, y: y, width: width, height: height), withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
            }
            func newPage() {
                context.beginPage(); page += 1
                draw("Local Ledger", y: 36, height: 30, font: .systemFont(ofSize: 22, weight: .semibold), color: UIColor(red: 0.16, green: 0.37, blue: 0.31, alpha: 1))
                draw("Generated locally · \(Date.now.formatted(date: .abbreviated, time: .shortened))", y: 70, font: captionFont)
                draw("Income \(Money.formatted(income))     Expenses \(Money.formatted(spending))     Entries \(transactions.count)", y: 92, font: bodyFont)
                draw("Page \(page) · Private financial report", y: 809, font: captionFont)
                y = 130
            }
            newPage()
            for tx in transactions {
                let tags = state.tags.filter { state.effectiveTags(for: tx).contains($0.id) }.map(\.name).joined(separator: ", ")
                let note = tx.note.isEmpty ? "" : "Note: " + tx.note
                let metadata = [tx.occurredAt.formatted(date: .abbreviated, time: .shortened),
                    state.accounts.first { $0.bankID == tx.bankID }?.bankName ?? tx.bankID,
                    state.category(for: tx)?.name ?? "Uncategorized", tags.isEmpty ? "" : "Tags: " + tags,
                    tx.reference.map { "Reference: " + $0 } ?? "", "Source: \(tx.origin.rawValue) · Balance: \(tx.affectsBalance ? "yes" : "no")", note].filter { !$0.isEmpty }
                let rowHeight = CGFloat(30 + metadata.count * 14)
                if y + rowHeight > 790 { newPage() }
                draw(state.merchantName(for: tx), y: y, width: 350, font: .systemFont(ofSize: 11, weight: .semibold))
                draw((tx.direction == .credit ? "+" : "−") + Money.formatted(tx.amount), x: 410, y: y, width: 145, font: bodyFont)
                y += 20
                for line in metadata { draw(line, y: y, height: 14, font: captionFont); y += 14 }
                y += 10
                context.cgContext.setStrokeColor(UIColor.lightGray.withAlphaComponent(0.3).cgColor)
                context.cgContext.move(to: CGPoint(x: 40, y: y - 4)); context.cgContext.addLine(to: CGPoint(x: 555, y: y - 4)); context.cgContext.strokePath()
            }
        }
    }
}
