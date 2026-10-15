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

    public var message: String {
        switch self {
        case .notPaymentPage: "没有识别到支付页面"
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
    @discardableResult
    public static func recordScreenText(
        _ text: String,
        now: Date = .now,
        calendar: Calendar = .current,
        in context: ModelContext
    ) throws -> CaptureResult {
        switch ScreenTextParser.parse(text, calendar: calendar) {
        case .payment(let payment):
            return try record(payment, now: now, calendar: calendar, in: context)
        case .ignored(let reason):
            return CaptureResult(message: "已忽略:\(reason)", recorded: false)
        case .unrecognized:
            throw PaymentCaptureError.notPaymentPage
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
