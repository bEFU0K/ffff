#!/usr/bin/env python3
"""Собирает ключевые экраны Telegram-iOS (чаты, пузыри, звонки, вход, окна, тема) в один zip.
Запуск: python3 tools/export_sources.py <путь к клону Telegram-iOS> <выходной zip>
Файл потом можно отдать Claude: он правит настоящие исходники, а не наугад."""
import os, sys, zipfile

WANTED = [
    # список чатов и контакты
    "ChatListItem.swift", "ChatListControllerNode.swift", "ChatListController.swift", "ChatListNode.swift",
    "ContactsController.swift", "ContactListNode.swift",
    # чат: пузыри, ввод, фон сообщений
    "ChatMessageBubbleItemNode.swift", "ChatMessageBackground.swift", "ChatMessageItemCommon.swift",
    "ChatTextInputPanelNode.swift", "ChatControllerNode.swift",
    # звонки
    "CallController.swift", "CallControllerNode.swift", "CallControllerNodeV2.swift", "CallControllerButtonsNode.swift",
    "CallControllerToastNode.swift", "IncomingCallController.swift",
    # вход и регистрация
    "AuthorizationSequenceController.swift", "AuthorizationSequenceSplashController.swift",
    "AuthorizationSequencePhoneEntryController.swift", "AuthorizationSequencePhoneEntryControllerNode.swift",
    "AuthorizationSequenceCodeEntryController.swift", "AuthorizationSequenceCodeEntryControllerNode.swift",
    "AuthorizationSequencePasswordEntryController.swift", "AuthorizationSequenceSignUpController.swift",
    # диалоги, меню действий
    "AlertController.swift", "TextAlertController.swift", "ActionSheetController.swift", "ActionSheetItemNode.swift",
    "ActionSheetButtonItem.swift", "ContextController.swift",
    # нижняя панель и тема
    "TabBarController.swift", "TabBarNode.swift",
    "DefaultDayPresentationTheme.swift", "DefaultDarkPresentationTheme.swift", "PresentationThemeSettings.swift",
]

def main():
    root, out = sys.argv[1], sys.argv[2]
    found, missing = {}, []
    for name in WANTED:
        hits = []
        for base, dirs, files in os.walk(os.path.join(root, "submodules")):
            dirs[:] = [d for d in dirs if d not in (".git", "node_modules")]
            if name in files:
                hits.append(os.path.join(base, name))
        if hits:
            found[name] = hits
        else:
            missing.append(name)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for name, hits in found.items():
            for h in hits:
                z.write(h, os.path.relpath(h, root))
        z.writestr("REPORT.txt", "Найдено: %d\nНе найдено: %s\n" % (len(found), ", ".join(missing) or "нет"))
    print("найдено файлов:", sum(len(v) for v in found.values()), "не найдено:", missing)

main()
