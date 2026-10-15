import Foundation

/// 微信支付的去重标识:金额 + 精确到分钟的时间。
/// 消息列表和账单详情页都拿得到这两样,同一笔在两处记过都能认出来;
/// 商户不放进来,因为列表页可能认不出商户(样本里瑞幸的商户行没被识别)。
public enum WeChatPaymentKey {
    public static func make(cents: Int, time: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: time)
        let stamp = String(
            format: "%04d-%02d-%02d %02d:%02d",
            c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0
        )
        return "微信|\(cents)|\(stamp)"
    }
}
