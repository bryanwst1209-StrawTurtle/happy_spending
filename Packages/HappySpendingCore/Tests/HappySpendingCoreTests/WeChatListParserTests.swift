import Testing
import Foundation
@testable import HappySpendingCore

struct WeChatListParserTests {
    // MARK: 真实样本(已脱敏)

    /// 样本一:顶部是一张被截断的转账卡(只剩"收款方 / 交易状态 / 查看账单详情"),下面两张完整卡片。
    /// "¥"被识别成"·";"收"是商户 logo 被识别成的字。
    private let sampleOne = """
    16:25 M
    三100
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
    支付服务
    优惠
    """
    private let sampleOneNow = makeDate(2026, 10, 15, 16, 25)

    /// 样本二:自动续费卡片的商户行没被识别出来,"续费项目""开通账号"跑到了金额前面。
    private let sampleTwo = """
    16:40 \\
    微信支付
    星期六 11:01
    续费项目
    开通账号
    通过招商银行信用卡（0000）自动续费
    · 9.90
    账单详情＞
    示例会员卡每月自动续费
    微信代扣
    对订单有疑惑
    进入商家小程序
    >
    星期六 12:41
    示例小吃
    使用招商银行信用卡（0000）支付
    · 81.00
    账单详情＞
    我账单
    支付服务
    优惠
    """
    private let sampleTwoNow = makeDate(2026, 10, 15, 16, 40)

    private let now = makeDate(2026, 10, 15, 16, 40)

    private func parse(_ text: String, now: Date? = nil) -> [PaymentRecord]? {
        WeChatListParser.parse(text, now: now ?? self.now, calendar: testCalendar)
    }

    // MARK: 真实样本

    @Test func parsesSampleOne() throws {
        let cards = try #require(parse(sampleOne, now: sampleOneNow))
        #expect(cards.count == 2)

        #expect(cards[0].cents == 14770)
        #expect(cards[0].merchant == "示例超市")
        #expect(cards[0].note == "示例超市")
        #expect(cards[0].eventDate == makeDate(2026, 10, 14, 18, 23))
        #expect(cards[0].source == .screenText)
        #expect(cards[0].platformCategory == nil)

        #expect(cards[1].cents == 5500)
        #expect(cards[1].merchant == "示例小吃")
        #expect(cards[1].eventDate == makeDate(2026, 10, 15, 13, 0))
    }

    @Test func parsesSampleTwo() throws {
        let cards = try #require(parse(sampleTwo, now: sampleTwoNow))
        #expect(cards.count == 2)

        #expect(cards[0].cents == 990)
        #expect(cards[0].merchant == nil)
        #expect(cards[0].note == "微信")
        #expect(cards[0].eventDate == makeDate(2026, 10, 10, 11, 1))

        #expect(cards[1].cents == 8100)
        #expect(cards[1].merchant == "示例小吃")
        #expect(cards[1].eventDate == makeDate(2026, 10, 10, 12, 41))
    }

    @Test func cardsCarryTheWeChatKey() throws {
        let cards = try #require(parse(sampleOne, now: sampleOneNow))
        #expect(cards[0].orderRef == "微信|14770|2026-10-14 18:23")
        #expect(cards[1].orderRef == "微信|5500|2026-10-15 13:00")
    }

    // MARK: 卡片边界

    /// 不是识别原文:按录屏里看到的转账卡片版式构造,真机采样后替换。
    @Test func aTransferCardHasNoMerchant() throws {
        let text = """
        微信支付
        昨天 17:37
        微信支付凭证
        使用零钱支付
        ¥0.20
        收款方
        交易状态
        支付成功，对方已收款
        查看账单详情
        """
        let cards = try #require(parse(text))
        #expect(cards.count == 1)
        #expect(cards[0].cents == 20)
        #expect(cards[0].merchant == nil)
        #expect(cards[0].note == "微信")
        #expect(cards[0].eventDate == makeDate(2026, 10, 14, 17, 37))
    }

    @Test func cardsUnderOneTimeLabelShareIt() throws {
        let text = """
        微信支付
        13:00
        示例小吃
        使用零钱支付
        ·55.00
        账单详情＞
        示例超市
        使用零钱支付
        ·20.00
        账单详情＞
        """
        let cards = try #require(parse(text))
        #expect(cards.map(\.merchant) == ["示例小吃", "示例超市"])
        #expect(cards.map(\.eventDate) == [makeDate(2026, 10, 15, 13, 0), makeDate(2026, 10, 15, 13, 0)])
    }

    @Test func leftoverLinesBetweenCardsDoNotLeakIntoTheNextCard() throws {
        let text = """
        微信支付
        11:01
        续费项目
        开通账号
        通过招商银行信用卡（0000）自动续费
        · 9.90
        账单详情＞
        示例会员卡每月自动续费
        微信代扣
        进入商家小程序
        使用零钱支付
        · 3.00
        账单详情＞
        """
        let cards = try #require(parse(text))
        #expect(cards.count == 2)
        #expect(cards[1].cents == 300)
        #expect(cards[1].merchant == nil)
        #expect(cards[1].eventDate == makeDate(2026, 10, 15, 11, 1))
    }

