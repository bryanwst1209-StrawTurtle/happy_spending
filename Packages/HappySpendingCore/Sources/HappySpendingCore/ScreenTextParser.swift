import Foundation

/// 解析"提取图像中的文字"识别出的微信、支付宝支付页文字。
/// 规则锚定关键词而不是行号,所以状态栏时间、电量、操作按钮的提示这类噪音行不影响结果。
public enum ScreenTextParser {
    private enum Page {
        case wechatBill, alipayBill, wechatSuccess
    }

    public static func parse(_ text: String, calendar: Calendar = .current) -> ParseOutcome {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        switch detectPage(lines) {
        case .wechatBill: return parseWeChatBill(lines, calendar: calendar)
        case .alipayBill: return parseAlipayBill(lines, calendar: calendar)
        case .wechatSuccess: return parseWeChatSuccess(lines)
        case nil: return .unrecognized
        }
    }

    // MARK: 判断是哪种页面

    /// 判断顺序:微信账单页 → 支付宝账单页 → 微信成功页。
    private static func detectPage(_ lines: [String]) -> Page? {
        func has(_ keyword: String) -> Bool { lines.contains { $0.contains(keyword) } }

        if has("当前状态") && (has("转账时间") || has("支付时间")) { return .wechatBill }
        if (has("账单详情") || has("交易详情")) && (has("付款方式") || has("支付时间")) { return .alipayBill }
        if has("支付成功") && lines.contains("完成") && !has("当前状态") { return .wechatSuccess }
        return nil
    }

    // MARK: 微信·支付成功页

    /// `支付成功` / `<商户>` / `¥0.20` / `完成`
    private static func parseWeChatSuccess(_ lines: [String]) -> ParseOutcome {
        guard let amountIndex = lines.firstIndex(where: { currencyAmount($0) != nil }),
              let amountText = currencyAmount(lines[amountIndex]),
              let cents = try? AmountText.cents(from: amountText)
        else { return .unrecognized }

        var merchant: String?
        if let statusIndex = lines.firstIndex(where: { $0.contains("支付成功") }), statusIndex < amountIndex {
            merchant = lines[(statusIndex + 1)..<amountIndex].lazy.compactMap(cleanMerchant).first
        }
        return .payment(PaymentRecord(
            source: .screenText, cents: cents, merchant: merchant, note: merchant ?? "微信"
        ))
    }

    // MARK: 微信·账单详情页

    private static func parseWeChatBill(_ lines: [String], calendar: Calendar) -> ParseOutcome {
        guard let signed = firstSignedAmount(lines) else { return .unrecognized }
        if signed.isIncome { return .ignored("收入") }
        guard let cents = try? AmountText.cents(from: signed.digits) else { return .unrecognized }

        // 转账页 `扫二维码付款-给X`:取"给"后面的收款方(收款人是表情、头像时识别出来是空的,就没有商户)。
        // 商户页没有这一行:商户名单独一行在金额上方。
        let payee = lines.lazy.compactMap { TextMatch.captures("^.+?[-－—–]给(.*)$", in: $0) }.first
        let merchant: String?
        if let payee {
            merchant = cleanMerchant(payee[1])
        } else {
            merchant = signed.index > 0 ? cleanMerchant(lines[signed.index - 1]) : nil
        }

        // 去重:时间读出来了就用"金额 + 分钟",和消息列表上的同一笔对得上;读不出来退回单号。
        let eventDate = dateTime(afterAnyLabel: ["转账时间", "支付时间"], in: lines, calendar: calendar)
        let orderRef = eventDate.map { WeChatPaymentKey.make(cents: cents, time: $0, calendar: calendar) }
            ?? digits(afterAnyLabel: ["转账单号", "交易单号"], in: lines)

        return .payment(PaymentRecord(
            source: .screenText,
            cents: cents,
            merchant: merchant,
            note: merchant ?? "微信",
            eventDate: eventDate,
            orderRef: orderRef
        ))
    }

    // MARK: 支付宝·账单详情页

    private static func parseAlipayBill(_ lines: [String], calendar: Calendar) -> ParseOutcome {
        guard let signed = firstSignedAmount(lines) else { return .unrecognized }
        if signed.isIncome { return .ignored("收入") }
        guard let cents = try? AmountText.cents(from: signed.digits) else { return .unrecognized }

        // 商户是金额的上一行;如果那一行只是导航文字就当没有商户。
        let merchant = signed.index > 0 ? cleanMerchant(lines[signed.index - 1]) : nil

        // 支付宝分类:整行(去掉结尾的 >)恰好是某个已知分类名,不依赖位置。
        let platformCategory = lines.lazy.compactMap { line -> String? in
            let name = line.trimmingCharacters(in: CharacterSet(charactersIn: ">＞›) "))
            return PlatformCategoryMap.alipay[name] != nil ? name : nil
        }.first

        // 订单号在首屏下方通常看不到:退而用"金额 + 精确到秒的支付时间"标识这一笔,
        // 这样在同一页连按两次也只记一次。
        let time = alipayDateTime(in: lines, calendar: calendar)
        let orderRef = digits(afterAnyLabel: ["订单号"], in: lines)
            ?? time.map { "支付宝|\(cents)|\($0.text)" }

        return .payment(PaymentRecord(
            source: .screenText,
            cents: cents,
            merchant: merchant,
            note: merchant ?? "支付宝",
            eventDate: time?.date,
            orderRef: orderRef,
            platformCategory: platformCategory
        ))
    }

