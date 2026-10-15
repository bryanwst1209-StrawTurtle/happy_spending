import Testing
import Foundation
import SwiftData
@testable import HappySpendingCore

@MainActor
struct PaymentCaptureTests {
    private let now = makeDate(2026, 10, 15, 9, 30)

    private let wechatSuccess = "17:374\n三100\n♥支付成功\n•（**双）\n¥0.20\n完成"
    private let alipayBill = """
    17:37 1
    账单详情
    交易详情
    支付时间
    付款方式
    示例商户**店
    -15.12
    自动扣款成功
    2026-10-14 14:09:55
    日用百货＞
    """

    private func entries(_ context: ModelContext) throws -> [LedgerEntry] {
        try context.fetch(FetchDescriptor<LedgerEntry>())
    }

    // MARK: 通知

    @Test func anAlipayNotificationIsRecorded() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let result = try PaymentCapture.recordNotification(
            title: "交易提醒", body: "你有一笔 15.12 元的支出,领 2 元小荷包支付红包。",
            now: now, calendar: testCalendar, in: context
        )

        #expect(result.recorded)
        #expect(result.message == "已记 ¥15.12 · 支付宝")
        let entry = try #require(try entries(context).first)
        #expect(entry.autoSource == .notification)
        #expect(entry.amountInCents == 1512)
    }

    @Test func aWeChatNotificationIsRecorded() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let result = try PaymentCapture.recordNotification(
            title: "微信支付", body: "已支付 ¥147.70", now: now, calendar: testCalendar, in: context
        )

        #expect(result.recorded)
        #expect(result.message == "已记 ¥147.70 · 微信支付")
    }

    @Test func anIncomeNotificationIsQuietlyIgnored() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let result = try PaymentCapture.recordNotification(
            title: "交易提醒", body: "你有一笔 100.00 元的收入。", now: now, calendar: testCalendar, in: context
        )

        #expect(!result.recorded)
        #expect(result.message == "已忽略:收入")
        #expect(try entries(context).isEmpty)
    }

    @Test func anUnrelatedNotificationIsQuietlyIgnoredWithoutAnError() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let result = try PaymentCapture.recordNotification(
            title: "张三", body: "晚上吃什么", now: now, calendar: testCalendar, in: context
        )

        #expect(!result.recorded)
        #expect(result.message == "已忽略:不是支付通知")
        #expect(try entries(context).isEmpty)
    }

    // MARK: 屏幕识别

    @Test func aWeChatSuccessPageIsRecorded() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let result = try PaymentCapture.recordScreenText(wechatSuccess, now: now, calendar: testCalendar, in: context)

        #expect(result.recorded)
        #expect(result.message == "已记 ¥0.20 · （**双）")
        let entry = try #require(try entries(context).first)
        #expect(entry.autoSource == .screenText)
        #expect(entry.date == makeDate(2026, 10, 15))
    }

    @Test func theAlipayBillUsesItsPageTimeAndCategoryMap() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let daily = CategoryRules.addTopLevel(
            name: "日用", symbolName: "basket.fill", colorHex: "#34C759",
            kind: .expense, sortOrder: 0, in: context
        )

        let result = try PaymentCapture.recordScreenText(alipayBill, now: now, calendar: testCalendar, in: context)

        #expect(result.recorded)
        let entry = try #require(try entries(context).first)
        #expect(entry.date == makeDate(2026, 10, 14))
        #expect(entry.category === daily)
        #expect(entry.merchant == "示例商户**店")
    }

    @Test func aScreenWithoutAPaymentPageIsAnError() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        #expect(throws: PaymentCaptureError.notPaymentPage) {
            try PaymentCapture.recordScreenText("今天天气不错", now: now, calendar: testCalendar, in: context)
        }
        #expect(throws: PaymentCaptureError.notPaymentPage) {
            try PaymentCapture.recordScreenText("", now: now, calendar: testCalendar, in: context)
        }
        #expect(try entries(context).isEmpty)
    }

    @Test func anIncomeScreenIsIgnoredNotAnError() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let income = alipayBill.replacingOccurrences(of: "-15.12", with: "+15.12")

        let result = try PaymentCapture.recordScreenText(income, now: now, calendar: testCalendar, in: context)

        #expect(!result.recorded)
        #expect(result.message == "已忽略:收入")
        #expect(try entries(context).isEmpty)
    }

    @Test func triggeringTheSameBillTwiceRecordsItOnce() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let bill = """
        当前状态
        转账时间
        2026-10-14 17:37:40
        扫二维码付款-给示例商户
        -0.20
        转账单号
        10000000000000000000000000000000
        """

        let first = try PaymentCapture.recordScreenText(bill, now: now, calendar: testCalendar, in: context)
        let second = try PaymentCapture.recordScreenText(bill, now: now, calendar: testCalendar, in: context)

        #expect(first.recorded)
        #expect(!second.recorded)
        #expect(second.message == "已记过这一笔(单号相同)")
        #expect(try entries(context).count == 1)
    }

    @Test func triggeringTheSameAlipayBillTwiceRecordsItOnce() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let first = try PaymentCapture.recordScreenText(alipayBill, now: now, calendar: testCalendar, in: context)
        let second = try PaymentCapture.recordScreenText(alipayBill, now: now, calendar: testCalendar, in: context)

        #expect(first.recorded)
        #expect(!second.recorded)
        #expect(try entries(context).count == 1)
    }

    @Test func theErrorHasAReadableChineseMessage() {
        #expect(PaymentCaptureError.notPaymentPage.message == "没有识别到支付页面")
        #expect(PaymentCaptureError.notPaymentPage.errorDescription == "没有识别到支付页面")
    }
}
