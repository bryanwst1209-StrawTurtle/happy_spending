import Foundation

/// 解析微信"微信支付"消息列表的识别文字。一屏可能有好几张支付卡片,记下其中**完整**的:
/// 上面有时间标签、有金额行、有支出标志,并以"账单详情"收尾。被截断的卡片跳过。
public enum WeChatListParser {
    /// 不是消息列表返回 nil;是列表但没有完整卡片返回空数组。
    public static func parse(_ text: String, now: Date, calendar: Calendar) -> [PaymentRecord]? {
        let all = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // 标题之上(状态栏时间等)全部忽略,免得被当成时间标签。
        guard let titleIndex = all.firstIndex(of: "微信支付") else { return nil }
        let lines = Array(all[(titleIndex + 1)...])
        guard lines.contains(where: { TimeLabel.resolve($0, now: now, calendar: calendar) != nil }) else {
            return nil
        }

        var records: [PaymentRecord] = []
        var time: Date?
        var segment: [String] = []
        for line in lines {
            if let label = TimeLabel.resolve(line, now: now, calendar: calendar) {
                time = label
                segment = []
            } else if TimeLabel.looksLikeTime(line) {
                // 认不出的时间标签:它下面的卡片宁可跳过,也不借用上一个标签的时间、悄悄记错日期。
                time = nil
                segment = []
            } else if line.hasPrefix("账单详情") || line.hasPrefix("查看账单详情") {
                // 一段到此结束;第一个时间标签之前的段(顶部截断的卡片)没有时间,跳过。
                if let time, let record = card(segment, time: time, calendar: calendar) {
                    records.append(record)
                }
                // 几笔挨得很近时微信只显示一个时间标签:后面的段沿用当前时间。
                segment = []
            } else {
                segment.append(line)
            }
        }
        // 最后一段没有"账单详情"收尾,是底部截断的卡片,不要。
        return records
    }

    // MARK: 一张卡片

    private static func card(_ lines: [String], time: Date, calendar: Calendar) -> PaymentRecord? {
        guard let markerIndex = lines.firstIndex(where: isExpenseMarker),
              // 金额只取支出标志之后的:识别偶尔把上一张卡的行挪到"账单详情"后面,不能借来当金额。
              let amountText = lines[(markerIndex + 1)...].lazy.compactMap(amount).first,
              let cents = try? AmountText.cents(from: amountText)
        else { return nil }

        let merchant = markerIndex > 0 ? merchantName(lines[markerIndex - 1]) : nil
        return PaymentRecord(
            source: .screenText,
            cents: cents,
            merchant: merchant,
            note: merchant ?? "微信",
            eventDate: time,
            orderRef: WeChatPaymentKey.make(cents: cents, time: time, calendar: calendar)
        )
    }

    /// 支出卡片才有的那一行:"使用…支付"、"通过…自动续费/扣费/支付"、"微信支付凭证"。
    private static func isExpenseMarker(_ line: String) -> Bool {
        if line == "微信支付凭证" { return true }
        if line.hasPrefix("使用") && line.contains("支付") { return true }
        if line.hasPrefix("通过") { return ["自动续费", "扣费", "支付"].contains { line.contains($0) } }
        return false
    }

    /// 整行金额:`· 9.90`、`·147.70`、`¥0.20`、`￥0.20`、`Y0.20`("¥"常被识别成各种圆点)。
    private static func amount(_ line: String) -> String? {
        let normalized = line.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? line
        let symbols = "\u{00A5}\u{FFE5}Y\u{00B7}\u{2022}\u{30FB}\u{FF65}"
        return TextMatch.captures("^[\(symbols)]\\s*([0-9][0-9,]*(?:\\.[0-9]+)?)$", in: normalized)?[1]
    }

    // MARK: 商户

    /// 卡片里的标签和操作行;它们紧挨在下一张卡的支出标志上方时(商户行没识别出来),不能当成商户。
    private static let labels: Set<String> = [
        "续费项目", "开通账号", "收款方", "交易状态", "微信支付凭证", "微信代扣", "对订单有疑惑", "进入商家小程序",
    ]
    private static let decoration = CharacterSet(charactersIn: "•●·・○◦♥★☆■□◆◇—-_:：> \t")

    /// 支出标志的上一行;是标签或操作行、空的,或只有一个字(logo 被识别成的"收")就当没有商户。
    private static func merchantName(_ line: String) -> String? {
        let value = line.trimmingCharacters(in: decoration)
        return value.count <= 1 || labels.contains(value) ? nil : value
    }
}
