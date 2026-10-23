import Foundation
import Postbox
import SwiftSignalKit
import CryptoKit
import Security

/// Keychain переживает удаление приложения (если не менялись bundle id / Apple ID при переподписи).
enum AyuKeychain {
    static func set(_ account: String, data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "gfpgram",
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "gfpgram",
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess {
            return result as? Data
        }
        return nil
    }
}

/// Текущий аккаунт для настроек GFPGRAM. Premium, переключатели и тексты хранятся отдельно для каждого аккаунта.
/// Окна настроек выставляют аккаунт через setUI, фоновая обработка сообщений — через with(id).
public enum AyuScope {
    private static let lock = NSLock()
    private static var uiId: Int64 = 0
    private static let threadKey = "gfpgram.scope"

    public static var id: Int64 {
        if let value = Thread.current.threadDictionary[threadKey] as? Int64 { return value }
        lock.lock()
        defer { lock.unlock() }
        return uiId
    }

    public static func setUI(_ id: Int64) {
        lock.lock()
        uiId = id
        lock.unlock()
    }

    static func setUIIfUnset(_ id: Int64) {
        lock.lock()
        if uiId == 0 { uiId = id }
        lock.unlock()
    }

    static func with<T>(_ id: Int64, _ body: () -> T) -> T {
        let dict = Thread.current.threadDictionary
        let old = dict[threadKey]
        dict[threadKey] = id
        defer {
            if let old = old { dict[threadKey] = old } else { dict.removeObject(forKey: threadKey) }
        }
        return body()
    }

    /// Ключ UserDefaults для настройки текущего аккаунта.
    static func key(_ base: String, id: Int64? = nil) -> String {
        return "ayu.a\(id ?? self.id)." + base
    }

    /// Номер варианта текста по умолчанию: у каждого аккаунта свой, пока вариантов хватает.
    static func variant(_ count: Int, id: Int64? = nil) -> Int {
        let account = id ?? self.id
        lock.lock()
        defer { lock.unlock() }
        let defaults = UserDefaults.standard
        let storeKey = "ayu.defIdx.\(account)"
        if let value = defaults.object(forKey: storeKey) as? Int { return value % max(count, 1) }
        var used = Set<Int>()
        for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix("ayu.defIdx.") {
            if let number = value as? Int { used.insert(number) }
        }
        var next = 0
        while used.contains(next) { next += 1 }
        defaults.set(next, forKey: storeKey)
        AyuPersist.schedule()
        return next % max(count, 1)
    }
}

private final class AyuPremiumStore: @unchecked Sendable {
    static let shared = AyuPremiumStore()
    private let lock = NSLock()
    private var cached: [Int64: Double] = [:]
    private var lastSeen: Double
    private var lastSeenWritten: Double = 0

    init() {
        _ = AyuPersist.ready
        self.lastSeen = UserDefaults.standard.double(forKey: "ayu.lastSeen")
    }

    private func readKey(_ id: Int64) -> String? {
        let defaults = UserDefaults.standard
        if let key = defaults.string(forKey: "ayu.premiumKey.\(id)"), !key.isEmpty { return key }
        if let data = AyuKeychain.get("premiumKey.\(id)"), let key = String(data: data, encoding: .utf8), !key.isEmpty { return key }
        // Старый общий ключ (до 1.5): отдаём тому аккаунту, на который он выписан
        var legacy: [String] = []
        if let key = defaults.string(forKey: "ayu.premiumKey") { legacy.append(key) }
        if let data = AyuKeychain.get("premiumKey"), let key = String(data: data, encoding: .utf8) { legacy.append(key) }
        for key in legacy {
            if let parsed = AyuPremium.parse(key: key), parsed.userId == id { return key }
        }
        return nil
    }

    func saveKey(_ id: Int64, _ key: String) {
        self.lock.lock()
        defer { self.lock.unlock() }
        UserDefaults.standard.set(key, forKey: "ayu.premiumKey.\(id)")
        AyuKeychain.set("premiumKey.\(id)", data: Data(key.utf8))
        AyuPersist.schedule()
        self.cached[id] = nil
    }

