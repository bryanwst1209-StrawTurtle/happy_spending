import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public enum BackgroundImageError: Error, Equatable {
    case tooLarge
    case unreadable

    public var message: String {
        switch self {
        case .tooLarge: "图片太大,请选择 30 MB 以内的图片"
        case .unreadable: "无法读取这张图片"
        }
    }
}

/// 把用户选的照片处理成 app 背景:转正方向,长边缩到不超过 2048 像素,存成 JPEG。
/// 原图可能有几十 MB,缩小后只有几百 KB,读取和显示都快。
public enum BackgroundImage {
    /// 处理后的长边上限(像素),足够铺满手机屏幕。
    public static let maxPixel = 2048
    /// 原图大小上限:30 MB。
    public static let maxSourceBytes = 30 * 1024 * 1024

    public static func process(_ source: Data) throws -> Data {
        guard source.count <= maxSourceBytes else { throw BackgroundImageError.tooLarge }

        guard
            let imageSource = CGImageSourceCreateWithData(source as CFData, nil),
            CGImageSourceGetCount(imageSource) > 0,
            let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int,
            width > 0, height > 0
        else { throw BackgroundImageError.unreadable }

        // 缩略图会按 EXIF 方向转正;长边不超过 maxPixel,小图保持原尺寸。
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(max(width, height), maxPixel),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary)
        else { throw BackgroundImageError.unreadable }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else { throw BackgroundImageError.unreadable }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw BackgroundImageError.unreadable }
        return output as Data
    }
}

/// 背景图存成 app 自己目录里的一个文件,不放进账本数据库(数据库只存账单)。
public struct BackgroundImageStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// 正式使用的位置:Application Support/Appearance。
    public static var standard: BackgroundImageStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return BackgroundImageStore(directory: base.appending(path: "Appearance"))
    }

    private var fileURL: URL { directory.appending(path: "background.jpg") }

    /// 保存处理好的图片,覆盖旧的。
    public func save(_ data: Data) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    /// 没有设置背景图时返回 nil。
    public func load() -> Data? {
        try? Data(contentsOf: fileURL)
    }

    /// 移除背景图;本来就没有时什么也不做。
    public func remove() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}
