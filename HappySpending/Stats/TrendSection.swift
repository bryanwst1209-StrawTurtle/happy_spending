import SwiftUI
import Charts
import HappySpendingCore

enum StatsScope: String, CaseIterable, Identifiable {
    case month = "月"
    case year = "年"
    var id: String { rawValue }
}

struct TrendSection: View {
    let points: [TrendPoint]
    let scope: StatsScope

    private var unit: Calendar.Component { scope == .month ? .day : .month }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(scope == .month ? "每日支出" : "每月支出").font(.headline)
            Chart(points) { point in
                BarMark(
                    x: .value("日期", point.date, unit: unit),
                    y: .value("支出", Double(point.cents) / 100)
                )
                .foregroundStyle(Color.accentColor.gradient)
                .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: unit, count: scope == .month ? 5 : 1)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: scope == .month
                        ? Date.FormatStyle().day()
                        : Date.FormatStyle().month(.narrow))
                }
            }
            .frame(height: 180)
        }
    }
}
