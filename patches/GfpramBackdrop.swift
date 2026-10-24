import Foundation
import UIKit

/// Градиентный фон экранов входа: мягкие цветные «пятна» на тёмной или светлой основе.
public enum GfpramBackdrop {
    private static var cache: [String: UIColor] = [:]

    public static func authColor(fallback: UIColor) -> UIColor {
        var red: CGFloat = 0.0
        var green: CGFloat = 0.0
        var blue: CGFloat = 0.0
        var alpha: CGFloat = 0.0
        guard fallback.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return fallback
        }
        let dark = 0.299 * red + 0.587 * green + 0.114 * blue < 0.5
        let size = UIScreen.main.bounds.size
        if size.width < 1.0 || size.height < 1.0 {
            return fallback
        }
        let key = "\(dark)-\(Int(size.width))x\(Int(size.height))"
        if let color = cache[key] {
            return color
        }
        let boost: CGFloat = dark ? 1.0 : 0.5
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            fallback.setFill()
            context.fill(CGRect(origin: CGPoint(), size: size))
            let space = CGColorSpaceCreateDeviceRGB()
            let orbs: [(CGPoint, CGFloat, UIColor)] = [
                (CGPoint(x: size.width * 0.10, y: size.height * 0.04), size.width * 0.95, UIColor(red: 0.48, green: 0.36, blue: 1.0, alpha: 0.50 * boost)),
                (CGPoint(x: size.width * 0.98, y: size.height * 0.48), size.width * 0.85, UIColor(red: 1.0, green: 0.37, blue: 0.64, alpha: 0.38 * boost)),
                (CGPoint(x: size.width * 0.30, y: size.height * 1.02), size.width * 0.90, UIColor(red: 1.0, green: 0.60, blue: 0.27, alpha: 0.30 * boost))
            ]
            for (center, radius, color) in orbs {
                let colors = [color.cgColor, color.withAlphaComponent(0.0).cgColor] as CFArray
                if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0.0, 1.0]) {
                    context.cgContext.drawRadialGradient(gradient, startCenter: center, startRadius: 0.0, endCenter: center, endRadius: radius, options: [])
                }
            }
        }
        let color = UIColor(patternImage: image)
        cache[key] = color
        return color
    }
}
