import UIKit

/// Замена шрифта всего интерфейса. Семейство читается один раз за запуск (шрифты в узлах кэшируются),
/// поэтому смена шрифта применяется после перезапуска приложения.
public enum AyuFont {
    public static let key = "ayu.fontFamily"

    /// Только встроенные шрифты iOS с кириллицей: название в окне и имя семейства.
    public static let families: [(title: String, family: String)] = [
        ("Системный", ""),
        ("Helvetica Neue", "Helvetica Neue"),
        ("Arial", "Arial"),
        ("Verdana", "Verdana"),
        ("Trebuchet MS", "Trebuchet MS"),
        ("Georgia", "Georgia"),
        ("Palatino", "Palatino"),
        ("Times New Roman", "Times New Roman"),
        ("Menlo", "Menlo"),
        ("Courier New", "Courier New")
    ]

    public static let active: String = {
        let value = UserDefaults.standard.string(forKey: AyuFont.key) ?? ""
        return value
    }()

    private static let lock = NSLock()
    private static var cache: [String: UIFont] = [:]

    public static func weight(_ name: String) -> UIFont.Weight {
        switch name.lowercased() {
        case "ultralight": return .ultraLight
        case "thin": return .thin
        case "light": return .light
        case "medium": return .medium
        case "semibold": return .semibold
        case "bold": return .bold
        case "heavy": return .heavy
        case "black": return .black
        default: return .regular
        }
    }

    /// nil — выбран системный шрифт (или выбранного семейства нет на устройстве): тогда работает штатный код.
    public static func font(size: CGFloat, weight: UIFont.Weight, italic: Bool = false) -> UIFont? {
        let family = AyuFont.active
        if family.isEmpty {
            return nil
        }
        let cacheKey = "\(size)|\(weight.rawValue)|\(italic)"
        lock.lock()
        if let cached = cache[cacheKey] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        var descriptor = UIFontDescriptor(fontAttributes: [
            .family: family,
            .traits: [UIFontDescriptor.TraitKey.weight: weight]
        ])
        if italic, let withItalic = descriptor.withSymbolicTraits(.traitItalic) {
            descriptor = withItalic
        }
        let font = UIFont(descriptor: descriptor, size: size)
        if font.familyName != family {
            return nil
        }
        lock.lock()
        cache[cacheKey] = font
        lock.unlock()
        return font
    }
}
