import Foundation

/// 解析器统一的输出:从通知、屏幕文字里提取出的一笔支出。不入库。
public struct PaymentRecord: Equatable, Sendable {
    public let source: EntrySource
    /// 金额,整数分,大于 0。
    public let cents: Int
    /// 商户名;没有就是 nil。
    public let merchant: String?
    /// 账单备注:有商户用商户名,没有就用渠道名("微信""支付宝""微信支付")。
    public let note: String
    /// 页面上的支付时间;读不出就是 nil(入账时取触发时刻)。
    public let eventDate: Date?
    /// 单号原文(写库前会做哈希)。
    public let orderRef: String?
    /// 支付宝账单页上的分类名,如"日用百货"。
    public let platformCategory: String?

    public init(
        source: EntrySource,
        cents: Int,
        merchant: String? = nil,
        note: String,
        eventDate: Date? = nil,
        orderRef: String? = nil,
        platformCategory: String? = nil
    ) {
        self.source = source
        self.cents = cents
        self.merchant = merchant
        self.note = note
        self.eventDate = eventDate
        self.orderRef = orderRef
        self.platformCategory = platformCategory
    }
}

public enum ParseOutcome: Equatable, Sendable {
    /// 识别出一笔支出。
    case payment(PaymentRecord)
    /// 认得出,但不该记(收入等),附原因。
    case ignored(String)
    /// 认不出是支付通知或支付页面。
    case unrecognized
}
