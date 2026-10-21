import Foundation
import Postbox

/// Хранилище GFPGRAM: настройки, id удалённых сообщений, история правок, локальные значки «#».
private final class AyuStore: @unchecked Sendable {
    static let shared = AyuStore()

    private let lock = NSLock()
    private var deleted: Set<String>
    private var edits: [String: [String]]
    private var badgeNames: [String: String]

    init() {
        let defaults = UserDefaults.standard
        self.deleted = Set(defaults.stringArray(forKey: "ayu.deletedIds") ?? [])
        self.edits = (defaults.dictionary(forKey: "ayu.editHistory") as? [String: [String]]) ?? [:]
        self.badgeNames = (defaults.dictionary(forKey: "ayu.badges") as? [String: String]) ?? [:]
    }

    func markDeleted(_ key: String) {
        self.lock.lock()
        defer { self.lock.unlock() }
        if self.deleted.insert(key).inserted {
            UserDefaults.standard.set(Array(self.deleted), forKey: "ayu.deletedIds")
        }
    }

    func isDeleted(_ key: String) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.deleted.contains(key)
    }

    func clearDeleted() {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.deleted.removeAll()
        UserDefaults.standard.removeObject(forKey: "ayu.deletedIds")
    }

    func recordEdit(_ key: String, text: String) {
        self.lock.lock()
        defer { self.lock.unlock() }
        var list = self.edits[key] ?? []
        if list.last != text {
            list.append(text)
        }
        self.edits[key] = list
        UserDefaults.standard.set(self.edits, forKey: "ayu.editHistory")
    }

    func editHistory(_ key: String) -> [String] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.edits[key] ?? []
    }

    func hasBadge(_ id: String) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.badgeNames[id] != nil
    }

    func setBadge(_ id: String, name: String?) {
        self.lock.lock()
        defer { self.lock.unlock() }
        if let name = name {
            self.badgeNames[id] = name
        } else {
            self.badgeNames.removeValue(forKey: id)
        }
        UserDefaults.standard.set(self.badgeNames, forKey: "ayu.badges")
    }

    func allBadges() -> [(String, String)] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.badgeNames.map { ($0.key, $0.value) }.sorted(by: { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 < $1.1 })
    }
}

public enum AyuSettings {
    public struct Toggle {
        public let key: String
        public let title: String
        public init(key: String, title: String) {
            self.key = key
            self.title = title
        }
    }

    public struct Group {
        public let title: String
        public let footer: String
        public let toggles: [Toggle]
        public init(title: String, footer: String, toggles: [Toggle]) {
            self.title = title
            self.footer = footer
            self.toggles = toggles
        }
    }

    public static let version = "1.0"

    private static let ghostKeys = ["ghostRead", "ghostTyping", "ghostOnline", "ghostStories", "ghostScreenshot", "ghostConsume"]

    public static var groups: [Group] {
        return [
            Group(title: "РЕЖИМ ПРИЗРАКА", footer: "Главный переключатель включает или выключает всё сразу. Кнопка 👻 в списке чатов делает то же самое.", toggles: [
                Toggle(key: "ghostMode", title: "Режим призрака (всё сразу)"),
                Toggle(key: "ghostRead", title: "Не отмечать сообщения прочитанными"),
                Toggle(key: "ghostTyping", title: "Не показывать «печатает…» и запись"),
                Toggle(key: "ghostOnline", title: "Не показывать «в сети»"),
                Toggle(key: "ghostStories", title: "Не отмечать просмотр историй"),
                Toggle(key: "ghostScreenshot", title: "Не сообщать о скриншотах"),
                Toggle(key: "ghostConsume", title: "Не отмечать «прослушано / просмотрено»")
            ]),
            Group(title: "РЕЖИМ «ШПИОН» (АНТИ-УДАЛЕНИЕ)", footer: "Удалённые собеседником сообщения остаются на устройстве с маркером 🗑, изменённые — с маркером ✏️. Чат, где удалена вся переписка, отмечается 🗑 и серым цветом.", toggles: [
                Toggle(key: "keepDeleted", title: "Сохранять удалённые сообщения"),
                Toggle(key: "saveEdits", title: "Сохранять историю правок"),
                Toggle(key: "keepCleared", title: "Сохранять очищенные чаты"),
                Toggle(key: "keepSelfDestruct", title: "Сохранять самоудаляющиеся")
            ]),
            Group(title: "ОБХОД ОГРАНИЧЕНИЙ", footer: "Снимает запрет на пересылку, копирование и сохранение в закрытых чатах и каналах.", toggles: [
                Toggle(key: "allowCopy", title: "Обходить запрет пересылки и копирования")
            ]),
            Group(title: "ПРОЧЕЕ", footer: "", toggles: [
                Toggle(key: "hideAds", title: "Скрывать рекламу")
            ])
        ]
    }

