import Testing
import Foundation
import SwiftData
@testable import HappySpendingCore

@MainActor
struct PaymentRecorderTests {
    private let now = makeDate(2026, 10, 15, 9, 30)

    private func makeCategories(_ context: ModelContext) throws -> (daily: LedgerCategory, food: LedgerCategory, lunch: LedgerCategory, salary: LedgerCategory) {
        let daily = CategoryRules.addTopLevel(
            name: "日用", symbolName: "basket.fill", colorHex: "#34C759",
            kind: .expense, sortOrder: 0, in: context
        )
        let food = CategoryRules.addTopLevel(
            name: "餐饮", symbolName: "fork.knife", colorHex: "#FF9F0A",
            kind: .expense, sortOrder: 1, in: context
        )
        let lunch = try CategoryRules.addSubcategory(name: "午餐", under: food, in: context)
        let salary = CategoryRules.addTopLevel(
            name: "工资", symbolName: "banknote.fill", colorHex: "#30D158",
            kind: .income, sortOrder: 0, in: context
        )
        return (daily, food, lunch, salary)
    }

    private func entries(_ context: ModelContext) throws -> [LedgerEntry] {
        try context.fetch(FetchDescriptor<LedgerEntry>())
    }

    // MARK: 映射表

    @Test func theAlipayMapCoversTheDocumentedCategories() {
        #expect(PlatformCategoryMap.ourCategoryName(forAlipay: "日用百货") == "日用")
        #expect(PlatformCategoryMap.ourCategoryName(forAlipay: "餐饮美食") == "餐饮")
        #expect(PlatformCategoryMap.ourCategoryName(forAlipay: "交通出行") == "交通")
        #expect(PlatformCategoryMap.ourCategoryName(forAlipay: "服饰装扮") == "服饰")
        #expect(PlatformCategoryMap.ourCategoryName(forAlipay: "爱车养车") == "汽车")
        #expect(PlatformCategoryMap.ourCategoryName(forAlipay: "酒店旅游") == "旅游")
        #expect(PlatformCategoryMap.ourCategoryName(forAlipay: "医疗健康") == "医疗")
        #expect(PlatformCategoryMap.ourCategoryName(forAlipay: "住房物业") == "居住")
        #expect(PlatformCategoryMap.ourCategoryName(forAlipay: "数码电器") == "购物")
    }

    @Test func unknownAlipayCategoriesHaveNoMapping() {
        #expect(PlatformCategoryMap.ourCategoryName(forAlipay: "充值缴费") == nil)
        #expect(PlatformCategoryMap.ourCategoryName(forAlipay: "") == nil)
        #expect(PlatformCategoryMap.ourCategoryName(forAlipay: "日用") == nil)
    }

    // MARK: 记账

    @Test func recordsANotificationPaymentWithItsSourceAndNote() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let payment = PaymentRecord(source: .notification, cents: 1512, note: "支付宝")

        let result = try AutoEntryRecorder.record(payment, now: now, calendar: testCalendar, in: context)

