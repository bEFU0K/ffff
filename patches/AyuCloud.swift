import Foundation
import Postbox
import SwiftSignalKit

/// Облачная копия данных GFPGRAM в «Избранном» Telegram: Premium-ключ, выбранная иконка, админ-доступ, значки «#»
/// и список ваших аккаунтов. Локальные копии (UserDefaults, файл, связка ключей) пропадают, если при переустановке
/// сменился Apple ID/bundle id. Сообщение в «Избранном» живёт на сервере Telegram, поэтому после входа в любой
/// ваш аккаунт приложение находит копии и возвращает всё само.
/// Копия пишется в «Избранное» КАЖДОГО вашего аккаунта и читается на каждом: данные находятся, в какой бы аккаунт
/// вы ни вошли первым. Все найденные копии склеиваются (ничего не теряется, даже если одна копия неполная).
/// ШАБЛОН: apply_patches.py подставляет __LOCATION__ по реальному API Telegram-iOS; если API не подошёл — ставится AyuCloudStub.swift.
public enum AyuCloud {
    private static let marker = "GFPBK1"
    private static let settingsMarker = "GFPBK2"
    private static var pending: [Int64: Int] = [:]
    private static let lock = NSLock()
    private static var accounts: [Int64: Account] = [:]
    private static var restored = Set<Int64>()
    private static var attempted = Set<Int64>()
    private static var scheduled = false
    private static let queue = DispatchQueue(label: "gfpgram.cloud", qos: .utility)
    private static let restoreDisposables = DisposableSet()

    /// Вызывается при открытии списка чатов аккаунта (AyuPremiumService.start).
    public static func attach(account: Account) {
        let id = account.peerId.toInt64()
        lock.lock()
        accounts[id] = account
        let first = attempted.insert(id).inserted
        lock.unlock()
        if first {
            restore(account: account)
            // Если поиск не ответил — всё равно начинаем делать копии, чтобы не остаться без них
            queue.asyncAfter(deadline: .now() + 30.0) {
                lock.lock()
                let inserted = restored.insert(id).inserted
                lock.unlock()
                if inserted {
                    scheduleBackup()
                }
            }
        }
    }

