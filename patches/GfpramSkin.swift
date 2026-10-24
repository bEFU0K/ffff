import Foundation
import UIKit
import ObjectiveC

/// Свой «скин» окон Telegram: градиент поверх фона экрана звонка. Включается переключателем в «Фон клиента».
public enum GfpramSkin {
    private static var installed = false
    private static let tag = 0x67667073
    private static let callsKey = "gfpgram.skin.calls"

    public static var callsEnabled: Bool {
        get { return UserDefaults.standard.object(forKey: callsKey) == nil ? true : UserDefaults.standard.bool(forKey: callsKey) }
        set { UserDefaults.standard.set(newValue, forKey: callsKey) }
    }

    public static func install() {
        if installed {
            return
        }
        installed = true
        guard let original = class_getInstanceMethod(UIViewController.self, #selector(UIViewController.viewDidAppear(_:))),
              let replacement = class_getInstanceMethod(UIViewController.self, #selector(UIViewController.gfp_viewDidAppear(_:))) else {
            return
        }
        method_exchangeImplementations(original, replacement)
    }

    fileprivate static func decorate(_ controller: UIViewController) {
        if !callsEnabled || !controller.isViewLoaded {
            return
        }
        let name = String(describing: type(of: controller))
        guard name.contains("CallController") || name.contains("VoiceChatController") else {
            return
        }
        let view = controller.view!
        if view.viewWithTag(tag) != nil {
            return
        }
        let overlay = GradientView(frame: view.bounds)
        overlay.tag = tag
        overlay.isUserInteractionEnabled = false
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.alpha = 0.0
        // индекс 1: над фоном экрана (он первый), под кнопками и текстом
        view.insertSubview(overlay, at: min(1, view.subviews.count))
        UIView.animate(withDuration: 0.6, animations: { overlay.alpha = 1.0 })
        if !UIAccessibility.isReduceMotionEnabled {
            let shift = CABasicAnimation(keyPath: "endPoint")
            shift.fromValue = NSValue(cgPoint: CGPoint(x: 1.0, y: 1.0))
            shift.toValue = NSValue(cgPoint: CGPoint(x: 0.3, y: 1.3))
            shift.duration = 6.0
            shift.autoreverses = true
            shift.repeatCount = .infinity
            shift.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            overlay.gradientLayer.add(shift, forKey: "gfpShift")
        }
    }

    private final class GradientView: UIView {
        override class var layerClass: AnyClass { return CAGradientLayer.self }
        var gradientLayer: CAGradientLayer { return self.layer as! CAGradientLayer }

        override init(frame: CGRect) {
            super.init(frame: frame)
            self.gradientLayer.colors = [
                UIColor(red: 0.48, green: 0.36, blue: 1.0, alpha: 0.42).cgColor,
                UIColor(red: 1.0, green: 0.37, blue: 0.64, alpha: 0.30).cgColor,
                UIColor(red: 1.0, green: 0.60, blue: 0.27, alpha: 0.22).cgColor
            ]
            self.gradientLayer.startPoint = CGPoint(x: 0.0, y: 0.0)
            self.gradientLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}

extension UIViewController {
    @objc func gfp_viewDidAppear(_ animated: Bool) {
        self.gfp_viewDidAppear(animated)
        GfpramSkin.decorate(self)
    }
}
