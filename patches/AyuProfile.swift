import Foundation
import Postbox

public enum AyuProfile {
    private static let codes: [String: String] = [
        "1": "США/Канада", "7": "Россия/Казахстан", "20": "Египет", "27": "ЮАР", "30": "Греция",
        "31": "Нидерланды", "33": "Франция", "34": "Испания", "36": "Венгрия", "39": "Италия",
        "44": "Великобритания", "48": "Польша", "49": "Германия", "52": "Мексика", "55": "Бразилия",
        "60": "Малайзия", "62": "Индонезия", "63": "Филиппины", "66": "Таиланд", "81": "Япония",
        "82": "Южная Корея", "84": "Вьетнам", "86": "Китай", "90": "Турция", "91": "Индия", "98": "Иран",
        "370": "Литва", "371": "Латвия", "372": "Эстония", "373": "Молдова", "374": "Армения",
        "375": "Беларусь", "380": "Украина", "966": "Саудовская Аравия", "971": "ОАЭ", "972": "Израиль",
        "992": "Таджикистан", "993": "Туркменистан", "994": "Азербайджан", "995": "Грузия",
        "996": "Киргизия", "998": "Узбекистан"
    ]

    /// Страна по номеру. Работает только если номер виден клиенту (скрытые номера недоступны).
    public static func country(phone: String?) -> String? {
        guard let phone = phone, !phone.isEmpty else { return nil }
        for len in [3, 2, 1] where phone.count >= len {
            if let name = codes[String(phone.prefix(len))] { return name }
        }
        return nil
    }

    public static func dc(user: TelegramUser) -> Int? {
        if let res = user.photo.first?.resource as? TelegramCloudMediaResource {
            return Int(res.datacenterId)
        }
        return nil
    }

    public static func infoText(for user: TelegramUser) -> String {
        var parts = ["ID: \(user.id.id._internalGetInt64Value())"]
        if let dc = dc(user: user) { parts.append("DC\(dc)") }
        if let c = country(phone: user.phone) { parts.append(c) }
        return parts.joined(separator: " · ")
    }
}