    /// Отложенная отправка копии (если данные изменились).
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
            let ready = accounts.filter { restored.contains($0.key) }.map { $0.value }
            lock.unlock()
            for account in ready {
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
        if AyuSettings.adminUnlocked {
            dict["a"] = 1
        }
        var badges: [String: String] = [:]
        for entry in AyuBadges.entries() {
            badges[String(entry.id)] = String(entry.name.prefix(40))
        }
        if !badges.isEmpty {
            dict["b"] = badges
        }
        let own = AyuOwnAccounts.ids()
        if !own.isEmpty {
            dict["o"] = own
        }
        if dict.isEmpty {
            return nil
        }
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]) else {
            return nil
        }
        var text = data.base64EncodedString()
        if text.count > 3400 {
            // Не влезает в одно сообщение (лимит 4096): оставляем без названий значков
            var small = dict
            var ids: [String: String] = [:]
            for key in badges.keys.prefix(40) {
                ids[key] = ""
            }
            small["b"] = ids
            if let data2 = try? JSONSerialization.data(withJSONObject: small, options: [.sortedKeys]) {
                text = data2.base64EncodedString()
            }
        }
        return text
    }

    /// Настройки функций Premium (переключатели, тексты, слово-триггер, реакция). Хранятся обычным JSON, без base64:
    /// лимит сообщения считается в символах, поэтому русский текст влезает.
    private static func isSettingKey(_ key: String) -> Bool {
        if key == "ayu.premiumKey" { return false }
        return key.hasPrefix("ayu.premium") || key.hasPrefix("ayu.ar") || key.hasPrefix("ayu.keyword") || key == "ayu.stubText" || key == "ayu.dmReplyText" || key == "ayu.reactEmoji"
    }

    private static func settingsPayload() -> String? {
        var dict: [String: Any] = [:]
        for (key, value) in UserDefaults.standard.dictionaryRepresentation() where isSettingKey(key) {
            if value is String || value is Bool || value is Int || value is Double {
                dict[key] = value
            }
        }
        if dict.isEmpty {
            return nil
        }
        func encode(_ d: [String: Any]) -> String? {
            guard let data = try? JSONSerialization.data(withJSONObject: d, options: [.sortedKeys]) else {
                return nil
            }
            return String(data: data, encoding: .utf8)
        }
        var text = encode(dict)
        var limit = 600
        while let current = text, current.count > 3700, limit > 40 {
            limit /= 2
            for (key, value) in dict {
                if let string = value as? String, string.count > limit {
                    dict[key] = String(string.prefix(limit))
                }
            }
            text = encode(dict)
        }
        return text
    }

    private static func sendSettingsIfChanged(account: Account) {
        guard let body = settingsPayload() else {
            return
        }
        let sentKey = "ayu.cloudSentS." + String(account.peerId.id._internalGetInt64Value())
        if UserDefaults.standard.string(forKey: sentKey) == body {
            return
        }
        UserDefaults.standard.set(body, forKey: sentKey)
        AyuPersist.schedule()
        let text = "⚙️ GFPGRAM: резервная копия настроек Premium. Не удаляйте это сообщение.\n\n" + settingsMarker + " " + body
        let _ = TelegramEngine(account: account).messages.enqueueOutgoingMessage(to: account.peerId, replyTo: nil, content: .text(text)).start()
    }

    private static func finishRestore(id: Int64) {
        lock.lock()
        let left = (pending[id] ?? 1) - 1
        pending[id] = left
        if left <= 0 {
            restored.insert(id)
        }
        lock.unlock()
        if left <= 0 {
            scheduleBackup()
        }
    }

    private static func sendIfChanged(account: Account) {
        sendSettingsIfChanged(account: account)
        guard let body = payload() else {
            return
        }
        let sentKey = "ayu.cloudSent." + String(account.peerId.id._internalGetInt64Value())
        if UserDefaults.standard.string(forKey: sentKey) == body {
            return
        }
        UserDefaults.standard.set(body, forKey: sentKey)
        AyuPersist.schedule()
        let text = "🔐 GFPGRAM: резервная копия Premium, иконки и значков. Не удаляйте это сообщение — после обновления приложение вернёт всё само.\n\n" + marker + " " + body
        let _ = TelegramEngine(account: account).messages.enqueueOutgoingMessage(to: account.peerId, replyTo: nil, content: .text(text)).start()
    }

    private static func restore(account: Account) {
        let id = account.peerId.toInt64()
        lock.lock()
        pending[id] = 2
        lock.unlock()
        let settingsSearch = TelegramEngine(account: account).messages.searchMessages(location: __LOCATION__, query: settingsMarker, state: nil)
        restoreDisposables.add((settingsSearch
        |> take(1)
        |> deliverOnMainQueue).start(next: { result in
            var newest: (date: Int32, json: [String: Any])?
            for message in result.0.messages {
                guard let range = message.text.range(of: settingsMarker + " ") else {
                    continue
                }
                let tail = String(message.text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard let data = tail.data(using: .utf8), let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                    continue
                }
                if newest == nil || message.timestamp > newest!.date {
                    newest = (message.timestamp, object)
                }
            }
            if let object = newest?.json {
                let defaults = UserDefaults.standard
                for (key, value) in object where isSettingKey(key) && defaults.object(forKey: key) == nil {
                    defaults.set(value, forKey: key)
                }
                AyuPersist.schedule()
            }
            finishRestore(id: id)
        }))
        let search = TelegramEngine(account: account).messages.searchMessages(location: __LOCATION__, query: marker, state: nil)
        restoreDisposables.add((search
        |> take(1)
        |> deliverOnMainQueue).start(next: { result in
            var bestKey: String?
            var bestUntil: Int64 = 0
            var newestIcon: (date: Int32, name: String, premium: Bool)?
            var admin = false
            var badges: [String: String] = [:]
            var own: [String] = []
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
                if let key = object["k"] as? String, let parsed = AyuPremium.parse(key: key), parsed.until > bestUntil {
                    bestUntil = parsed.until
                    bestKey = key
                }
                if let icon = object["i"] as? String, newestIcon == nil || message.timestamp > newestIcon!.date {
                    newestIcon = (message.timestamp, icon, (object["p"] as? Bool) ?? false)
                }
                if let value = object["a"] as? Int, value == 1 {
                    admin = true
                }
                if let items = object["b"] as? [String: String] {
                    for (key, name) in items where badges[key] == nil || badges[key]!.isEmpty {
                        badges[key] = name.isEmpty ? "ID " + key : name
                    }
                }
                if let items = object["o"] as? [String] {
                    for item in items where !own.contains(item) {
                        own.append(item)
                    }
                }
            }
            AyuOwnAccounts.merge(own)
            AyuOwnAccounts.register(account.peerId.id._internalGetInt64Value())
            if let key = bestKey {
                AyuPremium.restoreKey(key)
            }
            if admin {
                AyuSettings.adoptAdmin()
            }
            if !badges.isEmpty {
                AyuBadges.merge(badges)
            }
            if let icon = newestIcon {
                AyuIconKeeper.adopt(name: icon.name, premium: icon.premium)
            }
            AyuIconKeeper.restore()
            finishRestore(id: id)
        }))
    }
}
