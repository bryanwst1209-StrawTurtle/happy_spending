import SwiftUI
import HappySpendingCore

/// 外观设置:自定义背景图和它的浓淡。四个页签共用,改了立刻生效。
@MainActor
@Observable
final class AppearanceModel {
    private static let opacityKey = "backgroundOpacity"

    private let store: BackgroundImageStore
    /// 背景图;nil 表示没有设置,用系统默认背景。
    private(set) var image: UIImage?

    /// 图片的浓淡,0.1~1。
    var opacity: Double {
        didSet { UserDefaults.standard.set(opacity, forKey: Self.opacityKey) }
    }

    init(store: BackgroundImageStore = .standard) {
        self.store = store
        image = store.load().flatMap(UIImage.init(data:))
        let saved = UserDefaults.standard.object(forKey: Self.opacityKey) as? Double
        opacity = saved ?? 0.4
    }

    /// 处理好的图片(见 `BackgroundImage.process`)存起来并立刻换上。
    func setImage(_ processed: Data) throws {
        try store.save(processed)
        image = UIImage(data: processed)
    }

    func removeImage() throws {
        try store.remove()
        image = nil
    }
}

/// 页面背景:没有设置背景图时就是系统背景色;有图时铺满,深色模式下再压暗一些,保证白字看得清。
struct AppBackground: View {
    @Environment(AppearanceModel.self) private var appearance
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Color(.systemBackground)
            .overlay {
                if let image = appearance.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .opacity(appearance.opacity)
                    if colorScheme == .dark {
                        Color.black.opacity(0.35)
                    }
                }
            }
            .clipped()
            .ignoresSafeArea()
    }
}

extension View {
    /// 列表页:有背景图时隐藏列表自带的底色,让背景图透出来。
    func appListBackground() -> some View { modifier(AppListBackground()) }

    /// 列表里的一行:有背景图时改成半透明的磨砂底,文字依然清楚。
    func appRowBackground() -> some View { modifier(AppRowBackground()) }
}

private struct AppListBackground: ViewModifier {
    @Environment(AppearanceModel.self) private var appearance

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(appearance.image == nil ? .automatic : .hidden)
            .background { if appearance.image != nil { AppBackground() } }
    }
}

private struct AppRowBackground: ViewModifier {
    @Environment(AppearanceModel.self) private var appearance

    func body(content: Content) -> some View {
        if appearance.image != nil {
            content.listRowBackground(Rectangle().fill(.regularMaterial))
        } else {
            content
        }
    }
}
