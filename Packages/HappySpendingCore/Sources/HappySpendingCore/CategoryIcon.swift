import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public enum CategoryIconError: Error, Equatable {
    case tooLarge
    case unreadable

    public var message: String {
        switch self {
        case .tooLarge: "图片太大,请选择 10 MB 以内的图片"
        case .unreadable: "无法读取这张图片"
        }
    }
}

/// 把用户选的任意图片处理成分类图标:居中裁成正方形,缩放到 128×128,存成 PNG。
public enum CategoryIcon {
    /// 图标边长(像素)。
    public static let size = 128
    /// 原图大小上限:10 MB。
    public static let maxSourceBytes = 10 * 1024 * 1024

    public static func process(_ source: Data) throws -> Data {
        guard source.count <= maxSourceBytes else { throw CategoryIconError.tooLarge }

        guard
            let imageSource = CGImageSourceCreateWithData(source as CFData, nil),
            CGImageSourceGetCount(imageSource) > 0,
            let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int,
            width > 0, height > 0
        else { throw CategoryIconError.unreadable }

        // 先缩到"短边约等于 128"的大小,同时应用 EXIF 方向;再按短边铺满画布,居中裁成正方形。
        let ratio = Double(max(width, height)) / Double(min(width, height))
        let maxPixel = min(Int((Double(size) * ratio).rounded(.up)), 4096)
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let scaled = CGImageSourceCreateThumbnailAtIndex(
            imageSource, 0, thumbnailOptions as CFDictionary
        ) else { throw CategoryIconError.unreadable }

        guard let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw CategoryIconError.unreadable }
        context.interpolationQuality = .high

        let scaledWidth = Double(scaled.width)
        let scaledHeight = Double(scaled.height)
        let scale = max(Double(size) / scaledWidth, Double(size) / scaledHeight)
        let drawWidth = scaledWidth * scale
        let drawHeight = scaledHeight * scale
        context.draw(scaled, in: CGRect(
            x: (Double(size) - drawWidth) / 2,
            y: (Double(size) - drawHeight) / 2,
            width: drawWidth,
            height: drawHeight
        ))

        guard let square = context.makeImage() else { throw CategoryIconError.unreadable }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil
        ) else { throw CategoryIconError.unreadable }
        CGImageDestinationAddImage(destination, square, nil)
        guard CGImageDestinationFinalize(destination) else { throw CategoryIconError.unreadable }
        return output as Data
    }
}
