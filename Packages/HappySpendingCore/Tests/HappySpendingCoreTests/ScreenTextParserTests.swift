import Testing
import Foundation
@testable import HappySpendingCore

struct ScreenTextParserTests {
    private let cal = testCalendar

    // MARK: 真实样本(已脱敏)

    /// 微信·支付成功页:`♥支付成功` 是图标被识别成了符号,商户名被打码。
    private let wechatSuccess = """
    17:374
    三100
    ♥支付成功
    •（**双）
    ¥0.20
    完成
    """

    /// 微信·账单详情页:日期被识别成了乱码 `2026·10 514E 17:37:40`。
    private let wechatBill = """
    17:38 M
    账单
    ミ分100
    全部账单
    扫二维码付款-给示例商户
    -0.20
    当前状态
    支付成功
    收款方备注
    二维码收款
    支付方式
    零钱
    转账时间
    2026·10 514E 17:37:40
    转账单号
    10000000000000000000000000000000
    账单服务
    对订单有疑惑
    申请电子凭证
    收款方服务
    向收款方留言
    发起群收款
    本服务由财付通提供
    """

    /// 微信·商户账单详情页:没有"付款-给X"这一行,商户名单独一行在金额上方。
    private let wechatMerchantBill = """
    16:18 \\
    账单
    ミ分100
    全部账单
    示例超市
    -147.70
    当前状态
    支付成功
    支付时间
    2026年10月14日 18:23:27
    商品
    商品
    商户全称
    示例（中国）投资有限公司
    收单机构
    财付通支付科技有限公司
    支付方式
    招商银行信用卡（0000）
    交易单号
    4000000000000000000000000000
    商户单号
    X0000000000000000000X000
    账单服务
    ⑦ 对订单有疑惑
    目在此商户交易
    园 发起群收款
    ③ 申请电子凭证
    联系商家
    &商家电话
    本服务由财付通提供
    """

    /// 支付宝·账单详情页:顶部混着状态栏和操作按钮的提示("截图识别 / 按住启用")。
    private let alipayBill = """
    截图识别
    17:37 1
    • 分100.
    <
    按住启用
    *截图识别文字
    支付时间
    付款方式
    支付奖励
    交易详情
    账单详情
    淘
    示例商户**店
    -15.12
    自动扣款成功
    2026-10-14 14:09:55
    招商银行信用卡（0000）＞
    v 立即领取2积分
    示例商品名称
    更多、
    共1件
    账单管理
    账单分类
    标签
    已解锁“日用百货”贴纸，去兑换好礼
    日用百货＞
    请选择＞
    使用记账本，查看自定义分类、标签统计
    计入收支
    备注
    添加＞
    查看往来记录
    """

