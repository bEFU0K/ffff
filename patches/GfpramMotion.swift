import Foundation
import UIKit
import ObjectiveC

/// Плавность GFPGRAM: пружинное нажатие на кнопки и строки настроек, появление списков волной.
public enum GfpramMotion {
    private static var installed = false
    fileprivate static weak var pressedView: UIView?
    fileprivate static var startPoint = CGPoint.zero

    /// Включает пружинное нажатие во всём приложении (один раз, на главном потоке).
    public static func install() {
        if installed {
            return
        }
        installed = true
        guard let original = class_getInstanceMethod(UIWindow.self, #selector(UIWindow.sendEvent(_:))),
              let swizzled = class_getInstanceMethod(UIWindow.self, #selector(UIWindow.gfp_sendEvent(_:))) else {
            return
        }
        method_exchangeImplementations(original, swizzled)
        GfpramBackground.apply()
        GfpramSkin.install()
    }

    /// Строки списков волной: прозрачность + лёгкий пружинный подъём снизу.
    public static func staggerIn(_ views: [UIView]) {
        if UIAccessibility.isReduceMotionEnabled {
            return
        }
        for (index, view) in views.prefix(14).enumerated() {
            let begin = view.layer.convertTime(CACurrentMediaTime(), from: nil) + Double(index) * 0.04

            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.0
            fade.toValue = 1.0
            fade.duration = 0.32
            fade.beginTime = begin
            fade.fillMode = .backwards
            view.layer.add(fade, forKey: "gfpFade")

            let rise = CASpringAnimation(keyPath: "transform.translation.y")
            rise.fromValue = 22.0
            rise.toValue = 0.0
            rise.mass = 1.0
            rise.stiffness = 220.0
            rise.damping = 18.0
            rise.duration = rise.settlingDuration
            rise.beginTime = begin
            rise.fillMode = .backwards
            view.layer.add(rise, forKey: "gfpRise")
        }
    }

    // MARK: нажатия

    private static let pressableRows = ["DisclosureItemNode", "ActionItemNode", "CheckboxItemNode", "PeerItemNode", "TextWithLabelItemNode", "GfpramFeature"]

    static func nodeName(_ view: UIView) -> String? {
        let selector = Selector(("asyncdisplaykit_node"))
        guard view.responds(to: selector), let object = view.perform(selector)?.takeUnretainedValue() else {
            return nil
        }
        return String(describing: type(of: object))
    }

    private static func pressTarget(for hit: UIView) -> (UIView, CGFloat)? {
        var current: UIView? = hit
        var depth = 0
        while let view = current, depth < 8 {
            if view is UISwitch || view is UITextField || view is UITextView || view is UISlider || view is UIScrollView {
                return nil
            }
            if view is UIControl {
                return (view, 0.92)
            }
            if let name = nodeName(view), pressableRows.contains(where: { name.contains($0) }) {
                return (view, 0.97)
            }
            current = view.superview
            depth += 1
        }
        return nil
    }

    private static func spring(_ view: UIView, scale: CGFloat, down: Bool) {
        UIView.animate(withDuration: down ? 0.18 : 0.55, delay: 0.0, usingSpringWithDamping: down ? 0.9 : 0.5, initialSpringVelocity: down ? 0.0 : 8.0, options: [.allowUserInteraction, .beginFromCurrentState], animations: {
            view.transform = down ? CGAffineTransform(scaleX: scale, y: scale) : .identity
        }, completion: nil)
    }

    private static func release() {
        if let view = pressedView {
            spring(view, scale: 1.0, down: false)
        }
        pressedView = nil
    }

    fileprivate static func track(_ event: UIEvent, window: UIWindow) {
        if UIAccessibility.isReduceMotionEnabled {
            return
        }
        guard event.type == .touches, let touches = event.allTouches, touches.count == 1, let touch = touches.first else {
            release()
            return
        }
        switch touch.phase {
        case .began:
            release()
            let point = touch.location(in: window)
            if let hit = window.hitTest(point, with: event), let (view, scale) = pressTarget(for: hit) {
                pressedView = view
                startPoint = point
                spring(view, scale: scale, down: true)
            }
        case .moved:
            if pressedView != nil {
                let point = touch.location(in: window)
                if hypot(point.x - startPoint.x, point.y - startPoint.y) > 12.0 {
                    release()
                }
            }
        case .ended, .cancelled:
            release()
        default:
            break
        }
    }
}

extension UIWindow {
    @objc func gfp_sendEvent(_ event: UIEvent) {
        GfpramMotion.track(event, window: self)
        self.gfp_sendEvent(event)
    }
}
