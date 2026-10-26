import Foundation

/// 外观里可选的预设背景:一个颜色是纯色,两个颜色是从左上到右下的渐变。
public struct BackgroundPreset: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    /// `#RRGGBB`,1 个或 2 个。
    public let colors: [String]

    public static let all: [BackgroundPreset] = [
        BackgroundPreset(id: "sakura", name: "樱花粉", colors: ["#FFC8D6"]),
        BackgroundPreset(id: "mint", name: "薄荷绿", colors: ["#B8E8D2"]),
        BackgroundPreset(id: "sky", name: "天空蓝", colors: ["#B4D2FF"]),
        BackgroundPreset(id: "lavender", name: "薰衣草", colors: ["#D8C4EC"]),
        BackgroundPreset(id: "cream", name: "奶油黄", colors: ["#FFE7B0"]),
        BackgroundPreset(id: "mist", name: "雾霾灰", colors: ["#D2D7DE"]),
        BackgroundPreset(id: "peach", name: "蜜桃", colors: ["#FF9A8B", "#FF6A88"]),
        BackgroundPreset(id: "dusk", name: "晚霞", colors: ["#FF9A8B", "#6A82FB"]),
        BackgroundPreset(id: "ocean", name: "海盐", colors: ["#89F7FE", "#66A6FF"]),
        BackgroundPreset(id: "lime", name: "青柠", colors: ["#D4FC79", "#96E6A1"]),
        BackgroundPreset(id: "grape", name: "葡萄", colors: ["#E0C3FC", "#8EC5FC"]),
        BackgroundPreset(id: "sunset", name: "落日", colors: ["#FAD0C4", "#FFD1FF"]),
    ]

    public static func named(_ id: String) -> BackgroundPreset? {
        all.first { $0.id == id }
    }
}

/// 当前用的是哪种背景。
public enum BackgroundChoice: Equatable, Hashable, Sendable {
    /// 系统默认背景色。
    case system
    /// 预设色盘里的一个(关联值是预设的 id)。
    case preset(String)
    /// 从相册选的图片。
    case image

    /// 存进设置里的文字:`system`、`image`、`preset:<id>`。
    public var stored: String {
        switch self {
        case .system: "system"
        case .image: "image"
        case .preset(let id): "preset:\(id)"
        }
    }

    /// 从设置里读出来;认不出的(比如以后删掉了某个预设)退回系统默认。
    public init(stored: String?) {
        switch stored {
        case "image":
            self = .image
        case let text? where text.hasPrefix("preset:"):
            let id = String(text.dropFirst("preset:".count))
            self = BackgroundPreset.named(id) == nil ? .system : .preset(id)
        default:
            self = .system
        }
    }
}
