import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import HappySpendingCore

struct CategoryIconTests {
    // MARK: 测试用的图片工具

    private typealias RGBA = (r: UInt8, g: UInt8, b: UInt8, a: UInt8)

    private func makeImage(width: Int, height: Int, draw: (CGContext) -> Void) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        draw(context)
        return context.makeImage()!
    }

    private func fill(_ context: CGContext, _ color: (CGFloat, CGFloat, CGFloat), _ rect: CGRect) {
        context.setFillColor(red: color.0, green: color.1, blue: color.2, alpha: 1)
        context.fill(rect)
    }

    private func encode(_ image: CGImage, as type: UTType, orientation: Int? = nil) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil)!
        var properties: [CFString: Any] = [:]
        if let orientation { properties[kCGImagePropertyOrientation] = orientation }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    /// 解码成 RGBA 像素;第 0 行是图片最上面一行。
    private func decode(_ data: Data) -> (width: Int, height: Int, pixel: (Int, Int) -> RGBA) {
        let source = CGImageSourceCreateWithData(data as CFData, nil)!
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(
            data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (width, height, { x, y in
            let i = (y * width + x) * 4
            return (bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3])
        })
    }

    private let magenta: (CGFloat, CGFloat, CGFloat) = (1, 0, 1)
    private let green: (CGFloat, CGFloat, CGFloat) = (0, 1, 0)
    private let red: (CGFloat, CGFloat, CGFloat) = (1, 0, 0)
    private let blue: (CGFloat, CGFloat, CGFloat) = (0, 0, 1)

    private func isGreen(_ p: RGBA) -> Bool { p.g > 200 && p.r < 60 && p.b < 60 }
    private func isMagenta(_ p: RGBA) -> Bool { p.r > 200 && p.b > 200 && p.g < 60 }
    private func isRed(_ p: RGBA) -> Bool { p.r > 200 && p.g < 80 && p.b < 80 }
    private func isBlue(_ p: RGBA) -> Bool { p.b > 200 && p.r < 80 && p.g < 80 }

    // MARK: 输出格式和尺寸

    @Test func limitsAreTheDocumentedOnes() {
        #expect(CategoryIcon.size == 128)
        #expect(CategoryIcon.maxSourceBytes == 10 * 1024 * 1024)
    }

    @Test func outputIsAlwaysAPNGOfExactly128Pixels() throws {
        for (width, height) in [(400, 200), (200, 400), (128, 128), (40, 40), (1000, 30), (30, 1000)] {
            let image = makeImage(width: width, height: height) { fill($0, red, CGRect(x: 0, y: 0, width: width, height: height)) }
            let output = try CategoryIcon.process(encode(image, as: .png))

            #expect(Array(output.prefix(8)) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
            let decoded = decode(output)
            #expect(decoded.width == 128 && decoded.height == 128, "\(width)x\(height)")
        }
    }

    @Test func jpegSourcesWorkToo() throws {
        let image = makeImage(width: 300, height: 200) { fill($0, blue, CGRect(x: 0, y: 0, width: 300, height: 200)) }
        let decoded = decode(try CategoryIcon.process(encode(image, as: .jpeg)))
        #expect(decoded.width == 128 && decoded.height == 128)
        #expect(isBlue(decoded.pixel(64, 64)))
    }

    // MARK: 居中裁剪而不是拉伸

    @Test func landscapeImagesAreCenterCroppedNotStretched() throws {
        // 400x200:左右各 100 像素是洋红,中间 200 像素是绿色。居中裁出的 200x200 正好全是绿色。
        let image = makeImage(width: 400, height: 200) { context in
            fill(context, magenta, CGRect(x: 0, y: 0, width: 400, height: 200))
            fill(context, green, CGRect(x: 100, y: 0, width: 200, height: 200))
        }
        let decoded = decode(try CategoryIcon.process(encode(image, as: .png)))

        #expect(isGreen(decoded.pixel(4, 64)))
        #expect(isGreen(decoded.pixel(64, 64)))
        #expect(isGreen(decoded.pixel(123, 64)))
    }

    @Test func portraitImagesAreCenterCroppedNotStretched() throws {
        let image = makeImage(width: 200, height: 400) { context in
            fill(context, magenta, CGRect(x: 0, y: 0, width: 200, height: 400))
            fill(context, green, CGRect(x: 0, y: 100, width: 200, height: 200))
        }
        let decoded = decode(try CategoryIcon.process(encode(image, as: .png)))

        #expect(isGreen(decoded.pixel(64, 4)))
        #expect(isGreen(decoded.pixel(64, 64)))
        #expect(isGreen(decoded.pixel(64, 123)))
    }

    @Test func tinyImagesAreScaledUpWithoutDistortion() throws {
        let image = makeImage(width: 40, height: 40) { fill($0, green, CGRect(x: 0, y: 0, width: 40, height: 40)) }
        let decoded = decode(try CategoryIcon.process(encode(image, as: .png)))
        #expect(isGreen(decoded.pixel(2, 2)))
        #expect(isGreen(decoded.pixel(125, 125)))
    }

    // MARK: 透明与方向

    @Test func transparencyIsPreserved() throws {
        let transparent = makeImage(width: 64, height: 64) { _ in }
        let decodedClear = decode(try CategoryIcon.process(encode(transparent, as: .png)))
        #expect(decodedClear.pixel(64, 64).a == 0)

        let opaque = makeImage(width: 64, height: 64) { fill($0, red, CGRect(x: 0, y: 0, width: 64, height: 64)) }
        let decodedOpaque = decode(try CategoryIcon.process(encode(opaque, as: .png)))
        #expect(decodedOpaque.pixel(64, 64).a == 255)
    }

    @Test func exifOrientationIsApplied() throws {
        // 400x200,左半红、右半蓝,标记方向为 6(需要顺时针转 90° 才是正的):转正之后红色在上、蓝色在下。
        let image = makeImage(width: 400, height: 200) { context in
            fill(context, red, CGRect(x: 0, y: 0, width: 200, height: 200))
            fill(context, blue, CGRect(x: 200, y: 0, width: 200, height: 200))
        }
        let decoded = decode(try CategoryIcon.process(encode(image, as: .jpeg, orientation: 6)))

        #expect(isRed(decoded.pixel(64, 12)))
        #expect(isBlue(decoded.pixel(64, 116)))
    }

    // MARK: 大小限制与坏数据

    @Test func noisyPhotosStayUnderTheStorageCap() throws {
        var generator = SystemRandomNumberGenerator()
        let image = makeImage(width: 1024, height: 768) { context in
            for _ in 0..<4000 {
                let color = (CGFloat.random(in: 0...1, using: &generator),
                             CGFloat.random(in: 0...1, using: &generator),
                             CGFloat.random(in: 0...1, using: &generator))
                fill(context, color, CGRect(
                    x: Int.random(in: 0..<1024, using: &generator),
                    y: Int.random(in: 0..<768, using: &generator),
                    width: 24, height: 24
                ))
            }
        }
        let output = try CategoryIcon.process(encode(image, as: .png))
        #expect(output.count <= 100 * 1024)
    }

    @Test func sourcesOverTenMegabytesAreRejected() {
        let tooBig = Data(count: CategoryIcon.maxSourceBytes + 1)
        #expect(throws: CategoryIconError.tooLarge) { try CategoryIcon.process(tooBig) }
    }

    @Test func exactlyTenMegabytesIsNotRejectedForItsSize() {
        let limit = Data(count: CategoryIcon.maxSourceBytes)
        #expect(throws: CategoryIconError.unreadable) { try CategoryIcon.process(limit) }
    }

    @Test func garbageIsUnreadable() {
        #expect(throws: CategoryIconError.unreadable) { try CategoryIcon.process(Data("not an image".utf8)) }
        #expect(throws: CategoryIconError.unreadable) { try CategoryIcon.process(Data()) }
    }

    @Test func errorsHaveReadableMessages() {
        #expect(CategoryIconError.tooLarge.message == "图片太大,请选择 10 MB 以内的图片")
        #expect(CategoryIconError.unreadable.message == "无法读取这张图片")
    }
}
