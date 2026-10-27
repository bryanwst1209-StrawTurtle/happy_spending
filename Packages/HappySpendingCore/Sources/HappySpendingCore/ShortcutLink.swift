import Foundation

/// "一键添加快捷指令"用的 iCloud 共享链接。
public enum ShortcutLink {
    /// 只接受 `https://www.icloud.com/shortcuts/<id>`;空的、写错的返回 nil(对应按钮不显示)。
    public static func url(from text: String?) -> URL? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
              let url = URL(string: text),
              url.scheme == "https",
              url.host() == "www.icloud.com"
        else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 2, parts[0] == "shortcuts", !parts[1].isEmpty else { return nil }
        return url
    }
}
