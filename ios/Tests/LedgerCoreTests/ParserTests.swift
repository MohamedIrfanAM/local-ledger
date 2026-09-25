import Foundation
import Testing
@testable import LedgerCore

struct ParserTests {
    let received = Date(timeIntervalSince1970: 1_788_558_000)

    @Test(arguments: ["AX-ICICIT-S", "VD-DCBANK-T", "JD-SBIUPI-S", "JX-CBSSBI-S"])
    func senderNormalization(_ sender: String) {
        #expect(BankRegistry.normalize(sender) == String(sender.dropFirst(3).dropLast(2)))
    }
    @Test func registryPreservesOfficialAndObservedHeaders() throws {
        let registry = try BankRegistry()
        #expect(registry.banks.count == 46)
        #expect(registry.banks.reduce(0) { $0 + $1.headers.count + ($1.observedHeaders?.count ?? 0) } == 563)
        #expect(registry.bank(for: "AX-ICICIT-S")?.id == "icici-bank")
        #expect(registry.bank(for: "NOTBANK") == nil)
        #expect(registry.published == "2020-06-16")
    }
    @Test func genericDebit() throws {
        let tx = try #require(TransactionParser.parse("Rs.1,249.50 debited from A/c XX1234 and paid to FRESH MENU on 05-09-2026 20:14. Avl Bal Rs 9,000", receivedAt: received, timeZone: .gmt))
        #expect(tx.amount == 124950); #expect(tx.direction == .debit); #expect(tx.merchant == "FRESH MENU")
        #expect(tx.occurredAt.ISO8601Format() == "2026-09-05T20:14:00Z")
    }
    @Test func refundAndUPICredit() throws {
        let refund = try #require(TransactionParser.parse("INR 500.00 refunded to your account for transaction at SWIGGY", receivedAt: received))
        #expect(refund.direction == .credit); #expect(refund.amount == 50000)
        let upi = try #require(TransactionParser.parse("Your a/c is credited by ₹2,500 via UPI from arun@okaxis", receivedAt: received))
        #expect(upi.direction == .credit); #expect(upi.amount == 250000); #expect(upi.merchant == "arun@okaxis")
    }
    @Test func iciciProfiles() throws {
        let debit = try #require(TransactionParser.parse("ICICI Bank Acct XX123 debited for Rs 42.00 on 05-Sep-26; CITY TRANSIT credited. UPI:600000000001.", receivedAt: received, bankID: "icici-bank", timeZone: .gmt))
        #expect(debit.direction == .debit); #expect(debit.amount == 4200); #expect(debit.merchant == "CITY TRANSIT")
        #expect(debit.parserID == "icici-account-debit-v1"); #expect(debit.confidence == 95)
        #expect(debit.occurredAt.ISO8601Format().hasPrefix("2026-09-05"))
        let salary = try #require(TransactionParser.parse("Your Acct XX123 is credited with salary of INR 12,000.00", receivedAt: received, bankID: "icici-bank"))
        #expect(salary.parserID == "icici-salary-credit-v1"); #expect(salary.amount == 1_200_000)
    }
    @Test func dcbProfiles() throws {
        let debit = try #require(TransactionParser.parse("INR 21.00 debited DCB a/c 1234; to SAMPLE SHOP; UPI 600000000002. Bal INR 999.00", receivedAt: received, bankID: "dcb-bank"))
        #expect(debit.direction == .debit); #expect(debit.merchant == "SAMPLE SHOP"); #expect(debit.parserID == "dcb-upi-debit-v1")
        let credit = try #require(TransactionParser.parse("INR 650.00 credited to your DCB Bank a/c 1234 from UPI ID sample@oksbi. UPI ref. 600000000003.", receivedAt: received, bankID: "dcb-bank"))
        #expect(credit.direction == .credit); #expect(credit.merchant == "sample@oksbi"); #expect(credit.parserID == "dcb-upi-credit-v1")
    }
    @Test func sbiProfilesAndCompactDates() throws {
        let debit = try #require(TransactionParser.parse("Dear UPI user A/C X1234 debited by 22.00 on date 27Aug26 trf to SAMPLE STORE Refno 600000000004-SBI", receivedAt: received, bankID: "state-bank-of-india", timeZone: .gmt))
        #expect(debit.direction == .debit); #expect(debit.merchant == "SAMPLE STORE"); #expect(debit.parserID == "sbi-upi-debit-v1")
        #expect(debit.occurredAt.ISO8601Format().hasPrefix("2026-08-27"))
        let credit = try #require(TransactionParser.parse("Your A/C XXXXX001234 has credit for UPI/DRC/600000000005/16082026/ of Rs 73.00 on 16/08/26. Avl Bal Rs 999.00-SBI", receivedAt: received, bankID: "state-bank-of-india", timeZone: .gmt))
        #expect(credit.amount == 7300); #expect(credit.direction == .credit); #expect(credit.parserID == "sbi-upi-credit-v1")
        #expect(credit.occurredAt.ISO8601Format().hasPrefix("2026-08-16"))
    }
    @Test(arguments: [
        "OTP 123456 for INR 900 payment", "Transaction of Rs 900 was declined",
        "Rs 999 spent on your credit card ending 1234 at STORE", "Credit of INR 800.00 failed for your account",
        "Use OTP 998877 to authorize Rs.999.00 debited at SAMPLE SHOP on A/c XX1234.",
        "OTP 112233 for INR 700.00 debit transaction on A/c XX1234.",
        "INR 499.00 will be debited from A/c XX1234 on 10-Sep-26 for SAMPLE SUBSCRIPTION.",
        "Paid too much? Get cashback of Rs.500.00. Shop now.",
        "INR 999999999999999999999999 debited from account", "Rs 0 debited from account"
    ]) func rejectsUnsafeMessages(_ body: String) { #expect(TransactionParser.parse(body, receivedAt: received) == nil) }
    @Test func footerOTPIsNotAnOTPMessage() throws {
        let tx = try #require(TransactionParser.parse("A/c XX1234 debited by INR 120.00 at SAMPLE CAFE. Never share OTP or PIN.", receivedAt: received))
        #expect(tx.amount == 12000); #expect(tx.direction == .debit)
    }
    @Test func masksBalanceAmounts() throws {
        let first = try #require(TransactionParser.parse("Available balance INR 9,876.54. Your A/c XX1234 was debited by INR 45.00 at SAMPLE STORE.", receivedAt: received))
        let second = try #require(TransactionParser.parse("Bal INR 8,765.43. A/c XX1234 debited by INR 46.00 at SAMPLE STORE.", receivedAt: received))
        #expect(first.amount == 4500); #expect(second.amount == 4600)
    }
    @Test func referenceAndProfileMetadata() throws {
        let tx = try #require(TransactionParser.parse("INR 75.00 debited from A/c XX1234 to SAMPLE STORE. UTR N123456789012.", receivedAt: received))
        #expect(tx.reference == "N123456789012")
        #expect(TransactionParser.profileIDs(bankID: "icici-bank") == ["icici-account-debit-v1", "icici-salary-credit-v1"])
        #expect(TransactionParser.profileIDs(bankID: "unknown").isEmpty)
    }
    @Test func privacySafeDiagnosticsAndFingerprints() {
        let body = "INR 75.00 debited from A/c XX1234 to SECRET STORE. UTR N123456789012."
        let signals = TransactionParser.diagnosticSignals(body)
        for secret in ["75", "1234", "SECRET", "N123456789012"] { #expect(!signals.contains(secret)) }
        #expect(TransactionParser.sourceKey(sender: "AX-ICICIT-S", body: body, receivedAt: received) == TransactionParser.sourceKey(sender: "ICICIT", body: "  " + body, receivedAt: received))
    }
}
