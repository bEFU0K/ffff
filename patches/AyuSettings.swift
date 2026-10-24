import Foundation
import Postbox

/// Запись истории правок: текст версии и время, когда её заменила следующая.
public struct AyuEditEntry: Codable {
    public var text: String
    public var date: Double

    public init(text: String, date: Double) {
        self.text = text
        self.date = date
    }
}

private struct AyuPersisted: Codable {
    var deleted: [String] = []
    var edits: [String: [AyuEditEntry]] = [:]
    var badges: [String: String] = [:]
}

/// Хранилище GFPGRAM: настройки, id удалённых сообщений, история правок, локальные значки «#».
/// Данные пишутся в три места сразу: UserDefaults, файл в Application Support и связку ключей iOS.
/// При запуске всё сливается обратно, поэтому история не теряется после обновления клиента
/// (а связка ключей переживает даже удаление приложения, если не менялся Apple ID при переподписи).
private final class AyuStore: @unchecked Sendable {
    static let shared = AyuStore()

    private let lock = NSLock()
    private var data = AyuPersisted()
    private var deletedSet = Set<String>()
    private var saveScheduled = false
    private let saveQueue = DispatchQueue(label: "gfpgram.store.save", qos: .utility)

    private static let defaultsKey = "ayu.store.v2"
    private static let keychainKey = "storeV2"

    private static var fileURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = base.appendingPathComponent("gfp-data", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        return dir.appendingPathComponent("store.json")
    }

    private static func merge(_ target: inout AyuPersisted, with other: AyuPersisted) {
        let known = Set(target.deleted)
        for id in other.deleted where !known.contains(id) {
            target.deleted.append(id)
        }
        for (key, name) in other.badges where target.badges[key] == nil {
            target.badges[key] = name
        }
        for (key, list) in other.edits {
            if let current = target.edits[key] {
                if list.count > current.count {
                    target.edits[key] = list
                }
            } else {
                target.edits[key] = list
            }
        }
    }

    init() {
        _ = AyuPersist.ready
        var merged = AyuPersisted()
        let defaults = UserDefaults.standard

        if let blob = defaults.data(forKey: AyuStore.defaultsKey), let value = try? JSONDecoder().decode(AyuPersisted.self, from: blob) {
            AyuStore.merge(&merged, with: value)
        }
        // Файл в Application Support
        if let url = AyuStore.fileURL, let blob = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(AyuPersisted.self, from: blob) {
            AyuStore.merge(&merged, with: value)
        }
        // Связка ключей (переживает удаление приложения)
        if let blob = AyuKeychain.get(AyuStore.keychainKey), let value = try? JSONDecoder().decode(AyuPersisted.self, from: blob) {
            AyuStore.merge(&merged, with: value)
        }
        // Старый формат (до 1.3): отдельные ключи UserDefaults
        var legacy = AyuPersisted()
        legacy.deleted = defaults.stringArray(forKey: "ayu.deletedIds") ?? []
        legacy.badges = (defaults.dictionary(forKey: "ayu.badges") as? [String: String]) ?? [:]
        if let old = defaults.dictionary(forKey: "ayu.editHistory") as? [String: [String]] {
            for (key, texts) in old {
                legacy.edits[key] = texts.map { AyuEditEntry(text: $0, date: 0) }
            }
        }
        AyuStore.merge(&merged, with: legacy)

        // Чистим историю: подряд идущие одинаковые версии (мусор от старых сборок) схлопываем
        for (key, list) in merged.edits {
            var clean: [AyuEditEntry] = []
            for entry in list where clean.last?.text != entry.text {
                clean.append(entry)
            }
            if clean.isEmpty {
                merged.edits.removeValue(forKey: key)
            } else {
                merged.edits[key] = clean
            }
        }
        self.data = merged
        self.deletedSet = Set(merged.deleted)
        self.scheduleSave()
    }

    // MARK: Сохранение

