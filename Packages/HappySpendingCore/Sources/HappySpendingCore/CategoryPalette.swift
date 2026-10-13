import Foundation

public enum CategoryPalette {
    /// 新增一级分类时按顺序轮换使用的颜色。
    public static let colors = [
        "#FF9F0A", "#0A84FF", "#30B0C7", "#BF5AF2",
        "#FF375F", "#34C759", "#5E5CE6", "#A2845E",
    ]

    /// 超出范围时循环使用(负数也安全)。
    public static func color(at index: Int) -> String {
        colors[((index % colors.count) + colors.count) % colors.count]
    }
}
