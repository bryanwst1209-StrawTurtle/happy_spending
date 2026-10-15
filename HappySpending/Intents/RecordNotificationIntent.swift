import AppIntents
import SwiftData
import HappySpendingCore

/// 快捷指令动作"记一笔(通知)":接收微信、支付宝支付通知的标题和正文并记一笔支出。
/// 由"收到通知时"自动化在后台调用,所以认不出的通知会安静地忽略,不报错。
struct RecordNotificationIntent: AppIntent {
    static var title: LocalizedStringResource = "记一笔(通知)"
    static var description = IntentDescription(
        "把微信、支付宝的支付通知记为一笔支出。通常由快捷指令里“收到通知时”的自动化调用,标题和正文接触发器给出的通知标题和通知正文。"
    )
    static var openAppWhenRun: Bool = false

    static var parameterSummary: some ParameterSummary {
        Summary("记一笔 \(\.$notificationTitle) \(\.$notificationBody)")
    }

    @Parameter(title: "通知标题")
    var notificationTitle: String

    @Parameter(title: "通知正文")
    var notificationBody: String

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        do {
            let result = try PaymentCapture.recordNotification(
                title: notificationTitle,
                body: notificationBody,
                in: SharedModelContainer.shared.mainContext
            )
            return .result(value: result.message)
        } catch let error as AmountError {
            throw AutoRecordError(message: error.message)
        } catch {
            throw AutoRecordError(message: "记账失败:\(error.localizedDescription)")
        }
    }
}
