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
        #expect(second.message == "已记过这一笔")
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

    // MARK: 微信支付消息列表

    private let listNow = makeDate(2026, 10, 15, 16, 25)

    private let wechatList = """
    16:25 M
    微信支付
    收款方
    交易状态
    支付成功，对方已收款
    查看账单详情
    昨天18:23
    示例超市
    使用招商银行信用卡（0000）支付
    ·147.70
    账单详情＞
    13:00
    收
    示例小吃
    使用招商银行信用卡（0000）支付
    ·55.00
    账单详情＞
    我的账单
    """

    /// 同一笔山姆的账单详情页(支付时间和列表上的"昨天18:23"在同一分钟)。
    private let wechatMerchantBill = """
    账单
    全部账单
    示例超市
    -147.70
    当前状态
    支付成功
    支付时间
    2026年10月14日 18:23:27
    交易单号
    4000000000000000000000000000
    """

    @Test func recordsEveryCompleteCardOnTheList() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let result = try PaymentCapture.recordScreenText(wechatList, now: listNow, calendar: testCalendar, in: context)

        #expect(result.recorded)
        #expect(result.message == "已记 2 笔,共 ¥202.70")
        let saved = try entries(context).sorted { $0.amountInCents > $1.amountInCents }
        #expect(saved.map(\.amountInCents) == [14770, 5500])
        #expect(saved.map(\.note) == ["示例超市", "示例小吃"])
        #expect(saved.map(\.date) == [makeDate(2026, 10, 14), makeDate(2026, 10, 15)])
        #expect(saved.allSatisfy { $0.autoSource == .screenText })
    }

    @Test func pressingTheSameListTwiceRecordsNothingNew() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        try PaymentCapture.recordScreenText(wechatList, now: listNow, calendar: testCalendar, in: context)
        let again = try PaymentCapture.recordScreenText(wechatList, now: listNow, calendar: testCalendar, in: context)

        #expect(!again.recorded)
        #expect(again.message == "这一屏的 2 笔都记过了")
        #expect(try entries(context).count == 2)
    }

    @Test func aPaymentRecordedOnItsDetailPageIsSkippedOnTheList() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        try PaymentCapture.recordScreenText(wechatMerchantBill, now: listNow, calendar: testCalendar, in: context)
        let list = try PaymentCapture.recordScreenText(wechatList, now: listNow, calendar: testCalendar, in: context)

        #expect(list.recorded)
        #expect(list.message == "已记 1 笔 ¥55.00,1 笔已记过")
        #expect(try entries(context).count == 2)
    }

    @Test func aListWithOneNewCardUsesTheSingleEntryMessage() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let one = "微信支付\n13:00\n示例小吃\n使用零钱支付\n·55.00\n账单详情＞"

        let first = try PaymentCapture.recordScreenText(one, now: listNow, calendar: testCalendar, in: context)
        let second = try PaymentCapture.recordScreenText(one, now: listNow, calendar: testCalendar, in: context)

        #expect(first.message == "已记 ¥55.00 · 示例小吃")
        #expect(second.message == "已记过这一笔")
        #expect(!second.recorded)
    }

    @Test func twoIdenticalCardsOnOneScreenAreRecordedOnce() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let twins = """
        微信支付
        13:00
        示例小吃
        使用零钱支付
        ·55.00
        账单详情＞
        示例小吃
        使用零钱支付
        ·55.00
        账单详情＞
        """

        let result = try PaymentCapture.recordScreenText(twins, now: listNow, calendar: testCalendar, in: context)

        #expect(result.message == "已记 1 笔 ¥55.00,1 笔已记过")
        #expect(try entries(context).count == 1)
    }

    @Test func aListWithoutCompleteCardsThrows() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let cutOff = "微信支付\n收款方\n查看账单详情\n昨天18:23\n示例超市\n使用零钱支付"

        #expect(throws: PaymentCaptureError.noCompleteCard) {
            try PaymentCapture.recordScreenText(cutOff, now: listNow, calendar: testCalendar, in: context)
        }
        #expect(try entries(context).isEmpty)
    }

    @Test func listMessagesForEveryCombination() {
        func fresh(_ cents: Int, _ message: String = "") -> AutoEntryResult {
            AutoEntryResult(entryID: UUID(), cents: cents, message: message)
        }
        #expect(PaymentCapture.listMessage(fresh: [fresh(8100, "已记 ¥81.00 · 示例小吃")], duplicates: 0)
                == "已记 ¥81.00 · 示例小吃")
        #expect(PaymentCapture.listMessage(fresh: [fresh(8100), fresh(5570)], duplicates: 0)
                == "已记 2 笔,共 ¥136.70")
        #expect(PaymentCapture.listMessage(fresh: [fresh(8100)], duplicates: 1)
                == "已记 1 笔 ¥81.00,1 笔已记过")
        #expect(PaymentCapture.listMessage(fresh: [fresh(8100), fresh(5570)], duplicates: 1)
                == "已记 2 笔,共 ¥136.70,1 笔已记过")
        #expect(PaymentCapture.listMessage(fresh: [], duplicates: 1) == "已记过这一笔")
        #expect(PaymentCapture.listMessage(fresh: [], duplicates: 2) == "这一屏的 2 笔都记过了")
    }

    @Test func theNoCompleteCardErrorHasAReadableChineseMessage() {
        #expect(PaymentCaptureError.noCompleteCard.message == "这一屏没有完整的支付记录")
        #expect(PaymentCaptureError.noCompleteCard.errorDescription == "这一屏没有完整的支付记录")
    }

    @Test func theErrorHasAReadableChineseMessage() {
        #expect(PaymentCaptureError.notPaymentPage.message == "没有识别到支付页面")
        #expect(PaymentCaptureError.notPaymentPage.errorDescription == "没有识别到支付页面")
    }
}
