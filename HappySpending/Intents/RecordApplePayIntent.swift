import AppIntents
import SwiftData
import HappySpendingCore

/// 在快捷指令的错误提示里显示中文原因。
struct AutoRecordError: Error, CustomLocalizedStringResourceConvertible {
    let message: String
    var localizedStringResource: LocalizedStringResource { "\(message)" }
}

/// 快捷指令动作"记一笔(Apple Pay)"。通常由"钱包 → 交易"自动化调用。
/// 参数用文本,以便容错:快捷指令传来的金额是数字还是带符号的文本要等真机验证。
struct RecordApplePayIntent: AppIntent {
    static var title: LocalizedStringResource = "记一笔(Apple Pay)"
    static var description = IntentDescription(
        "把一笔 Apple Pay 消费记为支出。商户和金额通常来自快捷指令里“钱包 → 交易”自动化。"
    )
    static var openAppWhenRun: Bool = false

    static var parameterSummary: some ParameterSummary {
        Summary("记一笔 \(\.$merchant) \(\.$amount)")
    }

    // 可选:交易没有商户名时,快捷指令不会因为缺必填参数而卡住自动化。
    @Parameter(title: "商户")
    var merchant: String?

    @Parameter(title: "金额")
    var amount: String

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        do {
            let result = try AutoEntryRecorder.record(
                merchant: merchant ?? "",
                amountText: amount,
                in: SharedModelContainer.shared.mainContext
            )
            return .result(value: result.message)
        } catch let error as AmountError {
            throw AutoRecordError(message: error.message)
        } catch {
            throw AutoRecordError(message: "保存失败:\(error.localizedDescription)")
        }
    }
}
