import SwiftUI

/// 圆形分类图标:有自定义图片就显示图片,否则是带底色的 SF Symbol。
struct CategoryIconView: View {
    let symbolName: String
    let colorHex: String
    let iconData: Data?
    var size: CGFloat = 46

    var body: some View {
        let color = Color(hex: colorHex)
        ZStack {
            if let iconData, let image = UIImage(data: iconData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle().fill(color.opacity(0.18))
                Image(systemName: symbolName)
                    .font(.system(size: size * 0.42))
                    .foregroundStyle(color)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}