    private static func flag(_ key: String) -> Bool {
        if UserDefaults.standard.object(forKey: key) == nil { return true }
        return UserDefaults.standard.bool(forKey: key)
    }

    /// Значение переключателя по короткому ключу (например "ghostRead").
    public static func value(_ key: String) -> Bool {
        if key == "ghostMode" {
            return self.ghostMaster
        }
        return flag("ayu." + key)
    }

    public static func set(_ key: String, _ value: Bool) {
        if key == "ghostMode" {
            self.setGhostMaster(value)
            return
        }
        UserDefaults.standard.set(value, forKey: "ayu." + key)
    }

    public static var ghostMaster: Bool {
        for key in self.ghostKeys {
            if !flag("ayu." + key) {
                return false
            }
        }
        return true
    }

    public static func setGhostMaster(_ value: Bool) {
        for key in self.ghostKeys {
            UserDefaults.standard.set(value, forKey: "ayu." + key)
        }
    }

    public static var ghostRead: Bool { return flag("ayu.ghostRead") }
    public static var ghostTyping: Bool { return flag("ayu.ghostTyping") }
    public static var ghostOnline: Bool { return flag("ayu.ghostOnline") }
    public static var ghostStories: Bool { return flag("ayu.ghostStories") }
    public static var keepDeleted: Bool { return flag("ayu.keepDeleted") }
    public static var saveEdits: Bool { return flag("ayu.saveEdits") }
    public static var hideAds: Bool { return flag("ayu.hideAds") }
    public static var allowCopy: Bool { return flag("ayu.allowCopy") }
    public static var ghostScreenshot: Bool { return flag("ayu.ghostScreenshot") }
    public static var ghostConsume: Bool { return flag("ayu.ghostConsume") }
    public static var keepCleared: Bool { return flag("ayu.keepCleared") }
    public static var keepSelfDestruct: Bool { return flag("ayu.keepSelfDestruct") }

    // MARK: - Скрытый вход в админ-панель

    public static var adminUnlocked: Bool {
        return UserDefaults.standard.bool(forKey: "ayu.adminUnlocked")
    }

    public static func verifyAdminCode(_ code: String) -> Bool {
        if code.trimmingCharacters(in: .whitespacesAndNewlines) == "888090%" {
            UserDefaults.standard.set(true, forKey: "ayu.adminUnlocked")
            return true
        }
        return false
    }
}

public enum AyuEditHistory {
    public static func key(_ id: MessageId) -> String {
        return "\(id.peerId.toInt64())_\(id.namespace)_\(id.id)"
    }

    public static func record(id: MessageId, text: String) {
        if !AyuSettings.saveEdits || text.isEmpty { return }
        AyuStore.shared.recordEdit(key(id), text: text)
    }

    public static func history(id: MessageId) -> [String] {
        return AyuStore.shared.editHistory(key(id))
    }
}

/// Сообщения, удалённые собеседником, но сохранённые у нас.
public enum AyuDeleted {
    public static func mark(_ id: MessageId) {
        AyuStore.shared.markDeleted(AyuEditHistory.key(id))
    }

    public static func contains(_ id: MessageId) -> Bool {
        return AyuStore.shared.isDeleted(AyuEditHistory.key(id))
    }

    public static func clearAll() {
        AyuStore.shared.clearDeleted()
    }
}

/// Локальный значок «#» (виден только на этом устройстве).
public enum AyuBadges {
    public static func contains(_ id: Int64) -> Bool {
        return AyuStore.shared.hasBadge(String(id))
    }

    public static func add(id: Int64, name: String) {
        AyuStore.shared.setBadge(String(id), name: name)
    }

    public static func remove(id: Int64) {
        AyuStore.shared.setBadge(String(id), name: nil)
    }

    public static func entries() -> [(id: Int64, name: String)] {
        var result: [(id: Int64, name: String)] = []
        for (key, name) in AyuStore.shared.allBadges() {
            if let id = Int64(key) {
                result.append((id: id, name: name))
            }
        }
        return result
    }

    public static func decorate(id: Int64, title: String) -> String {
        if AyuStore.shared.hasBadge(String(id)) {
            return title + " #"
        }
        return title
    }
}
