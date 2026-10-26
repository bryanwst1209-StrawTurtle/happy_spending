import SwiftUI
import HappySpendingCore

/// 外观设置:用哪种背景(默认 / 预设色盘 / 相册图片)和它的浓淡。四个页签共用,改了立刻生效。
@MainActor
@Observable
final class AppearanceModel {
    private static let choiceKey = "backgroundChoice"
    private static let opacityKey = "backgroundOpacity"

    private let store: BackgroundImageStore
    /// 存下来的相册图片;没有选过或已删除时为 nil。选了别的背景时图片仍然保留,可以切回来。
    private(set) var image: UIImage?

    var choice: BackgroundChoice {
        didSet { UserDefaults.standard.set(choice.stored, forKey: Self.choiceKey) }
    }

    /// 背景的浓淡,0.1~1;对颜色和图片都生效。
    var opacity: Double {
        didSet { UserDefaults.standard.set(opacity, forKey: Self.opacityKey) }
    }

    init(store: BackgroundImageStore = .standard) {
        self.store = store
        let image = store.load().flatMap(UIImage.init(data:))
        self.image = image
        let savedChoice = UserDefaults.standard.string(forKey: Self.choiceKey)
        // 有色盘之前只有图片:那时设过图片的,继续用图片。
        choice = savedChoice.map(BackgroundChoice.init(stored:)) ?? (image == nil ? .system : .image)
        opacity = UserDefaults.standard.object(forKey: Self.opacityKey) as? Double ?? 0.4
    }

    /// 实际显示的背景:选了图片但图片不在了,按默认处理。
    var effectiveChoice: BackgroundChoice {
        choice == .image && image == nil ? .system : choice
    }

    /// 是否换掉了系统默认背景(列表要隐藏自带底色、行要改成磨砂)。
    var isCustom: Bool { effectiveChoice != .system }

    /// 处理好的图片(见 `BackgroundImage.process`)存起来并换上。
    func setImage(_ processed: Data) throws {
        try store.save(processed)
        image = UIImage(data: processed)
        choice = .image
    }

    /// 删除存下来的图片;正在用它时退回默认。
    func deleteImage() throws {
        try store.remove()
        image = nil
        if choice == .image { choice = .system }
    }
}

/// 预设的填充:一个颜色是纯色,两个颜色是从左上到右下的渐变。
struct PresetFill: View {
    let preset: BackgroundPreset
    /// 整页背景时加两团很淡的光晕,让渐变更柔和;色块里不加。
    var glow = false

    var body: some View {
        let colors = preset.colors.map(Color.init(hex:))
        ZStack {
            if colors.count > 1 {
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            } else {
                colors.first ?? .clear
            }
            if glow {
                GeometryReader { proxy in
                    let size = proxy.size
                    Circle()
                        .fill(Color.white.opacity(0.35))
                        .frame(width: size.width * 0.7)
                        .blur(radius: 50)
                        .position(x: size.width * 0.2, y: size.height * 0.22)
                    Circle()
                        .fill((colors.last ?? .white).opacity(0.5))
                        .frame(width: size.width * 0.9)
                        .blur(radius: 70)
                        .position(x: size.width * 0.85, y: size.height * 0.72)
                }
            }
        }
    }
}

/// 页面背景:默认就是系统背景色;选了预设或图片时铺满并按浓淡显示,深色模式下再压暗一些,保证白字看得清。
struct AppBackground: View {
    @Environment(AppearanceModel.self) private var appearance
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Color(.systemBackground)
            .overlay {
                switch appearance.effectiveChoice {
                case .system:
                    EmptyView()
                case .preset(let id):
                    if let preset = BackgroundPreset.named(id) {
                        PresetFill(preset: preset, glow: true).opacity(appearance.opacity)
                    }
                case .image:
                    if let image = appearance.image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .opacity(appearance.opacity)
                    }
                }
                if appearance.isCustom && colorScheme == .dark {
                    Color.black.opacity(0.35)
                }
            }
            .clipped()
            .ignoresSafeArea()
    }
}

extension View {
    /// 列表页:换了背景时隐藏列表自带的底色,让背景透出来。
    func appListBackground() -> some View { modifier(AppListBackground()) }

    /// 列表里的一行:换了背景时改成半透明的磨砂底,文字依然清楚。
    func appRowBackground() -> some View { modifier(AppRowBackground()) }
}

private struct AppListBackground: ViewModifier {
    @Environment(AppearanceModel.self) private var appearance

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(appearance.isCustom ? .hidden : .automatic)
            .background { if appearance.isCustom { AppBackground() } }
    }
}

private struct AppRowBackground: ViewModifier {
    @Environment(AppearanceModel.self) private var appearance

    func body(content: Content) -> some View {
        if appearance.isCustom {
            content.listRowBackground(Rectangle().fill(.regularMaterial))
        } else {
            content
        }
    }
}