    func clearKey(_ id: Int64) {
        self.lock.lock()
        defer { self.lock.unlock() }
        UserDefaults.standard.removeObject(forKey: "ayu.premiumKey.\(id)")
        AyuKeychain.set("premiumKey.\(id)", data: Data())
        // Старый общий ключ тоже убираем, если он был этого аккаунта
        if let key = UserDefaults.standard.string(forKey: "ayu.premiumKey"), let parsed = AyuPremium.parse(key: key), parsed.userId == id {
            UserDefaults.standard.removeObject(forKey: "ayu.premiumKey")
            AyuKeychain.set("premiumKey", data: Data())
        }
        AyuPersist.schedule()
        self.cached[id] = nil
    }

    /// Срок Premium именно этого аккаунта (ключ должен быть выписан на его id).
    func until(_ id: Int64) -> Double? {
        self.lock.lock()
        defer { self.lock.unlock() }
        if let value = self.cached[id] { return value < 0 ? nil : value }
        var value: Double = -1
        if id != 0, let key = self.readKey(id), let parsed = AyuPremium.parse(key: key), parsed.userId == id {
            value = Double(parsed.until)
        }
        self.cached[id] = value
        return value < 0 ? nil : value
    }

    /// Есть ли Premium хотя бы у одного аккаунта (для иконки приложения: она одна на всё устройство).
    func anyActive() -> Bool {
        var ids = Set<Int64>()
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("ayu.premiumKey.") {
            if let id = Int64(key.dropFirst("ayu.premiumKey.".count)) { ids.insert(id) }
        }
        if let key = UserDefaults.standard.string(forKey: "ayu.premiumKey"), let parsed = AyuPremium.parse(key: key) { ids.insert(parsed.userId) }
        let current = self.now()
        for id in ids {
            if let value = self.until(id), current < value { return true }
        }
        return false
    }

    /// Текущее время, но не меньше максимума, который мы уже видели (защита от перевода часов назад).
    func now() -> Double {
        self.lock.lock()
        defer { self.lock.unlock() }
        let real = Date().timeIntervalSince1970
        let value = max(real, self.lastSeen)
        self.lastSeen = value
        if value - self.lastSeenWritten > 60 {
            self.lastSeenWritten = value
            UserDefaults.standard.set(value, forKey: "ayu.lastSeen")
        }
        return value
    }

    func issued() -> [[String]] {
        return (UserDefaults.standard.array(forKey: "ayu.issued") as? [[String]]) ?? []
    }

    func logIssued(_ row: [String]) {
        self.lock.lock()
        defer { self.lock.unlock() }
        var list = (UserDefaults.standard.array(forKey: "ayu.issued") as? [[String]]) ?? []
        list.insert(row, at: 0)
        if list.count > 30 { list = Array(list.prefix(30)) }
        UserDefaults.standard.set(list, forKey: "ayu.issued")
        AyuPersist.schedule()
    }
}

/// GFPGRAM Premium: ключ активации = id пользователя + время окончания + подпись HMAC.
/// Админ выдаёт ключ в админ-панели и сам задаёт срок; пользователь вводит ключ в окне Premium.
public enum AyuPremium {
    public static let price = "150 ₽"
    public static let supportUsername = "gfpgram_support"
    public static let buyText = "купить премиум на месяц"
    /// ВАЖНО: смени эту строку на свою до сборки. Ключи, выданные с другим секретом, не подойдут.
    private static let secret = "gfpgram-premium-CHANGE-ME-2026"

