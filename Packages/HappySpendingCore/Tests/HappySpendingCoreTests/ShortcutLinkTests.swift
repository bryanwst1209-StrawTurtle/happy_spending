import Testing
import Foundation
@testable import HappySpendingCore

struct ShortcutLinkTests {
    @Test func iCloudShortcutLinksAreAccepted() {
        let url = ShortcutLink.url(from: "https://www.icloud.com/shortcuts/0123456789abcdef0123456789abcdef")
        #expect(url?.absoluteString == "https://www.icloud.com/shortcuts/0123456789abcdef0123456789abcdef")
        #expect(ShortcutLink.url(from: "  https://www.icloud.com/shortcuts/abc123  ") != nil)
    }

    /// 只认 iCloud 快捷指令链接:写错的链接不显示按钮,不会跳到别的地方。
    @Test func otherLinksAreRejected() {
        for text in [
            nil, "", "   ",
            "http://www.icloud.com/shortcuts/abc123",
            "https://www.icloud.com/shortcuts/",
            "https://www.icloud.com/photos/abc123",
            "https://icloud.com.evil.example/shortcuts/abc123",
            "shortcuts://run-shortcut?name=x",
            "不是链接",
        ] {
            #expect(ShortcutLink.url(from: text) == nil, "\(text ?? "nil")")
        }
    }
}