        let entry = try #require(try entries(context).first)
        #expect(entry.amountInCents == 1512)
        #expect(entry.kind == .expense)
        #expect(entry.note == "支付宝")
        #expect(entry.merchant == nil)
        #expect(entry.autoSource == .notification)
        #expect(entry.category == nil)
        #expect(entry.date == makeDate(2026, 10, 15))
        #expect(entry.createdAt == now)
        #expect(entry.orderRefHash == nil)
        #expect(result.entryID == entry.id)
        #expect(result.cents == 1512)
        #expect(!result.isDuplicate)
        #expect(result.message == "已记 ¥15.12 · 支付宝")
    }

    @Test func theMessageNamesTheMerchantWhenThereIsOne() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let payment = PaymentRecord(source: .screenText, cents: 20, merchant: "示例商户", note: "示例商户")

        let result = try AutoEntryRecorder.record(payment, now: now, calendar: testCalendar, in: context)

        #expect(result.message == "已记 ¥0.20 · 示例商户")
        #expect(try entries(context).first?.merchant == "示例商户")
    }

    @Test func theEventDateWinsOverTheTriggerTime() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let payment = PaymentRecord(
            source: .screenText, cents: 1512, note: "支付宝",
            eventDate: makeDate(2026, 10, 14, 14, 9)
        )

        try AutoEntryRecorder.record(payment, now: now, calendar: testCalendar, in: context)

        #expect(try entries(context).first?.date == makeDate(2026, 10, 14))
    }

    @Test func withoutAnEventDateTheTriggerDayIsUsed() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        try AutoEntryRecorder.record(
            PaymentRecord(source: .screenText, cents: 20, note: "微信"),
            now: now, calendar: testCalendar, in: context
        )

        #expect(try entries(context).first?.date == makeDate(2026, 10, 15))
    }

    // MARK: 单号去重

    @Test func theSameOrderNumberIsRecordedOnlyOnce() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let payment = PaymentRecord(
            source: .screenText, cents: 20, merchant: "示例商户", note: "示例商户",
            orderRef: "10000000000000000000000000000000"
        )

        let first = try AutoEntryRecorder.record(payment, now: now, calendar: testCalendar, in: context)
        let second = try AutoEntryRecorder.record(payment, now: now, calendar: testCalendar, in: context)

        #expect(try entries(context).count == 1)
        #expect(!first.isDuplicate)
        #expect(second.isDuplicate)
        #expect(second.entryID == first.entryID)
        #expect(second.message == "已记过这一笔(单号相同)")
    }

    @Test func differentOrderNumbersAreBothRecorded() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        for ref in ["10000000000000000000000000000001", "10000000000000000000000000000002"] {
            try AutoEntryRecorder.record(
                PaymentRecord(source: .screenText, cents: 20, note: "微信", orderRef: ref),
                now: now, calendar: testCalendar, in: context
            )
        }

        #expect(try entries(context).count == 2)
    }

    @Test func paymentsWithoutAnOrderNumberAreNeverDeduplicated() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let payment = PaymentRecord(source: .screenText, cents: 20, note: "微信")

        try AutoEntryRecorder.record(payment, now: now, calendar: testCalendar, in: context)
        try AutoEntryRecorder.record(payment, now: now, calendar: testCalendar, in: context)

        #expect(try entries(context).count == 2)
    }

    @Test func theStoredHashIsTheHashNotTheRawOrderNumber() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let raw = "10000000000000000000000000000000"

        try AutoEntryRecorder.record(
            PaymentRecord(source: .screenText, cents: 20, note: "微信", orderRef: raw),
            now: now, calendar: testCalendar, in: context
        )

        let stored = try #require(try entries(context).first?.orderRefHash)
        #expect(stored == OrderRef.hash(raw))
        #expect(stored != raw)
    }

    // MARK: 分类优先级

    @Test func merchantMemoryIsUsedFirst() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (daily, food, _, _) = try makeCategories(context)
        try MerchantMemory.learn(merchant: "示例商户", categoryID: food.id, in: context)
        let payment = PaymentRecord(
            source: .screenText, cents: 1512, merchant: "示例商户", note: "示例商户",
            platformCategory: "日用百货"
        )

        try AutoEntryRecorder.record(payment, now: now, calendar: testCalendar, in: context)

        let entry = try #require(try entries(context).first)
        #expect(entry.category === food)
        #expect(entry.category !== daily)
    }

    @Test func theAlipayCategoryMapIsUsedWhenThereIsNoMemory() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (daily, _, _, _) = try makeCategories(context)
        let payment = PaymentRecord(
            source: .screenText, cents: 1512, merchant: "示例商户", note: "示例商户",
            platformCategory: "日用百货"
        )

        try AutoEntryRecorder.record(payment, now: now, calendar: testCalendar, in: context)

        #expect(try entries(context).first?.category === daily)
    }

    @Test func theMapAppliesEvenWithoutAMerchant() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (_, food, _, _) = try makeCategories(context)
        let payment = PaymentRecord(source: .screenText, cents: 3000, note: "支付宝", platformCategory: "餐饮美食")

        try AutoEntryRecorder.record(payment, now: now, calendar: testCalendar, in: context)

        #expect(try entries(context).first?.category === food)
    }

    @Test func aMappingTargetThatIsArchivedFallsBackToUncategorized() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (daily, _, _, _) = try makeCategories(context)
        CategoryRules.archive(daily)
        let payment = PaymentRecord(source: .screenText, cents: 1512, note: "支付宝", platformCategory: "日用百货")

        try AutoEntryRecorder.record(payment, now: now, calendar: testCalendar, in: context)

        #expect(try entries(context).first?.category == nil)
    }

    @Test func aMappingTargetThatWasRenamedFallsBackToUncategorized() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (daily, _, _, _) = try makeCategories(context)
        daily.name = "家居"
        let payment = PaymentRecord(source: .screenText, cents: 1512, note: "支付宝", platformCategory: "日用百货")

        try AutoEntryRecorder.record(payment, now: now, calendar: testCalendar, in: context)

        #expect(try entries(context).first?.category == nil)
    }

    @Test func theMapNeverPicksAnIncomeCategoryWithTheSameName() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        CategoryRules.addTopLevel(
            name: "日用", symbolName: "gift.fill", colorHex: "#FFD60A",
            kind: .income, sortOrder: 0, in: context
        )
        let payment = PaymentRecord(source: .screenText, cents: 1512, note: "支付宝", platformCategory: "日用百货")

        try AutoEntryRecorder.record(payment, now: now, calendar: testCalendar, in: context)

        #expect(try entries(context).first?.category == nil)
    }

    @Test func anUnmappedPlatformCategoryIsUncategorized() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        _ = try makeCategories(context)
        let payment = PaymentRecord(source: .screenText, cents: 1512, note: "支付宝", platformCategory: "充值缴费")

        try AutoEntryRecorder.record(payment, now: now, calendar: testCalendar, in: context)

        #expect(try entries(context).first?.category == nil)
    }

    // MARK: 学习

    @Test func aScreenEntryWithAMerchantCanLearnFromAnEdit() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (_, food, _, _) = try makeCategories(context)
        try AutoEntryRecorder.record(
            PaymentRecord(source: .screenText, cents: 1512, merchant: "示例商户", note: "示例商户"),
            now: now, calendar: testCalendar, in: context
        )
        let entry = try #require(try entries(context).first)

        entry.category = food
        let learned = try MerchantMemory.learnFromEdit(entry: entry, previousCategoryID: nil, in: context)

        #expect(learned)
    }

    @Test func aNotificationEntryHasNoMerchantSoItNeverLearns() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (_, food, _, _) = try makeCategories(context)
        try AutoEntryRecorder.record(
            PaymentRecord(source: .notification, cents: 1512, note: "支付宝"),
            now: now, calendar: testCalendar, in: context
        )
        let entry = try #require(try entries(context).first)

        entry.category = food
        let learned = try MerchantMemory.learnFromEdit(entry: entry, previousCategoryID: nil, in: context)

        #expect(!learned)
    }

    // MARK: Apple Pay 入口仍然可用

    @Test func theApplePayEntryPointStillWorks() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let result = try AutoEntryRecorder.record(
            merchant: "  美团 ", amountText: "¥25.50", now: now, calendar: testCalendar, in: context
        )

        let entry = try #require(try entries(context).first)
        #expect(entry.autoSource == .applePay)
        #expect(entry.merchant == "美团")
        #expect(entry.note == "美团")
        #expect(entry.amountInCents == 2550)
        #expect(result.message == "已记 ¥25.50 · 美团")
    }
}