    private static func signature(_ body: String) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(body.utf8), using: key)
        return Data(mac).prefix(6).map { String(format: "%02X", $0) }.joined()
    }

    public static func makeKey(userId: Int64, until: Int64) -> String {
        let body = String(userId, radix: 36) + "-" + String(until, radix: 36)
        return "GFP-" + body.uppercased() + "-" + signature(body)
    }

    static func parse(key: String) -> (userId: Int64, until: Int64)? {
        let parts = key.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "-").map(String.init)
        if parts.count != 4 || parts[0].uppercased() != "GFP" { return nil }
        let body = parts[1].lowercased() + "-" + parts[2].lowercased()
        if signature(body) != parts[3].uppercased() { return nil }
        guard let userId = Int64(parts[1].lowercased(), radix: 36), let until = Int64(parts[2].lowercased(), radix: 36) else { return nil }
        return (userId, until)
    }

    public enum ActivateResult {
        case ok(Date)
        case invalid
        case expired
        case wrongAccount
    }

    public static func activate(key: String, ownId: Int64) -> ActivateResult {
        guard let parsed = parse(key: key) else { return .invalid }
        if parsed.userId != ownId { return .wrongAccount }
        if Double(parsed.until) <= AyuPremiumStore.shared.now() { return .expired }
        let current = AyuPremiumStore.shared.until(ownId) ?? 0
        if Double(parsed.until) > current {
            AyuPremiumStore.shared.saveKey(ownId, key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
        }
        return .ok(Date(timeIntervalSince1970: Double(parsed.until)))
    }

    public static func revokeLocal() {
        AyuPremiumStore.shared.clearKey(AyuScope.id)
    }

    public static var until: Date? {
        if let value = AyuPremiumStore.shared.until(AyuScope.id) { return Date(timeIntervalSince1970: value) }
        return nil
    }

    /// Premium текущего аккаунта (у каждого аккаунта своя подписка).
    public static var isActive: Bool {
        return isActive(for: AyuScope.id)
    }

    public static func isActive(for id: Int64) -> Bool {
        guard let value = AyuPremiumStore.shared.until(id) else { return false }
        return AyuPremiumStore.shared.now() < value
    }

    /// Premium есть хотя бы у одного аккаунта.
    public static var isActiveAnywhere: Bool {
        return AyuPremiumStore.shared.anyActive()
    }

    public static func format(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "dd.MM.yyyy HH:mm"
        return f.string(from: date)
    }

    public static var statusText: String {
        if isActive, let until = until { return "до " + format(until) }
        return "не активен"
    }

    /// «30» или «30д» = дни, «12ч» = часы, «90м» = минуты. Возвращает секунды.
    public static func parseDuration(_ text: String) -> TimeInterval? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.isEmpty { return nil }
        var unit: Double = 86400
        if let last = s.last, !last.isNumber {
            switch last {
            case "d", "д": unit = 86400
            case "h", "ч": unit = 3600
            case "m", "м": unit = 60
            default: return nil
            }
            s.removeLast()
        }
        guard let n = Double(s.replacingOccurrences(of: ",", with: ".")), n > 0 else { return nil }
        let seconds = n * unit
        if seconds > 3650 * 86400 { return nil }
        return seconds
    }

    /// Админ: создаёт ключ и пишет его в журнал выдачи.
    public static func issue(userId: Int64, name: String, duration: TimeInterval) -> (key: String, until: Date) {
        let until = Int64(AyuPremiumStore.shared.now() + duration)
        let key = makeKey(userId: userId, until: until)
        let date = Date(timeIntervalSince1970: Double(until))
        AyuPremiumStore.shared.logIssued([name, String(until), key])
        return (key, date)
    }

    public static func issuedLog() -> [(name: String, until: Date, key: String)] {
        var result: [(name: String, until: Date, key: String)] = []
        for row in AyuPremiumStore.shared.issued() where row.count == 3 {
            if let u = Double(row[1]) {
                result.append((row[0], Date(timeIntervalSince1970: u), row[2]))
            }
        }
        return result
    }

    static func isStarVisible(id: Int64) -> Bool {
        return id != 0 && isActive(for: id) && AyuSettings.value("premiumStar", account: id)
    }
}

// MARK: - Бэкап аккаунтов

