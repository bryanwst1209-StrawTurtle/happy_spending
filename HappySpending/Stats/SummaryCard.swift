import SwiftUI
import HappySpendingCore

struct SummaryCard: View {
    let summary: PeriodSummary

    var body: some View {
        HStack {
            cell("收入", summary.incomeCents, .green)
            cell("支出", summary.expenseCents, .primary)
            cell("结余", summary.balanceCents, .primary)
        }
        .padding(.vertical, 18)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    private func cell(_ title: String, _ cents: Int, _ color: Color) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(Money.display(cents))
                .font(.headline.monospacedDigit())
                .foregroundStyle(color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}
