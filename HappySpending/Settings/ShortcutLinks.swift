import SwiftUI
import HappySpendingCore

/// 一键添加用的快捷指令链接。在"快捷指令"里长按快捷指令(或进入自动化)→ 共享 → 拷贝 iCloud 链接,
/// 填在下面。留空的那一项不显示"一键添加"按钮,只显示手动步骤。
enum ShortcutLinks {
    /// 截图 → 提取文字 → 记一笔(屏幕识别)→ 显示通知。
    static let screenText = ShortcutLink.url(from: nil)
    /// 来自支付宝、标题包含"交易提醒"的通知自动化。
    static let alipayNotification = ShortcutLink.url(from: nil)
    /// 来自微信、标题包含"微信支付"的通知自动化。
    static let wechatNotification = ShortcutLink.url(from: nil)
}

/// 帮助页里的"一键添加"按钮:点了跳到快捷指令 app 的添加页面。
struct AddShortcutButton: View {
    let title: String
    let url: URL
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            openURL(url)
        } label: {
            Label(title, systemImage: "plus.circle.fill")
                .font(.body.weight(.semibold))
        }
    }
}