public struct AyuBackupEntry: Codable {
    public var id: Int64
    public var name: String
    public var username: String?
    public var phone: String?
    public var savedAt: Double
}

public enum AyuBackup {
    private static let lock = NSLock()

    public static func entries() -> [AyuBackupEntry] {
        lock.lock()
        defer { lock.unlock() }
        return load()
    }

    private static func load() -> [AyuBackupEntry] {
        if let data = AyuKeychain.get("backups"), let list = try? JSONDecoder().decode([AyuBackupEntry].self, from: data) {
            return list
        }
        return []
    }

    private static func store(_ list: [AyuBackupEntry]) {
        if let data = try? JSONEncoder().encode(list) {
            AyuKeychain.set("backups", data: data)
        }
    }

    public static func upsert(_ entry: AyuBackupEntry) {
        lock.lock()
        defer { lock.unlock() }
        var list = load()
        list.removeAll(where: { $0.id == entry.id })
        list.insert(entry, at: 0)
        store(list)
    }

    public static func remove(id: Int64) {
        lock.lock()
        defer { lock.unlock() }
        var list = load()
        list.removeAll(where: { $0.id == id })
        store(list)
    }

    public static func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        store([])
    }

    public static func text(for entry: AyuBackupEntry) -> String {
        var lines = ["Имя: " + entry.name, "ID: " + String(entry.id)]
        if let u = entry.username, !u.isEmpty { lines.append("Юзер: @" + u) }
        if let p = entry.phone, !p.isEmpty {
            lines.append("Номер: +" + p)
            if let c = AyuProfile.country(phone: p) { lines.append("Страна: " + c) }
        }
        lines.append("Сохранено: " + AyuPremium.format(Date(timeIntervalSince1970: entry.savedAt)))
        return lines.joined(separator: "\n")
    }
}

// MARK: - Слова-триггеры

public struct AyuTrigger: Codable {
    public var word: String
    public var reply: String
    /// Полный id чата (peerId.toInt64()). nil — слово работает во всех чатах.
    public var chatId: Int64?
    public var chatTitle: String?

    public init(word: String, reply: String, chatId: Int64? = nil, chatTitle: String? = nil) {
        self.word = word
        self.reply = reply
        self.chatId = chatId
        self.chatTitle = chatTitle
    }
}

// MARK: - Фоновые функции Premium (автоответчик, заглушка, слова-триггеры, реакции)

public enum AyuPremiumService {
    private static let lock = NSLock()
    private static var started = Set<Int64>()
    private static var lastReply: [String: Double] = [:]
    private static let disposables = DisposableSet()

    public static let maxTriggers = 20

