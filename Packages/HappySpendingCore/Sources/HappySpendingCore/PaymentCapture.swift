import Foundation
import SwiftData

public struct CaptureResult: Equatable, Sendable {
    /// 给快捷指令显示的一句话。
    public let message: String
    /// 是否新记了一笔。
    public let recorded: Bool
}

public enum PaymentCaptureError: Error, Equatable, LocalizedError {
    case notPaymentPage
    /// 认出是微信支付消息列表,但这一屏的卡片都被截断了。
    case noCompleteCard

    public var message: String {
        switch self {
        case .notPaymentPage: "没有识别到支付页面"
        case .noCompleteCard: "这一屏没有完整的支付记录"
        }
    }

    public var errorDescription: String? { message }
}

/// 快捷指令动作调用的入口:解析文字、记账、决定给用户什么反馈。
public enum PaymentCapture {
    /// 通知:在后台自动运行,所以认不出或被忽略时**安静地成功返回**,不抛错,避免无关通知弹出错误。
    @discardableResult
    public static func recordNotification(
        title: String,
        body: String,
        now: Date = .now,
        calendar: Calendar = .current,
        in context: ModelContext
    ) throws -> CaptureResult {
        switch NotificationPaymentParser.parse(title: title, body: body) {
        case .payment(let payment):
            return try record(payment, now: now, calendar: calendar, in: context)
        case .ignored(let reason):
            return CaptureResult(message: "已忽略:\(reason)", recorded: false)
        case .unrecognized:
            return CaptureResult(message: "已忽略:不是支付通知", recorded: false)
        }
    }

    /// 屏幕识别:是用户主动触发的,认不出支付页面时**抛错**,让用户知道没记上。
    /// 先看是不是微信支付消息列表(一屏多笔);不是再按单个支付页解析。
    @discardableResult
    public static func recordScreenText(
        _ text: String,
        now: Date = .now,
        calendar: Calendar = .current,
        in context: ModelContext
    ) throws -> CaptureResult {
        if let cards = WeChatListParser.parse(text, now: now, calendar: calendar) {
            return try recordList(cards, now: now, calendar: calendar, in: context)
        }
        switch ScreenTextParser.parse(text, calendar: calendar) {
        case .payment(let payment):
            return try record(payment, now: now, calendar: calendar, in: context)
        case .ignored(let reason):
            return CaptureResult(message: "已忽略:\(reason)", recorded: false)
        case .unrecognized:
            throw PaymentCaptureError.notPaymentPage
        }
    }

    /// 逐笔记账;中途保存失败就抛错,前面已保存的留着(再按一次会被去重)。
    private static func recordList(
        _ cards: [PaymentRecord],
        now: Date,
        calendar: Calendar,
        in context: ModelContext
    ) throws -> CaptureResult {
        guard !cards.isEmpty else { throw PaymentCaptureError.noCompleteCard }
        var fresh: [AutoEntryResult] = []
        var duplicates = 0
        for card in cards {
            let result = try AutoEntryRecorder.record(card, now: now, calendar: calendar, in: context)
            if result.isDuplicate { duplicates += 1 } else { fresh.append(result) }
        }
        return CaptureResult(message: listMessage(fresh: fresh, duplicates: duplicates), recorded: !fresh.isEmpty)
    }

    /// 一次记多笔时给快捷指令的一句话。
    static func listMessage(fresh: [AutoEntryResult], duplicates: Int) -> String {
        let total = Money.display(fresh.reduce(0) { $0 + $1.cents })
        switch (fresh.count, duplicates) {
        case (0, 1): return "已记过这一笔"
        case (0, let d): return "这一屏的 \(d) 笔都记过了"
        case (1, 0): return fresh[0].message
        case (let n, 0): return "已记 \(n) 笔,共 \(total)"
        case (1, let d): return "已记 1 笔 \(total),\(d) 笔已记过"
        case (let n, let d): return "已记 \(n) 笔,共 \(total),\(d) 笔已记过"
        }
    }

    private static func record(
        _ payment: PaymentRecord,
        now: Date,
        calendar: Calendar,
        in context: ModelContext
    ) throws -> CaptureResult {
        let result = try AutoEntryRecorder.record(payment, now: now, calendar: calendar, in: context)
        return CaptureResult(message: result.message, recorded: !result.isDuplicate)
    }
}
