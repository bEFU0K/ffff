import Foundation
import Postbox

public enum AyuSettings {
    private static func flag(_ key: String) -> Bool {
        if UserDefaults.standard.object(forKey: key) == nil { return true }
        return UserDefaults.standard.bool(forKey: key)
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
}

public enum AyuEditHistory {
    private static let storeKey = "ayu.editHistory"

    public static func key(_ id: MessageId) -> String {
        return "\(id.peerId.toInt64())_\(id.namespace)_\(id.id)"
    }

    public static func record(id: MessageId, text: String) {
        if !AyuSettings.saveEdits || text.isEmpty { return }
        var all = UserDefaults.standard.dictionary(forKey: storeKey) as? [String: [String]] ?? [:]
        var list = all[key(id)] ?? []
        if list.last != text { list.append(text) }
        all[key(id)] = list
        UserDefaults.standard.set(all, forKey: storeKey)
    }

    public static func history(id: MessageId) -> [String] {
        let all = UserDefaults.standard.dictionary(forKey: storeKey) as? [String: [String]] ?? [:]
        return all[key(id)] ?? []
    }
}
