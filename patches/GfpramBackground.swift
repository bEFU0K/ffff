import Foundation
import UIKit
import ObjectiveC
import ImageIO

/// Свой фон клиента: фото или GIF под всеми экранами. Экраны делаются прозрачными, чтобы фон был виден.
public enum GfpramBackground {
    private static let enabledKey = "gfpgram.bg.enabled"
    private static let gifKey = "gfpgram.bg.gif"
    private static let blurKey = "gfpgram.bg.blur"
    private static let dimKey = "gfpgram.bg.dim"
    private static let transparentKey = "gfpgram.bg.transparent"
    private static let hostTag = 0x67667067
    private static var swizzled = false
    fileprivate static var active = false
    fileprivate static var assocKey: UInt8 = 0

    public static let blurLevels: [Double] = [0.0, 0.35, 0.7, 1.0]
    public static let blurTitles = ["Нет", "Слабое", "Среднее", "Сильное"]
    public static let dimLevels: [Double] = [0.0, 0.2, 0.4, 0.6]
    public static let dimTitles = ["Нет", "20%", "40%", "60%"]

    public static var isEnabled: Bool { return UserDefaults.standard.bool(forKey: enabledKey) && FileManager.default.fileExists(atPath: fileURL.path) }
    public static var isGif: Bool { return UserDefaults.standard.bool(forKey: gifKey) }
    public static var blurIndex: Int { return min(UserDefaults.standard.integer(forKey: blurKey), blurLevels.count - 1) }
    public static var dimIndex: Int { return min(UserDefaults.standard.integer(forKey: dimKey), dimLevels.count - 1) }
    public static var transparentScreens: Bool {
        get { return UserDefaults.standard.object(forKey: transparentKey) == nil ? true : UserDefaults.standard.bool(forKey: transparentKey) }
        set { UserDefaults.standard.set(newValue, forKey: transparentKey); apply() }
    }
    public static var kindTitle: String { return isEnabled ? (isGif ? "GIF" : "Фото") : "Не выбран" }
    public static var blurTitle: String { return blurTitles[blurIndex] }
    public static var dimTitle: String { return dimTitles[dimIndex] }

