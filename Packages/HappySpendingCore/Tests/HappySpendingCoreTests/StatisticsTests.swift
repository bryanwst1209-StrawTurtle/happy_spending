import Testing
import Foundation
@testable import HappySpendingCore

struct StatisticsTests {
    private let cal = testCalendar

    // MARK: Period

    @Test func monthPeriodIsHalfOpenAtBothEnds() {
        let rows = [
            makeRow(cents: 1, on: makeDate(2026, 9, 30, 23, 59)),
            makeRow(cents: 2, on: makeDate(2026, 10, 1, 0, 0)),
            makeRow(cents: 4, on: makeDate(2026, 10, 31, 23, 59)),
            makeRow(cents: 8, on: makeDate(2026, 11, 1, 0, 0)),
        ]
        let filtered = Period.month(makeDate(2026, 10, 15)).filter(rows, calendar: cal)
        #expect(filtered.map(\.cents) == [2, 4])
    }

    @Test func yearPeriodSeparatesDecemberFromNextJanuary() {
        let rows = [
            makeRow(cents: 1, on: makeDate(2025, 12, 31, 23, 59)),
            makeRow(cents: 2, on: makeDate(2026, 1, 1, 0, 0)),
            makeRow(cents: 4, on: makeDate(2026, 12, 31, 23, 59)),
            makeRow(cents: 8, on: makeDate(2027, 1, 1, 0, 0)),
        ]
        let filtered = Period.year(2026).filter(rows, calendar: cal)
        #expect(filtered.map(\.cents) == [2, 4])
    }

    // MARK: summary

    @Test func summaryAddsIncomeAndExpenseSeparately() {
        let d = makeDate(2026, 10, 10)
        let rows = [
            makeRow(cents: 1000, on: d),
            makeRow(cents: 250, on: d),
            makeRow(cents: 5000, kind: .income, on: d, top: "工资"),
        ]
        let summary = Statistics.summary(rows)
        #expect(summary.incomeCents == 5000)
        #expect(summary.expenseCents == 1250)
        #expect(summary.balanceCents == 3750)
    }

    @Test func summaryOfNothingIsZero() {
        let summary = Statistics.summary([])
        #expect(summary.incomeCents == 0)
        #expect(summary.expenseCents == 0)
        #expect(summary.balanceCents == 0)
    }

    @Test func balanceCanBeNegative() {
        let rows = [makeRow(cents: 300, on: makeDate(2026, 10, 10))]
        #expect(Statistics.summary(rows).balanceCents == -300)
    }

    // MARK: shares

    @Test func sharesGroupByTopLevelWithSubcategoryDetail() {
        let d = makeDate(2026, 10, 10)
        let rows = [
            makeRow(cents: 3000, on: d, top: "餐饮", sub: "午餐"),
            makeRow(cents: 1000, on: d, top: "餐饮", sub: "晚餐"),
            makeRow(cents: 1000, on: d, top: "餐饮"),
            makeRow(cents: 2000, on: d, top: "交通"),
        ]
        let shares = Statistics.shares(rows, kind: .expense)

        #expect(shares.map(\.name) == ["餐饮", "交通"])
        #expect(shares[0].cents == 5000)
        #expect(abs(shares[0].fraction - 5.0 / 7.0) < 1e-9)
        #expect(abs(shares.map(\.fraction).reduce(0, +) - 1.0) < 1e-9)

        let children = shares[0].children
        #expect(children.map(\.name) == ["午餐", "晚餐", "未细分"])
        #expect(children.map(\.cents) == [3000, 1000, 1000])
        #expect(abs(children[0].fraction - 0.6) < 1e-9)
        #expect(children[2].id == nil)
        #expect(shares[1].children.map(\.name) == ["未细分"])
    }

    @Test func sharesOnlyCountTheRequestedKind() {
        let d = makeDate(2026, 10, 10)
        let rows = [
            makeRow(cents: 100, on: d, top: "餐饮"),
            makeRow(cents: 9000, kind: .income, on: d, top: "工资"),
        ]
        #expect(Statistics.shares(rows, kind: .expense).map(\.name) == ["餐饮"])
        #expect(Statistics.shares(rows, kind: .income).map(\.name) == ["工资"])
    }

    @Test func sharesOfNothingIsEmptyNotNaN() {
        #expect(Statistics.shares([], kind: .expense).isEmpty)
        let onlyIncome = [makeRow(cents: 100, kind: .income, on: makeDate(2026, 10, 10), top: "工资")]
        #expect(Statistics.shares(onlyIncome, kind: .expense).isEmpty)
    }

