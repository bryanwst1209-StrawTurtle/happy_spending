import SwiftUI
import HappySpendingCore

struct NumericKeypad: View {
    let saveTitle: String
    let canSave: Bool
    let onKey: (KeypadKey) -> Void
    let onSave: () -> Void

    private let rows: [[KeypadKey]] = [
        [.digit(7), .digit(8), .digit(9)],
        [.digit(4), .digit(5), .digit(6)],
        [.digit(1), .digit(2), .digit(3)],
        [.dot, .digit(0), .backspace],
    ]

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                VStack(spacing: 8) {
                    ForEach(rows.indices, id: \.self) { r in
                        HStack(spacing: 8) {
                            ForEach(rows[r], id: \.self) { key in
                                Button { onKey(key) } label: {
                                    keyLabel(key)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                                .buttonStyle(.glass)
                            }
                        }
                    }
                }
                Button(action: onSave) {
                    Text(saveTitle)
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.glassProminent)
                .disabled(!canSave)
                .frame(width: 84)
            }
        }
        .frame(height: 4 * 54 + 3 * 8)
    }

    @ViewBuilder
    private func keyLabel(_ key: KeypadKey) -> some View {
        switch key {
        case .digit(let d): Text("\(d)").font(.title2.weight(.medium))
        case .dot: Text(".").font(.title2.weight(.medium))
        case .backspace: Image(systemName: "delete.left").font(.title3)
        }
    }
}
