import Testing
import Foundation
import SwiftData
@testable import HappySpendingCore

@MainActor
struct PaymentModelTests {
    @Test func newSourcesHaveStableRawValues() {
        #expect(EntrySource.screenText.rawValue == "screenText")
        #expect(EntrySource.notification.rawValue == "notification")
        #expect(EntrySource.applePay.rawValue == "applePay")
    }

    @Test func entriesStartWithoutAnOrderRefHash() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let entry = LedgerEntry(amountInCents: 100, kind: .expense, date: makeDate(2026, 10, 15))
        context.insert(entry)

        #expect(entry.orderRefHash == nil)
    }

    @Test func orderRefHashSurvivesASaveAndFetch() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        context.insert(LedgerEntry(
            amountInCents: 100, kind: .expense, date: makeDate(2026, 10, 15),
            autoSource: .screenText, orderRefHash: "abc123"
        ))
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<LedgerEntry>())
        #expect(fetched.count == 1)
        #expect(fetched[0].orderRefHash == "abc123")
        #expect(fetched[0].autoSource == .screenText)
        #expect(fetched[0].isAuto)
    }

    @Test func restoringADeletedEntryKeepsItsOrderRefHash() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let original = LedgerEntry(
            amountInCents: 1512, kind: .expense, date: makeDate(2026, 10, 14),
            note: "示例商户", autoSource: .screenText, merchant: "示例商户", orderRefHash: "deadbeef"
        )
        context.insert(original)

        let snapshot = DeletedEntrySnapshot(original)
        context.delete(original)
        let restored = snapshot.makeEntry(categories: [])

        #expect(restored.orderRefHash == "deadbeef")
        #expect(restored.autoSource == .screenText)
        #expect(restored.merchant == "示例商户")
    }

    // MARK: OrderRef

    @Test func orderRefHashIsA64CharLowercaseHexDigest() throws {
        let hash = try #require(OrderRef.hash("10000000000000000000000000000000"))
        #expect(hash.count == 64)
        #expect(hash.allSatisfy { "0123456789abcdef".contains($0) })
    }

    @Test func orderRefHashIgnoresWhitespace() {
        #expect(OrderRef.hash("1000 0000 0000") == OrderRef.hash("100000000000"))
        #expect(OrderRef.hash(" 100000000000\n") == OrderRef.hash("100000000000"))
    }

    @Test func differentOrderRefsHaveDifferentHashes() {
        #expect(OrderRef.hash("100000000001") != OrderRef.hash("100000000002"))
    }

    @Test func blankOrderRefsHaveNoHash() {
        #expect(OrderRef.hash("") == nil)
        #expect(OrderRef.hash("   \n ") == nil)
    }

    // MARK: PaymentRecord

    @Test func paymentRecordDefaultsAreEmpty() {
        let record = PaymentRecord(source: .notification, cents: 1512, note: "支付宝")
        #expect(record.merchant == nil)
        #expect(record.eventDate == nil)
        #expect(record.orderRef == nil)
        #expect(record.platformCategory == nil)
        #expect(record.note == "支付宝")
    }

    @Test func parseOutcomesCompareByValue() {
        let record = PaymentRecord(source: .screenText, cents: 20, note: "微信")
        #expect(ParseOutcome.payment(record) == .payment(record))
        #expect(ParseOutcome.ignored("收入") == .ignored("收入"))
        #expect(ParseOutcome.ignored("收入") != .unrecognized)
    }
}