    private func scheduleSave() {
        self.lock.lock()
        if self.saveScheduled {
            self.lock.unlock()
            return
        }
        self.saveScheduled = true
        self.lock.unlock()
        self.saveQueue.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.writeAll()
        }
    }

    private func writeAll() {
        self.lock.lock()
        self.saveScheduled = false
        var snapshot = self.data
        snapshot.deleted = Array(self.deletedSet)
        self.lock.unlock()

        guard let blob = try? JSONEncoder().encode(snapshot) else {
            return
        }
        UserDefaults.standard.set(blob, forKey: AyuStore.defaultsKey)
        if let url = AyuStore.fileURL {
            try? blob.write(to: url, options: [.atomic])
        }
        // В связку ключей кладём ужатую копию: самые свежие правки и последние удалённые.
        var compact = snapshot
        let newest = compact.edits.keys.sorted(by: { (compact.edits[$0]?.last?.date ?? 0) > (compact.edits[$1]?.last?.date ?? 0) }).prefix(250)
        var trimmed: [String: [AyuEditEntry]] = [:]
        for key in newest {
            trimmed[key] = compact.edits[key]?.map { AyuEditEntry(text: String($0.text.prefix(2000)), date: $0.date) }
        }
        compact.edits = trimmed
        compact.deleted = Array(compact.deleted.suffix(3000))
        if let small = try? JSONEncoder().encode(compact) {
            AyuKeychain.set(AyuStore.keychainKey, data: small)
        }
    }

    // MARK: Удалённые

    func markDeleted(_ key: String) {
        self.lock.lock()
        let inserted = self.deletedSet.insert(key).inserted
        self.lock.unlock()
        if inserted {
            self.scheduleSave()
        }
    }

    func isDeleted(_ key: String) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.deletedSet.contains(key)
    }

    func clearDeleted() {
        self.lock.lock()
        self.deletedSet.removeAll()
        self.data.deleted.removeAll()
        self.lock.unlock()
        self.scheduleSave()
    }

    // MARK: История правок

    func recordEdit(_ key: String, text: String) {
        self.lock.lock()
        var list = self.data.edits[key] ?? []
        if list.last?.text != text {
            list.append(AyuEditEntry(text: text, date: Date().timeIntervalSince1970))
        }
        self.data.edits[key] = list
        self.lock.unlock()
        self.scheduleSave()
    }

    func editEntries(_ key: String) -> [AyuEditEntry] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.data.edits[key] ?? []
    }

    func editHistory(_ key: String) -> [String] {
        return self.editEntries(key).map { $0.text }
    }

    // MARK: Значки

    func hasBadge(_ id: String) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.data.badges[id] != nil
    }

    func setBadge(_ id: String, name: String?) {
        self.lock.lock()
        if let name = name {
            self.data.badges[id] = name
        } else {
            self.data.badges.removeValue(forKey: id)
        }
        self.lock.unlock()
        self.scheduleSave()
    }

    func allBadges() -> [(String, String)] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.data.badges.map { ($0.key, $0.value) }.sorted(by: { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 < $1.1 })
    }
}

/// Резервная копия всех настроек GFPGRAM (ключи UserDefaults с префиксом «ayu.»): Premium-ключ, переключатели,
/// тексты автоответов, вход в админ-панель и т.д. Копия лежит в файле Application Support и в связке ключей iOS.
/// При запуске недостающие значения возвращаются, поэтому после обновления клиента Premium и настройки не слетают.
enum AyuPersist {
    private static let keychainKey = "prefsV1"
    private static let lock = NSLock()
    private static var scheduled = false
    private static let queue = DispatchQueue(label: "gfpgram.prefs", qos: .utility)

    /// Первое обращение один раз восстанавливает данные и подписывается на уход в фон.
    static let ready: Bool = {
        restore()
        NotificationCenter.default.addObserver(forName: Notification.Name("UIApplicationDidEnterBackgroundNotification"), object: nil, queue: nil, using: { _ in
            schedule()
        })
        schedule()
        return true
    }()

    private static var fileURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = base.appendingPathComponent("gfp-data", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        return dir.appendingPathComponent("prefs.json")
    }

