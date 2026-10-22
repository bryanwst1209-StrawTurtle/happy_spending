import SwiftUI
import HappySpendingCore

/// 点账单页、统计页标题弹出的年月选择器;统计页年视图只选年份。
struct MonthPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let years: ClosedRange<Int>
    let yearOnly: Bool
    let now: Date
    let onPick: (Date) -> Void

    @State private var year: Int
    @State private var month: Int

    private let calendar = DayStamp.calendar

    init(current: Date, years: ClosedRange<Int>, yearOnly: Bool, now: Date, onPick: @escaping (Date) -> Void) {
        self.years = years
        self.yearOnly = yearOnly
        self.now = now
        self.onPick = onPick
        let components = DayStamp.calendar.dateComponents([.year, .month], from: current)
        _year = State(initialValue: min(max(components.year ?? years.upperBound, years.lowerBound), years.upperBound))
        _month = State(initialValue: components.month ?? 1)
    }

    /// 今年只能选到本月。
    private var months: ClosedRange<Int> { HistoryRange.months(in: year, now: now, calendar: calendar) }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                Picker("年", selection: $year) {
                    ForEach(Array(years), id: \.self) { Text(verbatim: "\($0)年").tag($0) }
                }
                .pickerStyle(.wheel)
                if !yearOnly {
                    Picker("月", selection: $month) {
                        ForEach(Array(months), id: \.self) { Text(verbatim: "\($0)月").tag($0) }
                    }
                    .pickerStyle(.wheel)
                }
            }
            .padding(.horizontal)
            .onChange(of: year) { month = min(month, months.upperBound) }
            .navigationTitle(yearOnly ? "选择年份" : "选择月份")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        // 年视图也保留原来的月份(夹在可选范围内),切回月视图时停在同一个月。
                        let picked = min(month, months.upperBound)
                        if let date = calendar.date(from: DateComponents(year: year, month: picked, day: 1)) {
                            onPick(date)
                        }
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.height(320)])
    }
}
