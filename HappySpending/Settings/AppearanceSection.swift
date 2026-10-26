import SwiftUI
import PhotosUI
import HappySpendingCore

/// 设置页的"外观":默认 / 预设色盘 / 相册图片,浓淡,删除图片。
struct AppearanceSection: View {
    @Environment(AppearanceModel.self) private var appearance

    @State private var pick: PhotosPickerItem?
    @State private var isProcessing = false
    @State private var errorMessage: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 5)

    var body: some View {
        @Bindable var appearance = appearance
        Section {
            LazyVGrid(columns: columns, spacing: 12) {
                swatch("默认", choice: .system) {
                    Color(.systemBackground)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.3)))
                }
                ForEach(BackgroundPreset.all) { preset in
                    swatch(preset.name, choice: .preset(preset.id)) { PresetFill(preset: preset) }
                }
                if let image = appearance.image {
                    swatch("我的图片", choice: .image) {
                        Image(uiImage: image).resizable().scaledToFill()
                    }
                }
                PhotosPicker(selection: $pick, matching: .images) {
                    tile(label: "从相册选") {
                        ZStack {
                            Color.secondary.opacity(0.12)
                            if isProcessing {
                                ProgressView()
                            } else {
                                Image(systemName: "photo.badge.plus").font(.title3)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 6)
            .appRowBackground()

            if appearance.effectiveChoice != .system {
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
            }
            if appearance.image != nil {
                Button("删除这张图片", role: .destructive) {
                    do {
                        try appearance.deleteImage()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                .appRowBackground()
            }
        } header: {
            Text("外观")
        } footer: {
            Text("四个页面共用这个背景。浓淡越低,背景越淡,文字越清楚。")
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

    /// 可点选的色块;当前选中的带勾。
    private func swatch(_ label: String, choice: BackgroundChoice, @ViewBuilder fill: () -> some View) -> some View {
        let selected = appearance.effectiveChoice == choice
        return Button {
            appearance.choice = choice
        } label: {
            tile(label: label) {
                fill()
                    .overlay(alignment: .bottomTrailing) {
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.callout)
                                .foregroundStyle(.white, Color.accentColor)
                                .padding(4)
                        }
                    }
            }
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.accentColor, lineWidth: selected ? 2.5 : 0)
                    .frame(height: 64)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func tile(label: String, @ViewBuilder fill: () -> some View) -> some View {
        VStack(spacing: 4) {
            fill()
                .frame(height: 64)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
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