    private static func collect() -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in UserDefaults.standard.dictionaryRepresentation() where key.hasPrefix("ayu.") && key != "ayu.store.v2" {
            if value is Bool || value is String || value is Double || value is Int || value is [String] || value is [[String]] {
                result[key] = value
            }
        }
        return result
    }

    private static func restore() {
        var sources: [[String: Any]] = []
        if let url = fileURL, let data = try? Data(contentsOf: url), let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            sources.append(object)
        }
        if let data = AyuKeychain.get(keychainKey), !data.isEmpty, let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            sources.append(object)
        }
        let defaults = UserDefaults.standard
        for source in sources {
            for (key, value) in source where key.hasPrefix("ayu.") && defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }
    }

    /// Отложенная запись копии (не чаще раза в пару секунд).
    static func schedule() {
        lock.lock()
        if scheduled {
            lock.unlock()
            return
        }
        scheduled = true
        lock.unlock()
        queue.asyncAfter(deadline: .now() + 2.0) {
            lock.lock()
            scheduled = false
            lock.unlock()
            let snapshot = collect()
            guard JSONSerialization.isValidJSONObject(snapshot), let data = try? JSONSerialization.data(withJSONObject: snapshot) else {
                return
            }
            if let url = fileURL {
                try? data.write(to: url, options: [.atomic])
            }
            AyuKeychain.set(keychainKey, data: data)
        }
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

    public static let version = "2.2"

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
            Group(title: "ОБХОД ОГРАНИЧЕНИЙ", footer: "Снимает запрет на копирование и сохранение в закрытых чатах и каналах. Если пересылка запрещена, «Переслать» отправит обычное сообщение-копию (текст и медиа), а не пересланное.", toggles: [
                Toggle(key: "allowCopy", title: "Обходить запрет пересылки и копирования"),
                Toggle(key: "forwardCopy", title: "Пересылать запрещённое как копию")
            ]),
            Group(title: "ЧИТЫ", footer: "Лимит аккаунтов применяется после перезапуска приложения. ID сообщения копируется нажатием в меню сообщения.", toggles: [
                Toggle(key: "moreAccounts", title: "До 10 аккаунтов вместо 3"),
                Toggle(key: "showIds", title: "Пункт «ID сообщения» в меню")
            ]),
            Group(title: "ПРОЧЕЕ", footer: "", toggles: [
                Toggle(key: "hideAds", title: "Скрывать рекламу")
            ])
        ]
    }

    private static func flag(_ key: String) -> Bool {
        _ = AyuPersist.ready
        if UserDefaults.standard.object(forKey: key) == nil { return true }
        return UserDefaults.standard.bool(forKey: key)
    }

    /// Переключатели, которые по умолчанию выключены.
    private static let defaultOff: Set<String> = ["showIds", "premiumStub", "premiumDmReply", "premiumKeyword", "premiumReact", "arOnline", "arBusy", "arNight", "arStubOffline"]

    /// Переключатели Premium: у каждого аккаунта свои.
    private static let accountKeys: Set<String> = ["premiumStub", "premiumBackup", "premiumStar", "premiumDmReply", "premiumKeyword", "premiumReact", "arOnline", "arBusy", "arNight", "arStubOffline", "arOffline", "kwAway", "reactAway"]

    private static func storageKey(_ key: String, account: Int64?) -> String {
        if accountKeys.contains(key) {
            return AyuScope.key(key, id: account)
        }
        return "ayu." + key
    }

    private static func flagKey(_ key: String, account: Int64? = nil) -> Bool {
        _ = AyuPersist.ready
        let storage = storageKey(key, account: account)
        if UserDefaults.standard.object(forKey: storage) == nil { return !defaultOff.contains(key) }
        return UserDefaults.standard.bool(forKey: storage)
    }

    /// Значение переключателя по короткому ключу (например "ghostRead").
    public static func value(_ key: String) -> Bool {
        if key == "ghostMode" {
            return self.ghostMaster
        }
        return flagKey(key)
    }

    /// Значение переключателя Premium для конкретного аккаунта.
    public static func value(_ key: String, account: Int64) -> Bool {
        return flagKey(key, account: account)
    }

    /// Семейство шрифта интерфейса ("" — системный). Применяется после перезапуска.
    public static var fontFamily: String {
        get { return UserDefaults.standard.string(forKey: "ayu.fontFamily") ?? "" }
        set {
            UserDefaults.standard.set(newValue, forKey: "ayu.fontFamily")
            AyuPersist.schedule()
        }
    }

    public static func set(_ key: String, _ value: Bool) {
        if key == "ghostMode" {
            self.setGhostMaster(value)
            return
        }
        UserDefaults.standard.set(value, forKey: storageKey(key, account: nil))
        AyuPersist.schedule()
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
        AyuPersist.schedule()
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
    public static var forwardCopy: Bool { return flag("ayu.forwardCopy") }
    public static var moreAccounts: Bool { return flag("ayu.moreAccounts") }
    public static var showIds: Bool { return flagKey("showIds") }

    public static var ownUsername: String? {
        get { return UserDefaults.standard.string(forKey: AyuScope.key("ownUsername")) }
        set { UserDefaults.standard.set(newValue, forKey: AyuScope.key("ownUsername")) }
    }

    // MARK: - Скрытый вход в админ-панель

    public static var adminUnlocked: Bool {
        _ = AyuPersist.ready
        return UserDefaults.standard.bool(forKey: "ayu.adminUnlocked")
    }

    public static func verifyAdminCode(_ code: String) -> Bool {
        if code.trimmingCharacters(in: .whitespacesAndNewlines) == "888090%" {
            UserDefaults.standard.set(true, forKey: "ayu.adminUnlocked")
            AyuPersist.schedule()
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

    /// Сообщение действительно изменено: у него есть прошлая версия, отличающаяся от текущего текста.
    public static func isEdited(id: MessageId, text: String) -> Bool {
        guard let last = AyuStore.shared.editEntries(key(id)).last else { return false }
        return last.text != text
    }

    /// Все прошлые версии с временем замены: [0] — оригинал, дальше по порядку правок.
    public static func entries(id: MessageId) -> [AyuEditEntry] {
        return AyuStore.shared.editEntries(key(id))
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
        var result = title
        if AyuStore.shared.hasBadge(String(id)) {
            result += " #"
        }
        if AyuPremium.isStarVisible(id: id) {
            result += " ⭐"
        }
        return result
    }
}

/// Локальное описание значка в профиле (как «verified by Major» у ботов, но только на этом устройстве).
public enum AyuVerified {
    public static let text = "Официальный аккаунт разработчика клиента"

    /// Красивые значки для профиля одной строкой (nil — значков нет).
    public static func badges(id: Int64, username: String?) -> String? {
        var list: [String] = []
        let official = AyuBadges.contains(id) || (username ?? "").lowercased() == "gfpgram_support"
        if official {
            list.append("🛠 Разработчик")
            list.append("✅ Официальный")
        }
        if AyuPremium.isActive(for: id) {
            list.append("💎 Premium")
        }
        return list.isEmpty ? nil : list.joined(separator: "   ")
    }

    public static func text(id: Int64, username: String?) -> String? {
        if AyuBadges.contains(id) { return text }
        if let username = username, username.lowercased() == "gfpgram_support" { return text }
        return nil
    }
}