    // Варианты текстов по умолчанию: у каждого аккаунта свой вариант, чтобы ответы не повторялись.
    private static let stubVariants = [
        "{имя}, привет! Сейчас не могу ответить в «{чат}». Увижу ваше сообщение чуть позже и отвечу.",
        "Привет, {имя}! Вижу, что меня позвали в «{чат}», но сейчас занят. Вернусь и отвечу.",
        "{имя}, я заметил упоминание в «{чат}». Ответ будет позже, как только освобожусь.",
        "Здравствуйте, {имя}! В «{чат}» отвечу чуть позже, сейчас не у телефона.",
        "{имя}, принято! Сейчас не на связи, отпишусь в «{чат}» при первой возможности.",
        "О, {имя}, меня тегнули в «{чат}». Отвечу позже, не теряйте!"
    ]
    private static let offlineVariants = [
        "Привет, {имя}! Сейчас меня нет в сети, но я обязательно увижу сообщение и отвечу, как только появлюсь. Если что-то срочное — опиши суть одним сообщением.",
        "{имя}, добрый день! Я сейчас не в сети. Как только вернусь — сразу отвечу.",
        "Привет! Телефон пока не со мной, {имя}. Напиши, что нужно, и я отвечу позже.",
        "Здравствуйте, {имя}. Сейчас недоступен, отвечу, как только смогу.",
        "{имя}, привет! Меня нет на связи. Ваше сообщение не потеряется, отвечу позже.",
        "Хей, {имя}! Я офлайн, но сообщение увидел бы при первой возможности. Ответ будет позже."
    ]
    private static let onlineVariants = [
        "Привет, {имя}! Я на связи, но прямо сейчас не могу ответить. Напишу, как только освобожусь.",
        "{имя}, вижу сообщение! Сейчас чуть занят, отвечу через пару минут.",
        "Привет, {имя}. Я здесь, но руки заняты. Отвечу, как только смогу.",
        "{имя}, секунду! Допишу одно дело и сразу отвечу.",
        "Здравствуйте, {имя}! Сообщение получил, отвечу чуть позже.",
        "Я тут, {имя}, но пока не могу нормально ответить. Скоро вернусь к чату."
    ]
    private static let busyVariants = [
        "Привет, {имя}! Сейчас я занят и отвечу позже. Если вопрос срочный — коротко опиши суть, и я отвечу в первую очередь.",
        "{имя}, сейчас у меня важное дело. Отвечу, как только закончу.",
        "Привет! Я занят до конца дела, {имя}. Если срочно — напиши одним сообщением.",
        "Здравствуйте, {имя}. Занят, вернусь к вам позже.",
        "{имя}, я в делах. Ответ придёт позже, спасибо за терпение.",
        "Сейчас не до чатов, {имя}. Отвечу, когда освобожусь."
    ]
    private static let nightVariants = [
        "Привет, {имя}! Сейчас {время} — я отдыхаю и отвечу после {до}. Напиши, что нужно, и я отвечу утром.",
        "{имя}, на часах {время}, я сплю. Отвечу после {до}.",
        "Тсс, {имя}, ночь! Сейчас {время}. Напишу после {до}.",
        "Добрый вечер, {имя}. Уже {время}, отдыхаю. Отвечу после {до}.",
        "{имя}, до {до} меня не будет. Сообщение прочту утром и отвечу.",
        "Ночное время ({время}), {имя}. Отвечу после {до}, спокойной ночи!"
    ]

    private static func pick(_ list: [String]) -> String {
        return list[AyuScope.variant(list.count)]
    }

    public static var defaultStub: String { return pick(stubVariants) }
    public static var defaultDmReply: String { return pick(offlineVariants) }
    public static var defaultOnlineReply: String { return pick(onlineVariants) }
    public static var defaultBusyReply: String { return pick(busyVariants) }
    public static var defaultNightReply: String { return pick(nightVariants) }

    private static func storedText(_ base: String, _ fallback: () -> String) -> String {
        let value = UserDefaults.standard.string(forKey: AyuScope.key(base)) ?? ""
        return value.isEmpty ? fallback() : value
    }

    private static func setText(_ base: String, _ value: String) {
        UserDefaults.standard.set(value, forKey: AyuScope.key(base))
        AyuPersist.schedule()
    }

    /// Заглушка при упоминании в группе (отдельная для каждого аккаунта).
    public static var stubText: String {
        get { return storedText("stubText", { defaultStub }) }
        set { setText("stubText", newValue) }
    }

    /// Текст автоответчика «когда я не в сети».
    public static var dmReplyText: String {
        get { return storedText("dmReplyText", { defaultDmReply }) }
        set { setText("dmReplyText", newValue) }
    }

    /// Ответ, когда приложение открыто («в сети»).
    public static var onlineReplyText: String {
        get { return storedText("ar.onlineText", { defaultOnlineReply }) }
        set { setText("ar.onlineText", newValue) }
    }

    /// Ответ в режиме «Занят» (включается вручную).
    public static var busyReplyText: String {
        get { return storedText("ar.busyText", { defaultBusyReply }) }
        set { setText("ar.busyText", newValue) }
    }

    /// Ответ ночью.
    public static var nightReplyText: String {
        get { return storedText("ar.nightText", { defaultNightReply }) }
        set { setText("ar.nightText", newValue) }
    }

