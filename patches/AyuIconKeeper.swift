import Foundation
import UIKit

/// Запоминает выбранную иконку приложения и возвращает её после обновления/переустановки.
/// iOS сам хранит имя альтернативной иконки, но при перепаковке приложения (Sideloadly) сбрасывает её на основную.
/// Выбор лежит в UserDefaults с префиксом «ayu.»: он автоматически попадает в файл и связку ключей (AyuPersist)
/// и в облачную копию в «Избранном» (AyuCloud).
public enum AyuIconKeeper {
    private static let nameKey = "ayu.appIcon"
    private static let premiumKey = "ayu.appIconPremium"
    private static let premiumNames: Set<String> = ["GfpGold", "GfpTurbo", "GfpNight", "GfpDuck"]
    private static var observer: NSObjectProtocol?

    public static var rememberedName: String? {
        return UserDefaults.standard.string(forKey: nameKey)
    }

    public static var rememberedPremium: Bool {
        return UserDefaults.standard.bool(forKey: premiumKey)
    }

    /// Вызывается после успешной смены иконки в окне «Иконка приложения». name == nil — основная.
    public static func remember(name: String?, premium: Bool) {
        let defaults = UserDefaults.standard
        defaults.set(name ?? "main", forKey: nameKey)
        defaults.set(premium, forKey: premiumKey)
        AyuPersist.schedule()
        AyuCloud.scheduleBackup()
    }

    /// Значение из облачной копии: берём, только если локально ничего не запомнено.
    static func adopt(name: String, premium: Bool) {
        let defaults = UserDefaults.standard
        if defaults.string(forKey: nameKey) == nil {
            defaults.set(name, forKey: nameKey)
            defaults.set(premium, forKey: premiumKey)
            AyuPersist.schedule()
        }
    }

    /// Возвращает сохранённую иконку, если iOS её сбросила.
    public static func restore() {
        DispatchQueue.main.async {
            seedIfNeeded()
            apply()
        }
    }

    /// Если иконка уже выбрана, но запоминания ещё не было (первое обновление на эту версию) — запоминаем текущую.
    private static func seedIfNeeded() {
        if rememberedName != nil {
            return
        }
        let app = UIApplication.shared
        if let current = app.alternateIconName, current != "BlueIcon" {
            let defaults = UserDefaults.standard
            defaults.set(current, forKey: nameKey)
            defaults.set(premiumNames.contains(current), forKey: premiumKey)
            AyuPersist.schedule()
        }
    }

    private static func apply() {
        guard let saved = rememberedName else {
            return
        }
        // Premium-иконка без активной подписки не возвращается
        if rememberedPremium && !AyuPremium.isActive {
            return
        }
        let target: String? = saved == "main" ? nil : saved
        let app = UIApplication.shared
        let current = app.alternateIconName
        if current == target || (target == nil && current == "BlueIcon") {
            return
        }
        guard app.supportsAlternateIcons else {
            return
        }
        // Менять иконку можно только когда приложение на экране
        if app.applicationState != .active {
            if observer == nil {
                observer = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main, using: { _ in
                    if let token = observer {
                        NotificationCenter.default.removeObserver(token)
                        observer = nil
                    }
                    apply()
                })
            }
            return
        }
        app.setAlternateIconName(target, completionHandler: { _ in })
    }
}
