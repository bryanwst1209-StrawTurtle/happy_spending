import SwiftUI

/// 账单页、统计页顶部的"‹ 2026年10月 ›"。点标题可以跳到任意月份,已在当前月时 › 置灰。
struct PeriodSwitcher: View {
    let title: String
    var isNextDisabled: Bool
    /// 不在当前月(或今年)时显示的"回到本月 / 回到今年";nil 时不显示。
    var backTitle: String?
    var onTitleTap: (() -> Void)?
    var onBack: (() -> Void)?
    let onPrevious: () -> Void
    let onNext: () -> Void

    init(
        title: String,
        isNextDisabled: Bool = false,
        backTitle: String? = nil,
        onTitleTap: (() -> Void)? = nil,
        onBack: (() -> Void)? = nil,
        onPrevious: @escaping () -> Void,
        onNext: @escaping () -> Void
    ) {
        self.title = title
        self.isNextDisabled = isNextDisabled
        self.backTitle = backTitle
        self.onTitleTap = onTitleTap
        self.onBack = onBack
        self.onPrevious = onPrevious
        self.onNext = onNext
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Button(action: onPrevious) { Image(systemName: "chevron.left") }
                    .buttonStyle(.glass)
                Spacer()
                // 这一行可能放在 List 里:List 行内任何一个按钮用了 `.disabled`,整行的按钮都会点不动,
                // 所以这里不用 `.disabled`,而是变淡并且不接收点击。
                if let onTitleTap {
                    Button(action: onTitleTap) {
                        HStack(spacing: 4) {
                            Text(title).font(.headline)
                            Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(title).font(.headline)
                }
                Spacer()
                Button(action: onNext) { Image(systemName: "chevron.right") }
                    .buttonStyle(.glass)
                    .opacity(isNextDisabled ? 0.35 : 1)
                    .allowsHitTesting(!isNextDisabled)
            }
            if let backTitle, let onBack {
                Button(backTitle, action: onBack)
                    .font(.footnote)
                    .buttonStyle(.borderless)
            }
        }
    }
}
