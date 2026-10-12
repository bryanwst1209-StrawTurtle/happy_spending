import SwiftUI
import SwiftData
import HappySpendingCore

struct StatsView: View {
    @Query(sort: \LedgerEntry.date) private var entries: [LedgerEntry]
    @State private var scope: StatsScope = .month
    @State private var anchor = DayStamp.stamp(.now)

    private let calendar = DayStamp.calendar

    private var year: Int { calendar.component(.year, from: anchor) }
    private var period: Period { scope == .month ? .month(anchor) : .year(year) }
    private var rows: [EntryRow] { period.filter(entries.map(\.row), calendar: calendar) }
    private var title: String {
        scope == .month
            ? BillsLogic.monthTitle(anchor, calendar: calendar)
            : "\(year)年"
    }
    private var trend: [TrendPoint] {
        scope == .month
            ? Statistics.dailyTrend(rows, month: anchor, calendar: calendar)
            : Statistics.monthlyTrend(rows, year: year, calendar: calendar)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                StatsBackground().ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        controls
                        SummaryCard(summary: Statistics.summary(rows))
                        if rows.isEmpty {
                            ContentUnavailableView("这段时间还没有账单", systemImage: "chart.pie")
                        } else {
                            SharesSection(title: "支出分类", shares: Statistics.shares(rows, kind: .expense))
                            TrendSection(points: trend, scope: scope)
                            DisclosureGroup("收入分类") {
                                SharesSection(title: "", shares: Statistics.shares(rows, kind: .income))
                                    .padding(.top, 8)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("统计")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: CategoryShare.self) { CategoryDetailView(share: $0) }
        }
    }

    private var controls: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(spacing: 12) {
                Picker("周期", selection: $scope) {
                    ForEach(StatsScope.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                PeriodSwitcher(title: title, onPrevious: { shift(-1) }, onNext: { shift(1) })
            }
            .padding(14)
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
        }
    }

    private func shift(_ delta: Int) {
        let component: Calendar.Component = scope == .month ? .month : .year
        anchor = calendar.date(byAdding: component, value: delta, to: anchor) ?? anchor
    }
}
