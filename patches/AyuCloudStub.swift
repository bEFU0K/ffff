import Foundation
import Postbox
import SwiftSignalKit

/// Заглушка: ставится вместо AyuCloud.swift, если API поиска сообщений в этой версии Telegram-iOS не подошёл
/// (apply_patches.py пишет причину в лог сборки). Premium и иконка при этом сохраняются локальными копиями.
public enum AyuCloud {
    public static func attach(account: Account) {
    }

    public static func scheduleBackup() {
    }
}