    /// Ночь с ... часов (0-23).
    public static var nightStart: Int {
        get {
            let v = UserDefaults.standard.object(forKey: AyuScope.key("ar.nightStart")) as? Int
            return min(max(v ?? 23, 0), 23)
        }
        set { UserDefaults.standard.set(min(max(newValue, 0), 23), forKey: AyuScope.key("ar.nightStart")); AyuPersist.schedule() }
    }

    /// Ночь до ... часов (0-23).
    public static var nightEnd: Int {
        get {
            let v = UserDefaults.standard.object(forKey: AyuScope.key("ar.nightEnd")) as? Int
            return min(max(v ?? 8, 0), 23)
        }
        set { UserDefaults.standard.set(min(max(newValue, 0), 23), forKey: AyuScope.key("ar.nightEnd")); AyuPersist.schedule() }
    }

    public static let replyIntervals: [Int] = [1, 5, 10, 30, 60, 240]

    /// Не чаще чем раз в ... минут на собеседника.
    public static var replyMinutes: Int {
        get {
            let v = UserDefaults.standard.object(forKey: AyuScope.key("ar.minutes")) as? Int
            return replyIntervals.contains(v ?? 10) ? (v ?? 10) : 10
        }
        set { UserDefaults.standard.set(newValue, forKey: AyuScope.key("ar.minutes")); AyuPersist.schedule() }
    }

    public static func nextReplyMinutes() {
        let list = replyIntervals
        let index = list.firstIndex(of: replyMinutes) ?? 0
        replyMinutes = list[(index + 1) % list.count]
    }

    public static func minutesLabel(_ minutes: Int) -> String {
        if minutes >= 60 { return String(minutes / 60) + " ч" }
        return String(minutes) + " мин"
    }

    public static func hourLabel(_ hour: Int) -> String {
        return (hour < 10 ? "0" : "") + String(hour) + ":00"
    }

    public static func resetTexts() {
        for key in ["stubText", "dmReplyText", "ar.onlineText", "ar.busyText", "ar.nightText"] {
            UserDefaults.standard.removeObject(forKey: AyuScope.key(key))
        }
        AyuPersist.schedule()
    }

    /// Приложение открыто (экран активен) — это и есть «я в сети».
    public static var isForeground: Bool = true
    private static var observing = false

    private static func observeAppState() {
        lock.lock()
        let first = !observing
        observing = true
        lock.unlock()
        if !first { return }
        let center = NotificationCenter.default
        center.addObserver(forName: Notification.Name("UIApplicationDidBecomeActiveNotification"), object: nil, queue: nil, using: { _ in
            AyuPremiumService.isForeground = true
        })
        center.addObserver(forName: Notification.Name("UIApplicationWillResignActiveNotification"), object: nil, queue: nil, using: { _ in
            AyuPremiumService.isForeground = false
        })
    }

