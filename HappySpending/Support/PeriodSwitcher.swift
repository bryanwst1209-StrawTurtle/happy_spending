import SwiftUI

struct PeriodSwitcher: View {
    let title: String
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack {
            Button(action: onPrevious) { Image(systemName: "chevron.left") }
                .buttonStyle(.glass)
            Spacer()
            Text(title).font(.headline)
            Spacer()
            Button(action: onNext) { Image(systemName: "chevron.right") }
                .buttonStyle(.glass)
        }
    }
}
