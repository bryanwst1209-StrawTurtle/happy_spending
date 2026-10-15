import Foundation

/// 平台自带分类 → 我们的一级分类名。只收确定的;对应关系以真机上看到的支付宝分类名为准,可以增补。
public enum PlatformCategoryMap {
    public static let alipay: [String: String] = [
        "日用百货": "日用",
        "餐饮美食": "餐饮",
        "交通出行": "交通",
        "服饰装扮": "服饰",
        "爱车养车": "汽车",
        "酒店旅游": "旅游",
        "医疗健康": "医疗",
        "住房物业": "居住",
        "数码电器": "购物",
    ]

    public static func ourCategoryName(forAlipay name: String) -> String? {
        alipay[name]
    }
}
