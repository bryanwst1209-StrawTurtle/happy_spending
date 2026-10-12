import SwiftUI
import Charts
import HappySpendingCore

struct SharesSection: View {
    let title: String
    let shares: [CategoryShare]

    private var total: Int { shares.reduce(0) { $0 + $1.cents } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            if shares.isEmpty {
                Text("暂无数据").foregroundStyle(.secondary)
            } else {
                Chart(shares) { share in
                    SectorMark(
                        angle: .value("金额", share.cents),
                        innerRadius: .ratio(0.62),
                        angularInset: 1.5
                    )
                    .cornerRadius(4)
                    .foregroundStyle(Color(hex: share.colorHex))
                }
                .frame(height: 220)
                .overlay {
                    VStack(spacing: 2) {
                        Text("合计").font(.caption).foregroundStyle(.secondary)
                        Text(Money.display(total)).font(.title3.weight(.semibold).monospacedDigit())
                    }
                }

                VStack(spacing: 0) {
                    ForEach(shares) { share in
                        NavigationLink(value: share) {
                            HStack(spacing: 10) {
                                Circle().fill(Color(hex: share.colorHex)).frame(width: 10, height: 10)
                                Text(share.name)
                                Spacer()
                                Text(share.fraction.formatted(.percent.precision(.fractionLength(1))))
                                    .foregroundStyle(.secondary)
                                Text(Money.display(share.cents)).monospacedDigit()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
            }
        }
    }
}