    /// 认不出的时间标签(12 小时制、乱码)下面的卡片宁可跳过,也不能借用上一个标签的时间、悄悄记错日期。
    @Test func anUnreadableTimeLabelDoesNotLendThePreviousTime() throws {
        for unreadable in ["下午1:00", "昨天 下午6:23", "昨天 18.23", "星期六 11:0l", "13:00 收", "25:00"] {
            let text = """
            微信支付
            昨天 09:00
            示例甲
            使用零钱支付
            ·10.00
            账单详情＞
            \(unreadable)
            示例乙
            使用零钱支付
            ·20.00
            账单详情＞
            """
            let cards = try #require(parse(text))
            #expect(cards.map(\.cents) == [1000], "\(unreadable)")
        }
    }

    /// 普通的商户名不能被当成"像时间的行"而打断卡片。
    @Test func merchantNamesThatStartLikeDatesStillWork() throws {
        let text = """
        微信支付
        13:00
        周黑鸭
        使用零钱支付
        ·30.00
        账单详情＞
        昨天咖啡
        使用零钱支付
        ·12.00
        账单详情＞
        """
        let cards = try #require(parse(text))
        #expect(cards.map(\.merchant) == ["周黑鸭", "昨天咖啡"])
    }

    /// 金额取支出标志之后的那一行:识别把上一张卡的金额挪到"账单详情"后面时,不能记成下一张卡的金额。
    @Test func theAmountMustComeAfterTheExpenseMarker() throws {
        let text = """
        微信支付
        11:01
        示例甲
        使用零钱支付
        账单详情＞
        · 9.90
        示例乙
        使用零钱支付
        · 3.00
        账单详情＞
        """
        let cards = try #require(parse(text))
        #expect(cards.map(\.cents) == [300])
        #expect(cards.map(\.merchant) == ["示例乙"])
    }

    @Test func aCardCutOffAtTheBottomIsSkipped() throws {
        let noAmount = """
        微信支付
        13:00
        示例小吃
        使用零钱支付
        ·55.00
        账单详情＞
        14:00
        示例超市
        使用零钱支付
        我的账单
        """
        let noFooter = """
        微信支付
        13:00
        示例小吃
        使用零钱支付
        ·55.00
        账单详情＞
        14:00
        示例超市
        使用零钱支付
        ·20.00
        我的账单
        """
        for text in [noAmount, noFooter] {
            let cards = try #require(parse(text))
            #expect(cards.map(\.cents) == [5500])
        }
    }

    @Test func contentAboveTheTitleCannotSupplyATime() throws {
        let text = """
        16:40
        微信支付
        使用零钱支付
        ·30.00
        查看账单详情
        13:00
        示例小吃
        使用零钱支付
        ·55.00
        账单详情＞
        """
        let cards = try #require(parse(text))
        #expect(cards.map(\.cents) == [5500])
    }

    @Test func aCardWithAnInvalidAmountIsSkippedAndTheRestAreKept() throws {
        let text = """
        微信支付
        12:00
        示例超市
        使用零钱支付
        ·0.00
        账单详情＞
        13:00
        示例小吃
        使用零钱支付
        ·55.00
        账单详情＞
        """
        let cards = try #require(parse(text))
        #expect(cards.map(\.cents) == [5500])
    }

    @Test func aSingleCharacterLineAboveTheMarkerIsNotAMerchant() throws {
        let text = """
        微信支付
        13:00
        收
        使用零钱支付
        ·55.00
        账单详情＞
        """
        let cards = try #require(parse(text))
        #expect(cards[0].merchant == nil)
        #expect(cards[0].note == "微信")
    }

    // MARK: 不该记的

    @Test func cardsWithoutAnExpenseMarkerAreSkipped() throws {
        let text = """
        微信支付
        13:00
        退款到账通知
        退款金额
        ·20.00
        账单详情＞
        """
        #expect(parse(text) == [])
    }

    @Test func onlyCutOffCardsGiveAnEmptyList() throws {
        let text = """
        微信支付
        收款方
        交易状态
        支付成功，对方已收款
        查看账单详情
        昨天18:23
        示例超市
        使用招商银行信用卡（0000）支付
        """
        #expect(parse(text) == [])
    }

    @Test func otherTextIsNotAListPage() {
        let detailPage = """
        账单
        全部账单
        示例超市
        -147.70
        当前状态
        支付成功
        支付时间
        2026年10月14日 18:23:27
        """
        let successPage = "♥支付成功\n示例商户\n¥0.20\n完成"
        let titleWithoutTimes = "微信支付\n已支付 ¥5.00"
        for text in [detailPage, successPage, titleWithoutTimes, "今天天气不错", ""] {
            #expect(parse(text) == nil, "\(text)")
        }
    }
}