    public static func nextBlur() { UserDefaults.standard.set((blurIndex + 1) % blurLevels.count, forKey: blurKey); apply() }
    public static func nextDim() { UserDefaults.standard.set((dimIndex + 1) % dimLevels.count, forKey: dimKey); apply() }

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("gfpgram_bg.bin")
    }

    private static var window: UIWindow? {
        // Через селектор: UIApplication.shared недоступен в модулях, которые собираются и для расширений
        let applicationClass: AnyObject = UIApplication.self
        let application = applicationClass.perform(NSSelectorFromString("sharedApplication"))?.takeUnretainedValue() as? UIApplication
        return application?.delegate?.window ?? nil
    }

    /// Сохраняет выбранное фото или GIF и включает фон.
    @discardableResult
    public static func setImageData(_ data: Data) -> Bool {
        guard UIImage(data: data) != nil else {
            return false
        }
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            return false
        }
        let gif = data.count > 3 && data[0] == 0x47 && data[1] == 0x49 && data[2] == 0x46
        UserDefaults.standard.set(gif, forKey: gifKey)
        UserDefaults.standard.set(true, forKey: enabledKey)
        apply()
        return true
    }

    public static func clear() {
        UserDefaults.standard.set(false, forKey: enabledKey)
        try? FileManager.default.removeItem(at: fileURL)
        apply()
    }

    /// Пересобирает фон и прозрачность экранов по текущим настройкам.
    public static func apply() {
        applyNow(retries: 8)
    }

    private static func applyNow(retries: Int) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { applyNow(retries: retries) }
            return
        }
        installSwizzle()
        guard let window = window else {
            // окно ещё не создано при запуске: пробуем ещё несколько раз
            if retries > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: { applyNow(retries: retries - 1) })
            }
            return
        }
        window.viewWithTag(hostTag)?.removeFromSuperview()
        let on = isEnabled
        active = on && transparentScreens
        if !on {
            restore(in: window)
            return
        }
        guard let data = try? Data(contentsOf: fileURL) else {
            return
        }
        let host = UIView(frame: window.bounds)
        host.tag = hostTag
        host.isUserInteractionEnabled = false
        host.backgroundColor = .black
        host.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        let imageView = UIImageView(frame: host.bounds)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        if isGif, let gif = decodeGif(data) {
            imageView.animationImages = gif.frames
            imageView.animationDuration = gif.duration
            imageView.image = gif.frames.first
            if !UIAccessibility.isReduceMotionEnabled {
                imageView.startAnimating()
            }
        } else {
            imageView.image = UIImage(data: data)
        }
        host.addSubview(imageView)
        if blurLevels[blurIndex] > 0.0 {
            let blur = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
            blur.frame = host.bounds
            blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            blur.alpha = CGFloat(blurLevels[blurIndex])
            host.addSubview(blur)
        }
        if dimLevels[dimIndex] > 0.0 {
            let dim = UIView(frame: host.bounds)
            dim.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            dim.backgroundColor = UIColor.black.withAlphaComponent(CGFloat(dimLevels[dimIndex]))
            host.addSubview(dim)
        }
        window.insertSubview(host, at: 0)
        if active {
            clearBlack(in: window)
        } else {
            restore(in: window)
        }
    }

    private static func decodeGif(_ data: Data) -> (frames: [UIImage], duration: Double)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        let count = CGImageSourceGetCount(source)
        if count < 2 {
            return nil
        }
        let step = max(1, count / 60)
        var frames: [UIImage] = []
        var total = 0.0
        var index = 0
        while index < count {
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 720]
            if let image = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) {
                frames.append(UIImage(cgImage: image))
            }
            var delay = 0.1
            if let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any], let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
                if let value = gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double, value > 0.011 {
                    delay = value
                } else if let value = gif[kCGImagePropertyGIFDelayTime] as? Double, value > 0.011 {
                    delay = value
                }
            }
            total += delay * Double(step)
            index += step
        }
        if frames.count < 2 {
            return nil
        }
        return (frames, max(0.5, total))
    }

    // MARK: прозрачные экраны

    private final class ColorBox {
        let color: CGColor
        init(_ color: CGColor) { self.color = color }
    }

    private static let allowedNodes = ["ControllerNode", "ItemListNode", "ChatListNode", "ContactListNode", "PeerInfoScreenNode", "ListView", "NavigationContainer", "NavigationControllerNode"]
    private static let deniedNodes = ["Gallery", "Media", "Camera", "Call", "Video", "Story", "Passcode", "Lock", "Player", "Photo", "Wallpaper", "ThemePreview", "ChatController", "ChatMessage", "Browser"]

    private static func isBackgroundColor(_ color: CGColor) -> Bool {
        if color.alpha < 0.99 {
            return false
        }
        let c = color.components ?? []
        if c.count >= 3 {
            let black = c[0] < 0.03 && c[1] < 0.03 && c[2] < 0.03
            let lightGrey = abs(c[0] - 0.949) < 0.012 && abs(c[1] - 0.949) < 0.012 && abs(c[2] - 0.969) < 0.012
            return black || lightGrey
        } else if c.count == 2 {
            return c[0] < 0.03
        }
        return false
    }

    fileprivate static func shouldClear(_ layer: CALayer, _ color: CGColor) -> Bool {
        if !active || !isBackgroundColor(color) {
            return false
        }
        guard let view = layer.delegate as? UIView, view.tag != hostTag, let name = GfpramMotion.nodeName(view) else {
            return false
        }
        if deniedNodes.contains(where: { name.contains($0) }) {
            return false
        }
        return allowedNodes.contains(where: { name.contains($0) })
    }

    fileprivate static func remember(_ layer: CALayer, _ color: CGColor) {
        objc_setAssociatedObject(layer, &assocKey, ColorBox(color), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    private static func walk(_ view: UIView, _ body: (UIView) -> Void) {
        body(view)
        for sub in view.subviews {
            walk(sub, body)
        }
    }

    private static func clearBlack(in window: UIWindow) {
        walk(window) { view in
            if let color = view.layer.backgroundColor, shouldClear(view.layer, color) {
                view.layer.backgroundColor = color
            }
        }
    }

    private static func restore(in window: UIWindow) {
        walk(window) { view in
            if let box = objc_getAssociatedObject(view.layer, &assocKey) as? ColorBox {
                objc_setAssociatedObject(view.layer, &assocKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                view.layer.backgroundColor = box.color
            }
        }
    }

    private static func installSwizzle() {
        if swizzled {
            return
        }
        swizzled = true
        guard let original = class_getInstanceMethod(CALayer.self, #selector(setter: CALayer.backgroundColor)),
              let replacement = class_getInstanceMethod(CALayer.self, #selector(CALayer.gfp_setBackgroundColor(_:))) else {
            return
        }
        method_exchangeImplementations(original, replacement)
    }

    // MARK: выбор фото

    public static func pickImage(completion: @escaping (Bool) -> Void) {
        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        guard let root = top else {
            completion(false)
            return
        }
        let handler = Picker(completion: completion)
        Picker.current = handler
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.mediaTypes = ["public.image"]
        picker.delegate = handler
        root.present(picker, animated: true, completion: nil)
    }

    fileprivate final class Picker: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        static var current: Picker?
        let completion: (Bool) -> Void

        init(completion: @escaping (Bool) -> Void) {
            self.completion = completion
            super.init()
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            var data: Data?
            if let url = info[.imageURL] as? URL {
                data = try? Data(contentsOf: url)
            }
            if data == nil, let image = info[.originalImage] as? UIImage {
                data = image.jpegData(compressionQuality: 0.92)
            }
            let completion = self.completion
            picker.dismiss(animated: true, completion: {
                let ok = data.map { GfpramBackground.setImageData($0) } ?? false
                completion(ok)
                Picker.current = nil
            })
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            let completion = self.completion
            picker.dismiss(animated: true, completion: {
                completion(false)
                Picker.current = nil
            })
        }
    }
}

extension CALayer {
    @objc func gfp_setBackgroundColor(_ color: CGColor?) {
        if let color = color, GfpramBackground.shouldClear(self, color) {
            GfpramBackground.remember(self, color)
            self.gfp_setBackgroundColor(nil)
        } else {
            self.gfp_setBackgroundColor(color)
        }
    }
}
