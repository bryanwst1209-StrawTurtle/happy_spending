import SwiftUI
import SwiftData
import HappySpendingCore

struct StatsView: View {
    @Query(LedgerQueries.earliest()) private var earliest: [LedgerEntry]
    @State private var scope: StatsScope = .month
    @State private var anchor = DayStamp.stamp(.now)
    @State private var picking = false

    private let calendar = DayStamp.calendar

    private var now: Date { DayStamp.stamp(.now) }
    private var year: Int { calendar.component(.year, from: anchor) }
    private var period: Period { scope == .month ? .month(anchor) : .year(year) }
    private var isCurrent: Bool { HistoryRange.isCurrent(period, now: now, calendar: calendar) }
    private var title: String {
        scope == .month
            ? BillsLogic.monthTitle(anchor, calendar: calendar)
            : "\(year)年"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                StatsBackground().ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        controls
                        StatsPeriodContent(period: period, anchor: anchor, scope: scope)
                    }
                    .padding()
                }
            }
            .navigationTitle("统计")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: CategoryShare.self) { CategoryDetailView(share: $0) }
            .sheet(isPresented: $picking) {
                MonthPickerSheet(
                    current: anchor,
                    years: HistoryRange.years(earliest: earliest.first?.date, now: now, calendar: calendar),
                    yearOnly: scope == .year,
                    now: now
                ) { anchor = $0 }
            }
        }
    }

    private var controls: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(spacing: 12) {
                Picker("周期", selection: $scope) {
                    ForEach(StatsScope.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                PeriodSwitcher(
                    title: title,
                    isNextDisabled: isCurrent,
                    backTitle: isCurrent ? nil : (scope == .month ? "回到本月" : "回到今年"),
                    onTitleTap: { picking = true },
                    onBack: { anchor = now },
                    onPrevious: { shift(-1) },
                    onNext: { shift(1) }
                )
            }
            .padding(14)
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
        }
    }

    private func shift(_ delta: Int) {
        // 已经是当前月(或今年)时 › 置灰;这里再拦一次,不翻到未来。
        guard delta < 0 || !isCurrent else { return }
        let component: Calendar.Component = scope == .month ? .month : .year
        anchor = HistoryRange.shift(anchor, by: delta, component, now: now, calendar: calendar)
    }
}

/// 统计页的内容:只从数据库查所选月份或年份的账。
struct StatsPeriodContent: View {
    @Query private var entries: [LedgerEntry]

    let anchor: Date
    let scope: StatsScope

    private let calendar = DayStamp.calendar

    init(period: Period, anchor: Date, scope: StatsScope) {
        self.anchor = anchor
        self.scope = scope
        _entries = Query(LedgerQueries.entries(in: period, calendar: DayStamp.calendar))
    }

    private var rows: [EntryRow] { entries.map(\.row) }
    private var year: Int { calendar.component(.year, from: anchor) }
    private var trend: [TrendPoint] {
        scope == .month
            ? Statistics.dailyTrend(rows, month: anchor, calendar: calendar)
            : Statistics.monthlyTrend(rows, year: year, calendar: calendar)
    }

    var body: some View {
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
}
