import Foundation

/// 解析微信、支付宝的支付通知。两种通知都只有金额,没有商户名。
/// 认不出的(其他 app、聊天消息、退款等)一律是 `.unrecognized`,由调用方安静地忽略。
public enum NotificationPaymentParser {
    private static let amount = #"([0-9][0-9,]*(?:\.[0-9]+)?)"#

    public static func parse(title: String, body: String) -> ParseOutcome {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = body.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? body

        if title.contains("交易提醒") { return alipay(body) }
        if title.contains("微信支付") { return wechat(body) }
        return .unrecognized
    }

    /// `你有一笔 15.12 元的支出,领 2 元小荷包支付红包。`:锚定整句取金额,不取后面的促销数字。
    private static func alipay(_ body: String) -> ParseOutcome {
        guard let groups = TextMatch.captures(#"你有一笔\s*"# + amount + #"\s*元的(支出|收入)"#, in: body) else {
            return .unrecognized
        }
        if groups[2] == "收入" { return .ignored("收入") }
        guard let cents = try? AmountText.cents(from: groups[1]) else { return .unrecognized }
        return .payment(PaymentRecord(source: .notification, cents: cents, note: "支付宝"))
    }

    /// `已支付 ¥147.70`
    private static func wechat(_ body: String) -> ParseOutcome {
        guard let groups = TextMatch.captures(#"已支付\s*[¥￥]\s*"# + amount, in: body) else {
            return .unrecognized
        }
        guard let cents = try? AmountText.cents(from: groups[1]) else { return .unrecognized }
        return .payment(PaymentRecord(source: .notification, cents: cents, note: "微信支付"))
    }
}
