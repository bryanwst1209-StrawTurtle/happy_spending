import AppIntents
import SwiftData
import HappySpendingCore

/// 快捷指令动作"记一笔(屏幕识别)":接收"提取图像中的文字"识别出的整段文字,
/// 解析微信、支付宝的支付页并记一笔支出。通常挂在操作按钮或轻点背面上。
struct RecordScreenTextIntent: AppIntent {
    static var title: LocalizedStringResource = "记一笔(屏幕识别)"
    static var description = IntentDescription(
        "识别微信、支付宝支付成功页、账单详情页或微信支付消息列表上的文字,把支出记下来。通常接在“拍摄屏幕截图”和“提取图像中的文字”后面。"
    )
    static var openAppWhenRun: Bool = false

    static var parameterSummary: some ParameterSummary {
        Summary("记一笔 \(\.$text)")
    }

    @Parameter(title: "屏幕文字")
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        do {
            let result = try PaymentCapture.recordScreenText(
                text, in: SharedModelContainer.shared.mainContext
            )
            return .result(value: result.message)
        } catch let error as PaymentCaptureError {
            throw AutoRecordError(message: error.message)
        } catch let error as AmountError {
            throw AutoRecordError(message: error.message)
        } catch {
            throw AutoRecordError(message: "记账失败:\(error.localizedDescription)")
        }
    }
}
