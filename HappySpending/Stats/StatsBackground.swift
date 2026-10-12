import SwiftUI

/// 给玻璃层提供可折射的彩色内容。
struct StatsBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.indigo.opacity(0.35), Color.teal.opacity(0.25), Color.pink.opacity(0.20)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color.orange.opacity(0.35))
                .frame(width: 260, height: 260)
                .blur(radius: 60)
                .offset(x: -120, y: -220)
            Circle()
                .fill(Color.blue.opacity(0.35))
                .frame(width: 300, height: 300)
                .blur(radius: 70)
                .offset(x: 140, y: 120)
        }
        .background(Color(.systemBackground))
    }
}
