import Testing
@testable import HappySpendingCore

struct NotificationPaymentParserTests {
    private func payment(_ outcome: ParseOutcome) -> PaymentRecord? {
        if case .payment(let record) = outcome { return record }
        return nil
    }

    // MARK: 支付宝(真实样本:交易提醒 / 你有一笔 15.12 元的支出,领 2 元小荷包支付红包。)

    @Test func parsesTheRealAlipayNotification() throws {
        let outcome = NotificationPaymentParser.parse(
            title: "交易提醒",
            body: "你有一笔 15.12 元的支出,领 2 元小荷包支付红包。"
        )

        let record = try #require(payment(outcome))
        #expect(record.cents == 1512)
        #expect(record.source == .notification)
        #expect(record.note == "支付宝")
        #expect(record.merchant == nil)
        #expect(record.eventDate == nil)
        #expect(record.orderRef == nil)
        #expect(record.platformCategory == nil)
    }

    @Test func parsesTheAlipayNotificationWithFullWidthPunctuationAndNoSpaces() throws {
        let outcome = NotificationPaymentParser.parse(
            title: "交易提醒",
            body: "你有一笔15.12元的支出，领2元小荷包支付红包。"
        )
        #expect(payment(outcome)?.cents == 1512)
    }

    @Test func thePromotionalAmountIsNeverTaken() throws {
        let promoFirst = NotificationPaymentParser.parse(
            title: "交易提醒",
            body: "领 2 元小荷包。你有一笔 15.12 元的支出,另有 9 元优惠"
        )
        #expect(payment(promoFirst)?.cents == 1512)

        let bigPromo = NotificationPaymentParser.parse(
            title: "交易提醒",
            body: "你有一笔 0.50 元的支出,领 100 元红包"
        )
        #expect(payment(bigPromo)?.cents == 50)
    }

    @Test func alipayIncomeIsIgnored() {
        let outcome = NotificationPaymentParser.parse(title: "交易提醒", body: "你有一笔 100.00 元的收入。")
        #expect(outcome == .ignored("收入"))
    }

    @Test func parsesAlipayAmountsWithThousandsSeparators() {
        let outcome = NotificationPaymentParser.parse(title: "交易提醒", body: "你有一笔1,234.50元的支出")
        #expect(payment(outcome)?.cents == 123450)
    }

    @Test func theTitleMayHaveSurroundingWhitespace() {
        let outcome = NotificationPaymentParser.parse(title: " 交易提醒\n", body: "你有一笔 15.12 元的支出")
        #expect(payment(outcome)?.cents == 1512)
    }

    @Test func anAlipayNotificationOfAnotherKindIsUnrecognized() {
        #expect(NotificationPaymentParser.parse(title: "交易提醒", body: "你的账单已出,请及时还款") == .unrecognized)
        #expect(NotificationPaymentParser.parse(title: "交易提醒", body: "") == .unrecognized)
    }

    @Test func aZeroOrOversizedAlipayAmountIsUnrecognized() {
        #expect(NotificationPaymentParser.parse(title: "交易提醒", body: "你有一笔 0 元的支出") == .unrecognized)
        #expect(NotificationPaymentParser.parse(title: "交易提醒", body: "你有一笔 10000000 元的支出") == .unrecognized)
    }

    // MARK: 微信(真实样本:微信支付 / 已支付 ¥147.70)

    @Test func parsesTheRealWeChatNotification() throws {
        let outcome = NotificationPaymentParser.parse(title: "微信支付", body: "已支付 ¥147.70")

        let record = try #require(payment(outcome))
        #expect(record.cents == 14770)
        #expect(record.source == .notification)
        #expect(record.note == "微信支付")
        #expect(record.merchant == nil)
    }

    @Test func parsesTheWeChatNotificationInOtherSpellings() {
        #expect(payment(NotificationPaymentParser.parse(title: "微信支付", body: "已支付￥147.70"))?.cents == 14770)
        #expect(payment(NotificationPaymentParser.parse(title: "微信支付", body: "已支付 ¥ 1,147.70"))?.cents == 114770)
        #expect(payment(NotificationPaymentParser.parse(title: "微信支付", body: "已支付 ¥5"))?.cents == 500)
    }

    @Test func otherWeChatPaymentNotificationsAreUnrecognized() {
        #expect(NotificationPaymentParser.parse(title: "微信支付", body: "已退款 ¥10.00") == .unrecognized)
        #expect(NotificationPaymentParser.parse(title: "微信支付", body: "收款到账 ¥10.00") == .unrecognized)
        #expect(NotificationPaymentParser.parse(title: "微信支付", body: "") == .unrecognized)
    }

    // MARK: 不是支付通知

    @Test func aChatMessageThatMentionsPayingIsNotARecord() {
        #expect(NotificationPaymentParser.parse(title: "张三", body: "已支付 ¥5") == .unrecognized)
        #expect(NotificationPaymentParser.parse(title: "张三", body: "你有一笔 5 元的支出") == .unrecognized)
    }

    @Test func otherAppsAndEmptyTitlesAreUnrecognized() {
        #expect(NotificationPaymentParser.parse(title: "美团", body: "已支付 ¥25.00") == .unrecognized)
        #expect(NotificationPaymentParser.parse(title: "", body: "已支付 ¥25.00") == .unrecognized)
    }
}
