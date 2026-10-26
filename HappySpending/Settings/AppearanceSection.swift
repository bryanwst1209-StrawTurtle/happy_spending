import SwiftUI
import PhotosUI
import HappySpendingCore

/// 设置页的"外观":选背景图、调浓淡、移除。
struct AppearanceSection: View {
    @Environment(AppearanceModel.self) private var appearance

    @State private var pick: PhotosPickerItem?
    @State private var isProcessing = false
    @State private var errorMessage: String?

    var body: some View {
        @Bindable var appearance = appearance
        Section {
            PhotosPicker(selection: $pick, matching: .images) {
                HStack {
                    Label(appearance.image == nil ? "选择背景图" : "更换背景图", systemImage: "photo")
                    Spacer()
                    if isProcessing {
                        ProgressView()
                    } else if let image = appearance.image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 36, height: 54)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            .appRowBackground()
            if appearance.image != nil {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("浓淡")
                        Spacer()
                        Text("\(Int((appearance.opacity * 100).rounded()))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $appearance.opacity, in: 0.1...1, step: 0.05)
                }
                .appRowBackground()
                Button("移除背景图", role: .destructive) {
                    do {
                        try appearance.removeImage()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                .appRowBackground()
            }
        } header: {
            Text("外观")
        } footer: {
            Text("四个页面共用这张背景图。浓淡越低,图片越淡,文字越清楚。")
        }
        .onChange(of: pick) { _, item in
            guard let item else { return }
            Task { await load(item) }
        }
        .alert("无法使用这张图片", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func load(_ item: PhotosPickerItem) async {
        isProcessing = true
        defer {
            isProcessing = false
            pick = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                errorMessage = BackgroundImageError.unreadable.message
                return
            }
            // 原图可能有几十 MB,缩放放到后台做,不卡界面。
            let processed = try await Task.detached { try BackgroundImage.process(data) }.value
            try appearance.setImage(processed)
        } catch let error as BackgroundImageError {
            errorMessage = error.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
