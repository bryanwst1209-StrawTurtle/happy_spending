import Testing
import Foundation
@testable import HappySpendingCore

struct BackgroundChoiceTests {
    // MARK: 预设色盘

    @Test func thereAreSixSolidsAndSixGradients() {
        let presets = BackgroundPreset.all
        #expect(presets.filter { $0.colors.count == 1 }.count == 6)
        #expect(presets.filter { $0.colors.count == 2 }.count == 6)
    }

    @Test func presetIDsAndNamesAreUnique() {
        let presets = BackgroundPreset.all
        #expect(Set(presets.map(\.id)).count == presets.count)
        #expect(Set(presets.map(\.name)).count == presets.count)
    }

    @Test func everyColorIsASixDigitHex() {
        for preset in BackgroundPreset.all {
            for hex in preset.colors {
                #expect(hex.range(of: "^#[0-9A-F]{6}$", options: .regularExpression) != nil, "\(preset.id) \(hex)")
            }
        }
    }

    @Test func aPresetCanBeFoundByID() {
        #expect(BackgroundPreset.named("sakura")?.name == "樱花粉")
        #expect(BackgroundPreset.named("dusk")?.colors == ["#FF9A8B", "#6A82FB"])
        #expect(BackgroundPreset.named("nope") == nil)
    }

    // MARK: 存取"当前选了哪个"

    @Test func choicesRoundTripThroughTheirStoredText() {
        for choice in [BackgroundChoice.system, .image, .preset("sakura"), .preset("dusk")] {
            #expect(BackgroundChoice(stored: choice.stored) == choice, "\(choice)")
        }
    }

    @Test func theStoredTextIsReadable() {
        #expect(BackgroundChoice.system.stored == "system")
        #expect(BackgroundChoice.image.stored == "image")
        #expect(BackgroundChoice.preset("sakura").stored == "preset:sakura")
    }

    /// 以后删掉或改名了某个预设,旧的设置不能卡住,退回默认。
    @Test func unknownStoredTextFallsBackToSystem() {
        for text in ["preset:removed", "preset:", "whatever", ""] {
            #expect(BackgroundChoice(stored: text) == .system, "\(text)")
        }
        #expect(BackgroundChoice(stored: nil) == .system)
    }
}
