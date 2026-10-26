import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import HappySpendingCore

struct BackgroundImageTests {
    private func makeImageData(width: Int, height: Int, orientation: Int? = nil) -> Data {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 0.2, green: 0.6, blue: 0.4, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
        var properties: [CFString: Any] = [:]
        if let orientation { properties[kCGImagePropertyOrientation] = orientation }
        CGImageDestinationAddImage(destination, context.makeImage()!, properties as CFDictionary)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    private func size(of data: Data) -> (width: Int, height: Int) {
        let source = CGImageSourceCreateWithData(data as CFData, nil)!
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        return (image.width, image.height)
    }

    // MARK: 处理图片

    @Test func aLargePhotoIsScaledDownKeepingItsShape() throws {
        let output = try BackgroundImage.process(makeImageData(width: 4000, height: 3000))
        let result = size(of: output)
        #expect(result.width == 2048)
        #expect(result.height == 1536)
    }

    @Test func aSmallPhotoKeepsItsSize() throws {
        let output = try BackgroundImage.process(makeImageData(width: 800, height: 600))
        let result = size(of: output)
        #expect(result.width == 800)
        #expect(result.height == 600)
    }

    /// 手机竖着拍的照片像素是横的,靠 EXIF 方向转正;处理后要已经转正。
    @Test func thePhotoIsTurnedUpright() throws {
        let output = try BackgroundImage.process(makeImageData(width: 400, height: 200, orientation: 6))
        let result = size(of: output)
        #expect(result.width == 200)
        #expect(result.height == 400)
    }

    @Test func somethingThatIsNotAPhotoIsRejected() {
        #expect(throws: BackgroundImageError.unreadable) {
            try BackgroundImage.process(Data("不是图片".utf8))
        }
    }

    @Test func anOversizedFileIsRejected() {
        #expect(throws: BackgroundImageError.tooLarge) {
            try BackgroundImage.process(Data(count: BackgroundImage.maxSourceBytes + 1))
        }
    }

    @Test func errorsHaveReadableChineseMessages() {
        #expect(BackgroundImageError.tooLarge.message == "图片太大,请选择 30 MB 以内的图片")
        #expect(BackgroundImageError.unreadable.message == "无法读取这张图片")
    }

    // MARK: 存取

    private func makeStore() -> BackgroundImageStore {
        BackgroundImageStore(directory: FileManager.default.temporaryDirectory.appending(path: "bg-\(UUID())"))
    }

    @Test func aSavedImageCanBeLoadedBack() throws {
        let store = makeStore()
        let data = try BackgroundImage.process(makeImageData(width: 300, height: 200))

        try store.save(data)

        #expect(store.load() == data)
    }

    @Test func savingAgainReplacesTheOldImage() throws {
        let store = makeStore()
        try store.save(Data("旧".utf8))
        try store.save(Data("新".utf8))

        #expect(store.load() == Data("新".utf8))
    }

    @Test func removingLeavesNoImage() throws {
        let store = makeStore()
        #expect(store.load() == nil)
        try store.remove()

        try store.save(Data("图".utf8))
        try store.remove()

        #expect(store.load() == nil)
    }
}
