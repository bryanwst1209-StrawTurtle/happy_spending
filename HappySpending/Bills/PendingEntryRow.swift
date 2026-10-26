import SwiftUI

/// 账单页顶部的"待归类 N 笔 ›"。
struct PendingEntryRow: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Section {
            Button(action: action) {
                HStack {
                    Label("待归类 \(count) 笔", systemImage: "tray.full")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .appRowBackground()
        }
    }
}