    // MARK: 金额行

    /// 统一全角/半角,并把各种减号归成 `-`。
    private static func normalized(_ line: String) -> String {
        (line.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? line)
            .replacingOccurrences(of: "\u{2212}", with: "-")
            .trimmingCharacters(in: .whitespaces)
    }

    /// `¥0.20` / `￥0.20` / `Y0.20` 这样的整行金额,返回数字部分。
    private static func currencyAmount(_ line: String) -> String? {
        TextMatch.captures("^[\u{00A5}\u{FFE5}Y]\\s*([0-9][0-9,]*(?:\\.[0-9]+)?)$", in: normalized(line))?[1]
    }

    private struct SignedAmount {
        let index: Int
        let isIncome: Bool
        let digits: String
    }

    /// 第一行形如 `-15.12` / `+15.12` 的整行金额。
    private static func firstSignedAmount(_ lines: [String]) -> SignedAmount? {
        for (index, line) in lines.enumerated() {
            if let groups = TextMatch.captures("^([+-])\\s*([0-9][0-9,]*(?:\\.[0-9]+)?)$", in: normalized(line)) {
                return SignedAmount(index: index, isIncome: groups[1] == "+", digits: groups[2])
            }
        }
        return nil
    }

    // MARK: 商户

    private static let decoration = CharacterSet(charactersIn: "•●·・○◦♥★☆■□◆◇—-_:： \t")
    private static let navigationWords: Set<String> = ["<", "‹", "账单详情", "交易详情", "详情", "账单", "全部账单"]

    /// 去掉两端的圆点、符号;空串或纯导航文字返回 nil。
    private static func cleanMerchant(_ line: String) -> String? {
        let value = line.trimmingCharacters(in: decoration)
        return value.isEmpty || navigationWords.contains(value) ? nil : value
    }

    // MARK: 时间与单号

    /// 在标签所在行或它的下一行里找日期时间。
    private static func dateTime(afterAnyLabel labels: [String], in lines: [String], calendar: Calendar) -> Date? {
        for (index, line) in lines.enumerated() where labels.contains(where: { line.contains($0) }) {
            let candidates = [line] + (index + 1 < lines.count ? [lines[index + 1]] : [])
            for candidate in candidates {
                if let date = parseDateTime(candidate, calendar: calendar) { return date }
            }
        }
        return nil
    }

    /// 支付宝的时间没有固定标签,直接找 `yyyy-MM-dd HH:mm:ss`。
    /// 返回解析出的时间和它在页面上的原文(原文用来生成单号)。
    private static func alipayDateTime(in lines: [String], calendar: Calendar) -> (date: Date, text: String)? {
        for line in lines {
            if let groups = TextMatch.captures("(\\d{4}-\\d{2}-\\d{2}\\s+\\d{2}:\\d{2}:\\d{2})", in: line),
               let date = parseDateTime(groups[1], calendar: calendar) {
                return (date, groups[1])
            }
        }
        return nil
    }

    /// 允许日期里夹杂几个分隔字符(`2026年10月14日 17:37:40`),并**校验**每一项:
    /// 识别错误产生的不可能的日期返回 nil,而不是被日历悄悄进位成别的日子。
    /// 分隔符一般不能是字母:识别常把 0、1 认成 O、l,被分隔符吞掉就会落到别的月份。
    /// 例外是 F、E:真实样本里"月""日"会被识别成这两个字母(`2026·10F14E`),它们不像数字。
    private static func parseDateTime(_ text: String, calendar: Calendar) -> Date? {
        let separator = "(?:[^0-9A-Za-z]|[EF])"
        let pattern = "(\\d{4})\(separator){1,3}(\\d{1,2})\(separator){1,3}(\\d{1,2})\(separator){0,3}(\\d{1,2}):(\\d{2})(?::(\\d{2}))?"
        guard let g = TextMatch.captures(pattern, in: text),
              let year = Int(g[1]), let month = Int(g[2]), let day = Int(g[3]),
              let hour = Int(g[4]), let minute = Int(g[5])
        else { return nil }
        let second = Int(g[6]) ?? 0

        guard (1...12).contains(month), (1...31).contains(day),
              (0...23).contains(hour), (0...59).contains(minute), (0...59).contains(second)
        else { return nil }

        let components = DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute, second: second
        )
        guard let date = calendar.date(from: components) else { return nil }
        let back = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        guard back.year == year, back.month == month, back.day == day else { return nil }
        return date
    }

    /// 标签下一行(或标签行自身)里的数字串,至少 10 位才算单号。
    private static func digits(afterAnyLabel labels: [String], in lines: [String]) -> String? {
        for (index, line) in lines.enumerated() where labels.contains(where: { line.contains($0) }) {
            let candidates = [line] + (index + 1 < lines.count ? [lines[index + 1]] : [])
            for candidate in candidates {
                let value = candidate.filter(\.isNumber)
                if value.count >= 10 { return value }
            }
        }
        return nil
    }
}
