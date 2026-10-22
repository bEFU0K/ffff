import Foundation
import Postbox
import SwiftSignalKit

/// Облачная копия Premium-ключа и выбранной иконки в «Избранном» Telegram.
/// Локальные копии (UserDefaults, файл, связка ключей) пропадают, если при переустановке сменился Apple ID/bundle id.
/// Сообщение в «Избранном» живёт на сервере Telegram, поэтому после входа в аккаунт приложение находит его и возвращает
/// Premium и иконку само. Ключ привязан к id аккаунта и сроку, чужой аккаунт его не примет.
/// ШАБЛОН: apply_patches.py подставляет __LOCATION__ по реальному API Telegram-iOS; если API не подошёл — ставится AyuCloudStub.swift.
public enum AyuCloud {
    private static let marker = "GFPBK1"
    private static let sentKey = "ayu.cloudSent"
    private static let lock = NSLock()
    private static var currentAccount: Account?
    private static var attached = false
    private static var scheduled = false
    private static let queue = DispatchQueue(label: "gfpgram.cloud", qos: .utility)
    private static let restoreDisposable = MetaDisposable()

    /// Вызывается при открытии списка чатов (AyuPremiumService.start).
    public static func attach(account: Account) {
        lock.lock()
        currentAccount = account
        let first = !attached
        attached = true
        lock.unlock()
        if first {
            restore(account: account)
        }
    }

    /// Отложенная отправка копии (если Premium-ключ или иконка изменились).
    public static func scheduleBackup() {
        lock.lock()
        if scheduled {
            lock.unlock()
            return
        }
        scheduled = true
        lock.unlock()
        queue.asyncAfter(deadline: .now() + 6.0) {
            lock.lock()
            scheduled = false
            let account = currentAccount
            lock.unlock()
            if let account = account {
                sendIfChanged(account: account)
            }
        }
    }

    private static func payload() -> String? {
        let defaults = UserDefaults.standard
        var dict: [String: Any] = [:]
        if let key = defaults.string(forKey: "ayu.premiumKey"), AyuPremium.parse(key: key) != nil {
            dict["k"] = key
        }
        if let icon = defaults.string(forKey: "ayu.appIcon") {
            dict["i"] = icon
            dict["p"] = defaults.bool(forKey: "ayu.appIconPremium")
        }
        if dict.isEmpty {
            return nil
        }
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]) else {
            return nil
        }
        return data.base64EncodedString()
    }

    private static func sendIfChanged(account: Account) {
        guard let body = payload() else {
            return
        }
        if UserDefaults.standard.string(forKey: sentKey) == body {
            return
        }
        UserDefaults.standard.set(body, forKey: sentKey)
        AyuPersist.schedule()
        let text = "🔐 GFPGRAM: резервная копия Premium и иконки. Не удаляйте это сообщение — после обновления приложение вернёт всё само.\n\n" + marker + " " + body
        let _ = TelegramEngine(account: account).messages.enqueueOutgoingMessage(to: account.peerId, replyTo: nil, content: .text(text)).start()
    }

    private static func restore(account: Account) {
        let defaults = UserDefaults.standard
        let haveKey = defaults.string(forKey: "ayu.premiumKey") != nil && AyuPremium.isActive
        let haveIcon = defaults.string(forKey: "ayu.appIcon") != nil
        if haveKey && haveIcon {
            scheduleBackup()
            return
        }
        let ownId = account.peerId.id._internalGetInt64Value()
        let search = TelegramEngine(account: account).messages.searchMessages(location: __LOCATION__, query: marker, state: nil)
        restoreDisposable.set((search
        |> take(1)
        |> deliverOnMainQueue).start(next: { result in
            var bestDate: Int32 = -1
            var best: [String: Any]?
            for message in result.0.messages {
                let text = message.text
                guard let range = text.range(of: marker + " ") else {
                    continue
                }
                let tail = text[range.upperBound...]
                guard let token = tail.split(whereSeparator: { $0 == " " || $0 == "\n" }).first else {
                    continue
                }
                guard let data = Data(base64Encoded: String(token)), let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                    continue
                }
                if message.timestamp > bestDate {
                    bestDate = message.timestamp
                    best = object
                }
            }
            if let best = best {
                if let key = best["k"] as? String, !AyuPremium.isActive {
                    let _ = AyuPremium.activate(key: key, ownId: ownId)
                }
                if let icon = best["i"] as? String {
                    AyuIconKeeper.adopt(name: icon, premium: (best["p"] as? Bool) ?? false)
                }
                AyuIconKeeper.restore()
            }
            scheduleBackup()
        }))
    }
}
