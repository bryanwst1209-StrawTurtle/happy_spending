import SwiftUI

struct AutoRecordHelpView: View {
    var body: some View {
        List {
            Section {
                Text("三种方式帮你自动记支出,账单里都带“自动”标记:刷钱包里的卡(Apple Pay)、在微信/支付宝里直接付款(屏幕识别)、在其他 app 里用微信/支付宝付款(通知)。每种设置一次就行。")
            } header: {
                Text("它做什么")
            }

            Section("① 刷钱包里的卡(Apple Pay)") {
                step(1, "打开系统的“快捷指令”app,切到底部的“自动化”。")
                step(2, "点右上角“+”,新建“个人自动化”,选择“钱包”下面的“交易”。")
                step(3, "选择要监控的卡,点“下一步”。")
                step(4, "添加操作,搜索“记一笔”,选择“记一笔(Apple Pay)”。")
                step(5, "把“商户”和“金额”两个参数分别设成触发器给出的“商户”和“金额”。")
                step(6, "运行方式选“立即运行”(不同系统版本这个选项的位置不同,可能在选好触发器之后,也可能是最后一页的“运行前先询问”开关,关掉它)。")
            }

            Section {
                step(1, "在“快捷指令”里新建一个普通快捷指令(不是自动化)。")
                step(2, "依次添加操作:“拍摄屏幕截图”→“提取图像中的文字”→“记一笔(屏幕识别)”,把“屏幕文字”参数设成上一步提取出的文字。")
                step(3, "把它设成操作按钮(设置 → 操作按钮 → 快捷指令),或轻点背面(设置 → 辅助功能 → 触控 → 轻点背面)。")
                step(4, "在微信或支付宝里付完款,停在“支付成功”页或“账单详情”页时按一下操作按钮或轻点背面。")
                Text("在微信、支付宝里直接付款时,这两个 app 在前台,系统不会发通知,所以要用这个办法。整个过程不会往相册里留图片。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("② 在微信/支付宝里直接付款(屏幕识别)")
            }

            Section {
                step(1, "在“快捷指令”的“自动化”里新建个人自动化,选择“通知”,来自“支付宝”,加筛选:标题 包含 交易提醒。")
                step(2, "再建一个,来自“微信”,加筛选:标题 包含 微信支付。")
                step(3, "运行方式选“立即运行”。添加操作“记一笔(通知)”,把“通知标题”和“通知正文”接触发器给出的通知标题和通知正文。")
                step(4, "这两个 app 的系统通知要开着,并且至少显示在“锁屏”或“通知中心”之一,只选“横幅”不行。")
                Text("这类通知里只有金额、没有商户名,所以账会先归“未分类”,需要你事后手动归类。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("③ 在其他 app 里用微信/支付宝付款(通知)")
            }

            Section("分类怎么来的") {
                Text("有商户名的账,你在账单里改过分类并保存后,app 会记住这个商户,以后同一商户直接用这个分类。支付宝账单页自带的分类(如“日用百货”)会按对应关系预填。其余先归“未分类”。")
            }

            Section("能覆盖什么") {
                Label("钱包里的卡刷卡付款(Apple Pay)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Label("微信、支付宝的支付(屏幕识别或通知)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Label("实体卡直接刷卡、银行 app 的通知:暂不支持", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }

            Section("隐私") {
                Text("app 不保存截图、识别出的原文和通知内容,只记下金额、商户、日期等解析结果。文字识别在手机本地进行。")
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
