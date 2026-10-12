import Testing
import Foundation
@testable import HappySpendingCore

struct CSVExporterTests {
    private let cal = testCalendar
    private let headerLine = "日期,类型,金额,一级分类,二级分类,备注"

    /// 去掉 BOM 后的正文。
    private func body(_ rows: [EntryRow]) -> String {
        let text = String(decoding: CSVExporter.csv(rows, calendar: cal), as: UTF8.self)
        return String(text.dropFirst())
    }

    @Test func startsWithUTF8BOM() {
        let data = CSVExporter.csv([], calendar: cal)
        #expect(Array(data.prefix(3)) == [0xEF, 0xBB, 0xBF])
    }

    @Test func emptyExportIsJustTheHeader() {
        #expect(body([]) == headerLine + "\r\n")
    }

    @Test func rowMatchesTheDocumentedFormat() {
        let row = makeRow(
            cents: 2350, on: makeDate(2026, 10, 10),
            top: "餐饮", sub: "午餐", note: "牛肉面, 加蛋"
        )
        #expect(body([row]) == headerLine + "\r\n" + "2026-10-10,支出,23.50,餐饮,午餐,\"牛肉面, 加蛋\"\r\n")
    }

    @Test func incomeAndMissingSubcategoryAreWritten() {
        let row = makeRow(cents: 500000, kind: .income, on: makeDate(2026, 10, 1), top: "工资")
        #expect(body([row]) == headerLine + "\r\n" + "2026-10-01,收入,5000.00,工资,,\r\n")
    }

    @Test func quotesAreDoubled() {
        let row = makeRow(cents: 100, on: makeDate(2026, 10, 10), note: "他说\"好\"")
        #expect(body([row]).hasSuffix("2026-10-10,支出,1.00,餐饮,,\"他说\"\"好\"\"\"\r\n"))
    }

    @Test func newlinesInNotesStayInsideTheirField() {
        let lf = makeRow(cents: 100, on: makeDate(2026, 10, 10), note: "第一行\n第二行")
        #expect(body([lf]).hasSuffix("2026-10-10,支出,1.00,餐饮,,\"第一行\n第二行\"\r\n"))

        let crlf = makeRow(cents: 100, on: makeDate(2026, 10, 10), note: "a\r\nb")
        #expect(body([crlf]).hasSuffix("2026-10-10,支出,1.00,餐饮,,\"a\r\nb\"\r\n"))
    }

    @Test func emojiAndChineseSurviveTheRoundTrip() {
        let row = makeRow(cents: 100, on: makeDate(2026, 10, 10), top: "餐饮", note: "奶茶🧋 好喝")
        #expect(body([row]).contains("奶茶🧋 好喝"))
    }

    @Test func uncategorizedEntriesAreExportedWithThatName() {
        let row = EntryRow(
            date: makeDate(2026, 10, 10), kind: .expense, cents: 100,
            topCategoryID: nil, topCategoryName: Uncategorized.name, topColorHex: Uncategorized.colorHex
        )
        #expect(body([row]).contains("2026-10-10,支出,1.00,未分类,,"))
    }

    @Test func rowsAreExportedOldestFirst() {
        let later = makeRow(cents: 200, on: makeDate(2026, 10, 12))
        let earlier = makeRow(cents: 100, on: makeDate(2026, 10, 3))
        let lines = body([later, earlier]).components(separatedBy: "\r\n")
        #expect(lines[1].hasPrefix("2026-10-03"))
        #expect(lines[2].hasPrefix("2026-10-12"))
    }

    @Test func fileNamesDescribeTheScope() {
        #expect(CSVExporter.fileName(for: nil, calendar: cal) == "happy_spending-all.csv")
        #expect(CSVExporter.fileName(for: .month(makeDate(2026, 10, 15)), calendar: cal) == "happy_spending-2026-10.csv")
        #expect(CSVExporter.fileName(for: .year(2026), calendar: cal) == "happy_spending-2026.csv")
    }
}
