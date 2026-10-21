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

private final class AyuPremiumStore: @unchecked Sendable {
    static let shared = AyuPremiumStore()
    private let lock = NSLock()
    private var cachedUntil: Double??
    private var lastSeen: Double
    private var lastSeenWritten: Double = 0
    var ownId: Int64 = 0

    init() {
        self.lastSeen = UserDefaults.standard.double(forKey: "ayu.lastSeen")
    }

    func storedKey() -> String? {
        if let key = UserDefaults.standard.string(forKey: "ayu.premiumKey") { return key }
        if let data = AyuKeychain.get("premiumKey") { return String(data: data, encoding: .utf8) }
        return nil
    }

    func saveKey(_ key: String) {
        self.lock.lock()
        defer { self.lock.unlock() }
        UserDefaults.standard.set(key, forKey: "ayu.premiumKey")
        AyuKeychain.set("premiumKey", data: Data(key.utf8))
        self.cachedUntil = nil
    }

    func clearKey() {
        self.lock.lock()
        defer { self.lock.unlock() }
        UserDefaults.standard.removeObject(forKey: "ayu.premiumKey")
        AyuKeychain.set("premiumKey", data: Data())
        self.cachedUntil = nil
    }

    func until() -> Double? {
        self.lock.lock()
        defer { self.lock.unlock() }
        if let cached = self.cachedUntil { return cached }
        var value: Double?
        if let key = self.storedKey(), let parsed = AyuPremium.parse(key: key) {
            value = Double(parsed.until)
        }
        self.cachedUntil = .some(value)
        return value
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

    public static var ownId: Int64 {
        get { return AyuPremiumStore.shared.ownId }
        set { AyuPremiumStore.shared.ownId = newValue }
    }

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
        let current = AyuPremiumStore.shared.until() ?? 0
        if Double(parsed.until) > current {
            AyuPremiumStore.shared.saveKey(key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
        }
        return .ok(Date(timeIntervalSince1970: Double(parsed.until)))
    }

    public static func revokeLocal() {
        AyuPremiumStore.shared.clearKey()
    }

    public static var until: Date? {
        if let value = AyuPremiumStore.shared.until() { return Date(timeIntervalSince1970: value) }
        return nil
    }

    public static var isActive: Bool {
        guard let value = AyuPremiumStore.shared.until() else { return false }
        return AyuPremiumStore.shared.now() < value
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
        let own = AyuPremiumStore.shared.ownId
        return own != 0 && id == own && isActive && AyuSettings.value("premiumStar")
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

// MARK: - Фоновые функции Premium (заглушка при упоминании, бэкап)

public enum AyuPremiumService {
    private static let lock = NSLock()
    private static var started = Set<Int64>()
    private static var lastReply: [Int64: Double] = [:]
    private static let disposables = DisposableSet()

    public static let defaultStub = "Меня сейчас нет на связи, отвечу позже."

    public static var stubText: String {
        get {
            let value = UserDefaults.standard.string(forKey: "ayu.stubText") ?? ""
            return value.isEmpty ? defaultStub : value
        }
        set { UserDefaults.standard.set(newValue, forKey: "ayu.stubText") }
    }

    public static func start(account: Account) {
        let id = account.peerId.toInt64()
        lock.lock()
        let inserted = started.insert(id).inserted
        lock.unlock()
        if !inserted { return }
        AyuPremium.ownId = account.peerId.id._internalGetInt64Value()
        snapshot(account: account)
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
        let _ = (account.postbox.transaction { transaction -> Peer? in
            return transaction.getPeer(account.peerId)
        } |> deliverOnMainQueue).start(next: { peer in
            guard let user = peer as? TelegramUser else { return }
            if let name = user.username { AyuSettings.ownUsername = name }
            if !force && !(AyuPremium.isActive && AyuSettings.value("premiumBackup")) { return }
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

    private static func handle(account: Account, message: Message) {
        if !AyuPremium.isActive || !AyuSettings.value("premiumStub") { return }
        if !message.flags.contains(.Incoming) { return }
        let namespace = message.id.peerId.namespace
        if namespace != Namespaces.Peer.CloudGroup && namespace != Namespaces.Peer.CloudChannel { return }
        if let channel = message.peers[message.id.peerId] as? TelegramChannel, case .broadcast = channel.info { return }
        if message.author?.id == account.peerId { return }
        if !isMention(account: account, message: message) { return }
        let key = message.id.peerId.toInt64()
        let now = Date().timeIntervalSince1970
        lock.lock()
        let last = lastReply[key] ?? 0
        if now - last < 120 {
            lock.unlock()
            return
        }
        lastReply[key] = now
        lock.unlock()
        let text = stubText
        let _ = TelegramEngine(account: account).messages.enqueueOutgoingMessage(to: message.id.peerId, replyTo: EngineMessageReplySubject(messageId: message.id, quote: nil, innerSubject: nil), content: .text(text)).start()
    }
}
