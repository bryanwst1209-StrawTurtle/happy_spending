/// 自动账的来源。账单行上都显示同一个"自动"标记。
public enum EntrySource: String, Codable, Sendable {
    /// Apple Pay("钱包 → 交易"自动化)。
    case applePay
    /// 微信、支付宝的支付页:用户触发"拍摄屏幕截图 → 提取文字"后交给 app 解析。
    case screenText
    /// 微信、支付宝的支付通知("收到通知时"自动化)。
    case notification
}
