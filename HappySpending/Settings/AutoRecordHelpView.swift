import SwiftUI

struct AutoRecordHelpView: View {
    var body: some View {
        List {
            Section {
                Text("用 Apple Pay(含加入 Apple Pay 的银行卡)付款后,app 会自动记一笔支出,账单里带“自动”标记。")
            } header: {
                Text("它做什么")
            }

            Section("怎么设置(只需要一次)") {
                step(1, "打开系统的“快捷指令”app,切到底部的“自动化”。")
                step(2, "点右上角“+”,新建“个人自动化”,选择“钱包”下面的“交易”。")
                step(3, "选择要监控的卡,点“下一步”。")
                step(4, "添加操作,搜索“记一笔”,选择“记一笔(Apple Pay)”。")
                step(5, "把“商户”和“金额”两个参数分别设成触发器给出的“商户”和“金额”(点参数框,在变量里选)。")
                step(6, "在最后一页把“运行前先询问”关掉,点“完成”。")
            }

            Section {
                Text("想在记账后收到提醒:在动作后面再加一步“显示通知”,内容选“记一笔”的输出结果。")
            } header: {
                Text("可选:记账提醒")
            }

            Section("分类怎么来的") {
                Text("自动记的账先归“未分类”。你在账单里点开它、改成某个分类并保存后,app 会记住这个商户,以后同一商户的自动账会直接用这个分类。")
            }

            Section("能覆盖什么") {
                Label("Apple Pay 和加入 Apple Pay 的银行卡", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Label("微信支付、支付宝、直接刷实体卡:iOS 不允许 app 读取这些支付,无法自动记", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("自动入账")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.footnote.weight(.semibold))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor.opacity(0.15)))
            Text(text)
        }
    }
}