    public static func isNightNow() -> Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        let from = nightStart
        let to = nightEnd
        if from == to { return false }
        if from < to { return hour >= from && hour < to }
        return hour >= from || hour < to
    }

    /// Подставляет {имя}, {чат}, {время}, {дата}, {до} в текст ответа.
    public static func fill(_ text: String, name: String, chat: String) -> String {
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "ru_RU")
        dateFormatter.dateFormat = "d MMMM"
        let now = Date()
        var result = text
        result = result.replacingOccurrences(of: "{имя}", with: name)
        result = result.replacingOccurrences(of: "{чат}", with: chat)
        result = result.replacingOccurrences(of: "{время}", with: timeFormatter.string(from: now))
        result = result.replacingOccurrences(of: "{дата}", with: dateFormatter.string(from: now))
        result = result.replacingOccurrences(of: "{до}", with: hourLabel(nightEnd))
        return result
    }

    /// Какой текст отправить автоответчиком сейчас. Приоритет: «Занят» → ночь → «в сети» / «не в сети». nil — не отвечать.
    public static func autoReplyText() -> String? {
        if AyuSettings.value("arBusy") { return busyReplyText }
        if AyuSettings.value("arNight") && isNightNow() { return nightReplyText }
        if isForeground {
            return AyuSettings.value("arOnline") ? onlineReplyText : nil
        }
        return AyuSettings.value("arOffline") ? dmReplyText : nil
    }

    // MARK: Слова-триггеры (до 20 штук, у каждого свой ответ и свой чат)

    public static var triggers: [AyuTrigger] {
        get {
            guard let text = UserDefaults.standard.string(forKey: AyuScope.key("triggers")), let data = text.data(using: .utf8),
                  let list = try? JSONDecoder().decode([AyuTrigger].self, from: data) else {
                return []
            }
            return list
        }
        set {
            let list = Array(newValue.prefix(maxTriggers))
            if let data = try? JSONEncoder().encode(list), let text = String(data: data, encoding: .utf8) {
                UserDefaults.standard.set(text, forKey: AyuScope.key("triggers"))
                AyuPersist.schedule()
            }
        }
    }

    /// Эмодзи для авто-реакции на входящие личные сообщения.
    public static var reactEmoji: String {
        get {
            let value = UserDefaults.standard.string(forKey: AyuScope.key("reactEmoji")) ?? ""
            return value.isEmpty ? "👍" : value
        }
        set { setText("reactEmoji", newValue) }
    }

    public static func start(account: Account) {
        let id = account.peerId.toInt64()
        let accountId = account.peerId.id._internalGetInt64Value()
        lock.lock()
        let inserted = started.insert(id).inserted
        lock.unlock()
        if !inserted { return }
        AyuScope.setUIIfUnset(accountId)
        observeAppState()
        snapshot(account: account)
        // Иконка возвращается после обновления из локальных копий
        AyuIconKeeper.restore()
        let disposable = account.stateManager.notificationMessages.start(next: { batches in
            for item in batches {
                for message in item.0 {
                    handle(account: account, message: message)
                }
            }
        })
        disposables.add(disposable)
    }

    public static func snapshot(account: Account, force: Bool = false) {
        let accountId = account.peerId.id._internalGetInt64Value()
        let _ = (account.postbox.transaction { transaction -> Peer? in
            return transaction.getPeer(account.peerId)
        } |> deliverOnMainQueue).start(next: { peer in
            guard let user = peer as? TelegramUser else { return }
            let allowed: Bool = AyuScope.with(accountId, {
                if let name = user.username { AyuSettings.ownUsername = name }
                return AyuPremium.isActive && AyuSettings.value("premiumBackup")
            })
            if !force && !allowed { return }
            var name = user.firstName ?? ""
            if let last = user.lastName, !last.isEmpty { name += " " + last }
            AyuBackup.upsert(AyuBackupEntry(id: user.id.id._internalGetInt64Value(), name: name.isEmpty ? "Без имени" : name, username: user.username, phone: user.phone, savedAt: Date().timeIntervalSince1970))
        })
    }

    private static func isMention(account: Account, message: Message) -> Bool {
        if message.attributes.contains(where: { $0 is ConsumablePersonalMentionMessageAttribute }) { return true }
        let own = (AyuSettings.ownUsername ?? "").lowercased()
        for attribute in message.attributes {
            guard let entities = attribute as? TextEntitiesMessageAttribute else { continue }
            for entity in entities.entities {
                switch entity.type {
                case .Mention:
                    if !own.isEmpty {
                        let text = message.text as NSString
                        let range = NSRange(entity.range)
                        if range.location + range.length <= text.length, text.substring(with: range).lowercased() == "@" + own { return true }
                    }
                case let .TextMention(peerId):
                    if peerId == account.peerId { return true }
                default:
                    break
                }
            }
        }
        return false
    }

    /// Не чаще одного раза за interval секунд для ключа.
    private static func allow(_ key: String, interval: Double) -> Bool {
        let now = Date().timeIntervalSince1970
        lock.lock()
        defer { lock.unlock() }
        let last = lastReply[key] ?? 0
        if now - last < interval {
            return false
        }
        lastReply[key] = now
        return true
    }

    private static func send(account: Account, peerId: PeerId, text: String, replyTo: MessageId?) {
        var reply: EngineMessageReplySubject?
        if let replyTo = replyTo {
            reply = EngineMessageReplySubject(messageId: replyTo, quote: nil, innerSubject: nil)
        }
        let _ = TelegramEngine(account: account).messages.enqueueOutgoingMessage(to: peerId, replyTo: reply, content: .text(text)).start()
    }

    /// Все настройки и Premium берутся для аккаунта, на который пришло сообщение.
    private static func handle(account: Account, message: Message) {
        let accountId = account.peerId.id._internalGetInt64Value()
        AyuScope.with(accountId, {
            handleScoped(account: account, accountId: accountId, message: message)
        })
    }

    private static func handleScoped(account: Account, accountId: Int64, message: Message) {
        if !AyuPremium.isActive { return }
        if !message.flags.contains(.Incoming) { return }
        if message.author?.id == account.peerId { return }
        if let author = message.author as? TelegramUser, author.botInfo != nil { return }
        let peerId = message.id.peerId
        let namespace = peerId.namespace
        let isPrivate = namespace == Namespaces.Peer.CloudUser
        let isGroup = namespace == Namespaces.Peer.CloudGroup || namespace == Namespaces.Peer.CloudChannel
        if !isPrivate && !isGroup { return }
        if let channel = message.peers[peerId] as? TelegramChannel, case .broadcast = channel.info { return }
        let chatKey = String(accountId) + ":" + String(peerId.toInt64())
        let chatTitle = message.peers[peerId]?.debugDisplayTitle ?? "чат"
        var senderName = "друг"
        if let author = message.author as? TelegramUser, let first = author.firstName, !first.isEmpty {
            senderName = first
        }

        if isPrivate && peerId != account.peerId && peerId.id._internalGetInt64Value() != 777000 {
            // Автоответчик в личных чатах: текст зависит от состояния (не в сети / в сети / ночью / занят)
            if AyuSettings.value("premiumDmReply"), let template = autoReplyText(), allow("dm:" + chatKey, interval: Double(replyMinutes * 60)) {
                send(account: account, peerId: peerId, text: fill(template, name: senderName, chat: chatTitle), replyTo: nil)
            }
            // Авто-реакция на входящие личные сообщения
            if AyuSettings.value("premiumReact") {
                TelegramEngine(account: account).messages.setMessageReactions(ids: [message.id], reactions: [.builtin(reactEmoji)])
            }
        }

        // Слова-триггеры (личные чаты и группы): срабатывает первое подходящее слово, раз в минуту на слово и чат
        if AyuSettings.value("premiumKeyword") && !message.text.isEmpty {
            let lowered = message.text.lowercased()
            let chatFull = peerId.toInt64()
            for trigger in triggers {
                let word = trigger.word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if word.isEmpty || trigger.reply.isEmpty { continue }
                if let only = trigger.chatId, only != chatFull { continue }
                if !lowered.contains(word) { continue }
                if allow("kw:" + chatKey + ":" + word, interval: 60) {
                    send(account: account, peerId: peerId, text: fill(trigger.reply, name: senderName, chat: chatTitle), replyTo: message.id)
                }
                break
            }
        }

        if isGroup && isMention(account: account, message: message) {
            // Заглушка при упоминании: раз в 2 минуты на группу
            let stubAllowed = !AyuSettings.value("arStubOffline") || !isForeground
            if AyuSettings.value("premiumStub") && stubAllowed && allow("stub:" + chatKey, interval: 120) {
                send(account: account, peerId: peerId, text: fill(stubText, name: senderName, chat: chatTitle), replyTo: message.id)
            }
        }
    }
}