    @Test func sameNamedCategoriesWithDifferentIDsStaySeparate() {
        let d = makeDate(2026, 10, 10)
        let rows = [
            makeRow(cents: 100, on: d, top: "其他", topID: UUID()),
            makeRow(cents: 200, on: d, top: "其他", topID: UUID()),
        ]
        let shares = Statistics.shares(rows, kind: .expense)
        #expect(shares.count == 2)
        #expect(shares.map(\.cents) == [200, 100])
    }

    @Test func entriesWithoutACategoryFormAnUncategorizedShare() {
        let row = EntryRow(
            date: makeDate(2026, 10, 10), kind: .expense, cents: 500,
            topCategoryID: nil, topCategoryName: Uncategorized.name, topColorHex: Uncategorized.colorHex
        )
        let shares = Statistics.shares([row], kind: .expense)
        #expect(shares.count == 1)
        #expect(shares[0].name == "未分类")
        #expect(shares[0].id == nil)
    }

    // MARK: daily trend

    @Test func dailyTrendHasOnePointPerDayAndFillsZeros() {
        let rows = [
            makeRow(cents: 100, on: makeDate(2026, 10, 1)),
            makeRow(cents: 400, on: makeDate(2026, 10, 1, 18, 0)),
        ]
        let points = Statistics.dailyTrend(rows, month: makeDate(2026, 10, 15), calendar: cal)

        #expect(points.count == 31)
        #expect(points.first?.date == makeDate(2026, 10, 1))
        #expect(points.last?.date == makeDate(2026, 10, 31))
        #expect(points[0].cents == 500)
        #expect(points[1].cents == 0)
    }

    @Test func dailyTrendRespectsMonthBoundaries() {
        let rows = [
            makeRow(cents: 700, on: makeDate(2026, 10, 31, 23, 59)),
            makeRow(cents: 900, on: makeDate(2026, 11, 1, 0, 0)),
            makeRow(cents: 50, on: makeDate(2026, 9, 30, 23, 59)),
        ]
        let points = Statistics.dailyTrend(rows, month: makeDate(2026, 10, 15), calendar: cal)

        #expect(points[30].cents == 700)
        #expect(points.map(\.cents).reduce(0, +) == 700)
    }

    @Test func dailyTrendOnlyCountsTheRequestedKind() {
        let rows = [
            makeRow(cents: 100, on: makeDate(2026, 10, 5)),
            makeRow(cents: 9000, kind: .income, on: makeDate(2026, 10, 5), top: "工资"),
        ]
        let points = Statistics.dailyTrend(rows, month: makeDate(2026, 10, 1), calendar: cal)
        #expect(points[4].cents == 100)
    }

    @Test func dailyTrendKnowsLeapYears() {
        #expect(Statistics.dailyTrend([], month: makeDate(2028, 2, 10), calendar: cal).count == 29)
        #expect(Statistics.dailyTrend([], month: makeDate(2027, 2, 10), calendar: cal).count == 28)
    }

    @Test func dailyTrendOfAnEmptyMonthIsAllZeros() {
        let points = Statistics.dailyTrend([], month: makeDate(2026, 10, 1), calendar: cal)
        #expect(points.count == 31)
        #expect(points.allSatisfy { $0.cents == 0 })
    }

    // MARK: monthly trend

    @Test func monthlyTrendHasTwelvePointsAndRespectsYearBoundaries() {
        let rows = [
            makeRow(cents: 200, on: makeDate(2026, 1, 15)),
            makeRow(cents: 50, on: makeDate(2026, 12, 1)),
            makeRow(cents: 300, on: makeDate(2026, 12, 31, 23, 59)),
            makeRow(cents: 900, on: makeDate(2027, 1, 1, 0, 0)),
            makeRow(cents: 7, on: makeDate(2025, 12, 31, 23, 59)),
        ]
        let points = Statistics.monthlyTrend(rows, year: 2026, calendar: cal)

        #expect(points.count == 12)
        #expect(points.first?.date == makeDate(2026, 1, 1))
        #expect(points.last?.date == makeDate(2026, 12, 1))
        #expect(points[0].cents == 200)
        #expect(points[11].cents == 350)
        #expect(points.map(\.cents).reduce(0, +) == 550)
    }

    @Test func monthlyTrendOfAnEmptyYearIsAllZeros() {
        let points = Statistics.monthlyTrend([], year: 2026, calendar: cal)
        #expect(points.count == 12)
        #expect(points.allSatisfy { $0.cents == 0 })
    }
}