    private func payment(_ outcome: ParseOutcome) -> PaymentRecord? {
        if case .payment(let record) = outcome { return record }
        return nil
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int, _ s: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min, second: s))!
    }

    // MARK: 微信·支付成功页

    @Test func parsesTheWeChatSuccessPage() throws {
        let record = try #require(payment(ScreenTextParser.parse(wechatSuccess, calendar: cal)))

        #expect(record.cents == 20)
        #expect(record.source == .screenText)
        #expect(record.merchant == "（**双）")
        #expect(record.note == "（**双）")
        #expect(record.eventDate == nil)
        #expect(record.orderRef == nil)
        #expect(record.platformCategory == nil)
    }

    @Test func theWeChatSuccessPageWithoutAMerchantLineUsesTheChannelName() throws {
        let record = try #require(payment(ScreenTextParser.parse("支付成功\n¥0.20\n完成", calendar: cal)))
        #expect(record.cents == 20)
        #expect(record.merchant == nil)
        #expect(record.note == "微信")
    }

    @Test func theWeChatSuccessPageAcceptsOtherCurrencySymbols() {
        for symbol in ["￥", "Y", "¥ "] {
            let text = "支付成功\n示例商户\n\(symbol)12.50\n完成"
            #expect(payment(ScreenTextParser.parse(text, calendar: cal))?.cents == 1250, "symbol \(symbol)")
        }
    }

    @Test func aWeChatSuccessPageWithoutTheDoneButtonIsUnrecognized() {
        #expect(ScreenTextParser.parse("支付成功\n示例商户\n¥0.20", calendar: cal) == .unrecognized)
    }

    // MARK: 微信·账单详情页

    @Test func parsesTheWeChatBillPage() throws {
        let record = try #require(payment(ScreenTextParser.parse(wechatBill, calendar: cal)))

        #expect(record.cents == 20)
        #expect(record.source == .screenText)
        #expect(record.merchant == "示例商户")
        #expect(record.note == "示例商户")
        #expect(record.orderRef == "10000000000000000000000000000000")
        #expect(record.platformCategory == nil)
    }

    @Test func aGarbledWeChatDateLeavesTheEventDateEmpty() throws {
        let record = try #require(payment(ScreenTextParser.parse(wechatBill, calendar: cal)))
        #expect(record.eventDate == nil)
    }

    @Test func aCleanWeChatDateIsParsed() throws {
        let text = wechatBill.replacingOccurrences(of: "2026·10 514E 17:37:40", with: "2026-10-14 17:37:40")
        let record = try #require(payment(ScreenTextParser.parse(text, calendar: cal)))
        #expect(record.eventDate == date(2026, 10, 14, 17, 37, 40))
    }

    @Test func aChineseFormattedWeChatDateIsParsed() throws {
        let text = wechatBill.replacingOccurrences(of: "2026·10 514E 17:37:40", with: "2026年10月14日 17:37:40")
        let record = try #require(payment(ScreenTextParser.parse(text, calendar: cal)))
        #expect(record.eventDate == date(2026, 10, 14, 17, 37, 40))
    }

    @Test func anImpossibleDateIsRejectedNotRolledOver() throws {
        let text = wechatBill.replacingOccurrences(of: "2026·10 514E 17:37:40", with: "2026-02-30 17:37:40")
        let record = try #require(payment(ScreenTextParser.parse(text, calendar: cal)))
        #expect(record.eventDate == nil)
    }

    /// 识别把数字认成字母(0→O、1→l)时,不能让分隔符吞掉它、把账记到别的月份。
    @Test func aDigitMisreadAsALetterLeavesTheEventDateEmpty() throws {
        for garbled in ["2026-1O-14 17:37:40", "2026年1O月14日 17:37:40", "2026-10-l4 17:37:40"] {
            let text = wechatBill.replacingOccurrences(of: "2026·10 514E 17:37:40", with: garbled)
            let record = try #require(payment(ScreenTextParser.parse(text, calendar: cal)))
            #expect(record.eventDate == nil, "\(garbled)")
        }
    }

    @Test func aFullyMaskedWeChatPayeeHasNoMerchant() throws {
        let text = wechatBill.replacingOccurrences(of: "扫二维码付款-给示例商户", with: "扫二维码付款-给●")
        let record = try #require(payment(ScreenTextParser.parse(text, calendar: cal)))
        #expect(record.merchant == nil)
        #expect(record.note == "微信")
    }

    @Test func parsesTheWeChatMerchantBillPage() throws {
        let record = try #require(payment(ScreenTextParser.parse(wechatMerchantBill, calendar: cal)))

        #expect(record.cents == 14770)
        #expect(record.merchant == "示例超市")
        #expect(record.note == "示例超市")
        #expect(record.eventDate == date(2026, 10, 14, 18, 23, 27))
        #expect(record.orderRef == "4000000000000000000000000000")
    }

    @Test func aWeChatMerchantBillWithOnlyNavigationAboveTheAmountHasNoMerchant() throws {
        let text = wechatMerchantBill.replacingOccurrences(of: "示例超市\n", with: "")
        let record = try #require(payment(ScreenTextParser.parse(text, calendar: cal)))
        #expect(record.merchant == nil)
        #expect(record.note == "微信")
    }

    /// 转账页的收款人是表情或头像时,"-给"后面识别出来是空的:不能把"扫二维码付款-给"当成商户。
    @Test func aTransferWithAnUnreadablePayeeDoesNotUseTheTransferLineAsMerchant() throws {
        let text = wechatBill.replacingOccurrences(of: "扫二维码付款-给示例商户", with: "扫二维码付款-给")
        let record = try #require(payment(ScreenTextParser.parse(text, calendar: cal)))
        #expect(record.merchant == nil)
        #expect(record.note == "微信")
    }

    @Test func theWeChatPaymentTimeLabelIsAlsoAccepted() throws {
        let text = wechatBill
            .replacingOccurrences(of: "转账时间", with: "支付时间")
            .replacingOccurrences(of: "2026·10 514E 17:37:40", with: "2026-10-14 17:37:40")
        let record = try #require(payment(ScreenTextParser.parse(text, calendar: cal)))
        #expect(record.eventDate == date(2026, 10, 14, 17, 37, 40))
    }

    @Test func aWeChatBillWithoutAnOrderNumberStillParses() throws {
        let text = wechatBill.replacingOccurrences(of: "转账单号\n10000000000000000000000000000000\n", with: "")
        let record = try #require(payment(ScreenTextParser.parse(text, calendar: cal)))
        #expect(record.orderRef == nil)
        #expect(record.cents == 20)
    }

    // MARK: 支付宝·账单详情页

    @Test func parsesTheAlipayBillPage() throws {
        let record = try #require(payment(ScreenTextParser.parse(alipayBill, calendar: cal)))

        #expect(record.cents == 1512)
        #expect(record.source == .screenText)
        #expect(record.merchant == "示例商户**店")
        #expect(record.note == "示例商户**店")
        #expect(record.eventDate == date(2026, 10, 14, 14, 9, 55))
        #expect(record.platformCategory == "日用百货")
        #expect(record.orderRef != nil)
    }

    /// 支付宝账单页首屏看不到订单号:用"金额 + 精确到秒的支付时间"当这笔支付的单号,
    /// 同一页连按两次能去重,两笔不同的支付不会撞上。
    @Test func anAlipayBillWithoutAnOrderNumberIsKeyedByAmountAndPaymentTime() throws {
        let first = try #require(payment(ScreenTextParser.parse(alipayBill, calendar: cal)))
        let again = try #require(payment(ScreenTextParser.parse("17:38\n" + alipayBill, calendar: cal)))
        let otherTime = try #require(payment(ScreenTextParser.parse(
            alipayBill.replacingOccurrences(of: "14:09:55", with: "14:09:56"), calendar: cal
        )))
        let otherAmount = try #require(payment(ScreenTextParser.parse(
            alipayBill.replacingOccurrences(of: "-15.12", with: "-15.13"), calendar: cal
        )))

        #expect(first.orderRef != nil)
        #expect(again.orderRef == first.orderRef)
        #expect(otherTime.orderRef != first.orderRef)
        #expect(otherAmount.orderRef != first.orderRef)
    }

    @Test func anAlipayBillWithoutOrderNumberOrTimeHasNoRef() throws {
        let text = alipayBill.replacingOccurrences(of: "2026-10-14 14:09:55\n", with: "")
        let record = try #require(payment(ScreenTextParser.parse(text, calendar: cal)))
        #expect(record.orderRef == nil)
    }

    @Test func theNoiseLinesOnTopDoNotBreakTheAlipayPage() throws {
        let noisy = "17:37\n100\n截图识别\n按住启用\n" + alipayBill
        let record = try #require(payment(ScreenTextParser.parse(noisy, calendar: cal)))
        #expect(record.cents == 1512)
        #expect(record.merchant == "示例商户**店")
    }

    @Test func theAlipayCategoryIsFoundWhereverItSits() throws {
        let text = alipayBill.replacingOccurrences(of: "日用百货＞", with: "餐饮美食>")
        let record = try #require(payment(ScreenTextParser.parse(text, calendar: cal)))
        #expect(record.platformCategory == "餐饮美食")
    }

    @Test func aSentenceThatMerelyMentionsACategoryIsNotTheCategory() throws {
        let text = alipayBill.replacingOccurrences(of: "日用百货＞\n", with: "")
        let record = try #require(payment(ScreenTextParser.parse(text, calendar: cal)))
        #expect(record.platformCategory == nil)
    }

    @Test func anUnknownAlipayCategoryHasNone() throws {
        let text = alipayBill.replacingOccurrences(of: "日用百货＞", with: "某个新分类＞")
        let record = try #require(payment(ScreenTextParser.parse(text, calendar: cal)))
        #expect(record.platformCategory == nil)
    }

    @Test func theAlipayMerchantIsNilWhenTheLineAboveTheAmountIsJustNavigation() throws {
        let text = alipayBill.replacingOccurrences(of: "示例商户**店", with: "账单详情")
        let record = try #require(payment(ScreenTextParser.parse(text, calendar: cal)))
        #expect(record.merchant == nil)
        #expect(record.note == "支付宝")
        #expect(record.cents == 1512)
    }

    @Test func anAlipayOrderNumberAfterItsLabelIsRead() throws {
        let text = alipayBill.replacingOccurrences(of: "查看往来记录", with: "订单号\n20000000000000000000\n查看往来记录")
        let record = try #require(payment(ScreenTextParser.parse(text, calendar: cal)))
        #expect(record.orderRef == "20000000000000000000")
    }

    // MARK: 金额的写法

    @Test func minusSignsInAllTheirSpellingsAreExpenses() {
        for minus in ["-", "−", "－", "- ", "－ "] {
            let text = wechatBill.replacingOccurrences(of: "-0.20", with: "\(minus)0.20")
            #expect(payment(ScreenTextParser.parse(text, calendar: cal))?.cents == 20, "minus \(minus)")
        }
    }

    @Test func aPlusSignIsIncomeAndIgnored() {
        let wechat = wechatBill.replacingOccurrences(of: "-0.20", with: "+0.20")
        let alipay = alipayBill.replacingOccurrences(of: "-15.12", with: "+15.12")
        #expect(ScreenTextParser.parse(wechat, calendar: cal) == .ignored("收入"))
        #expect(ScreenTextParser.parse(alipay, calendar: cal) == .ignored("收入"))
    }

    @Test func thousandsSeparatorsAndAnOversizedAmount() {
        let thousands = alipayBill.replacingOccurrences(of: "-15.12", with: "-1,234.56")
        #expect(payment(ScreenTextParser.parse(thousands, calendar: cal))?.cents == 123456)

        let huge = alipayBill.replacingOccurrences(of: "-15.12", with: "-99999999.00")
        #expect(ScreenTextParser.parse(huge, calendar: cal) == .unrecognized)

        let zero = alipayBill.replacingOccurrences(of: "-15.12", with: "-0.00")
        #expect(ScreenTextParser.parse(zero, calendar: cal) == .unrecognized)
    }

    @Test func aBillPageWithoutAnAmountLineIsUnrecognized() {
        let text = wechatBill.replacingOccurrences(of: "-0.20\n", with: "")
        #expect(ScreenTextParser.parse(text, calendar: cal) == .unrecognized)
    }

    // MARK: 不是支付页面

    @Test func randomScreenTextIsUnrecognized() {
        #expect(ScreenTextParser.parse("", calendar: cal) == .unrecognized)
        #expect(ScreenTextParser.parse("   \n\n  ", calendar: cal) == .unrecognized)
        #expect(ScreenTextParser.parse("今天天气不错\n明天见", calendar: cal) == .unrecognized)
        #expect(ScreenTextParser.parse("17:37\n100\n截图识别\n按住启用", calendar: cal) == .unrecognized)
    }

    @Test func aChatThatMentionsAnAmountIsNotAPaymentPage() {
        #expect(ScreenTextParser.parse("张三\n我转给你 ¥100.00\n收到了吗", calendar: cal) == .unrecognized)
    }

    @Test func aWeChatBillMissingItsTimeLabelFallsThroughToUnrecognized() {
        let text = wechatBill
            .replacingOccurrences(of: "转账时间\n2026·10 514E 17:37:40\n", with: "")
        #expect(ScreenTextParser.parse(text, calendar: cal) == .unrecognized)
    }
}
