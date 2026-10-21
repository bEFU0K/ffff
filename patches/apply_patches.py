#!/usr/bin/env python3
"""Патчи GFPGRAM для Telegram-iOS.
Использование: apply_patches.py <telegram-dir> [группы,которые,отключить]
Критичные патчи (название, иконка, App Group) — если не применились, скрипт падает (exit 1),
чтобы не тратить 2 часа на сборку заведомо нерабочего приложения."""
import os, re, shutil, sys, json

root = sys.argv[1]
disabled = set(x.strip() for x in (sys.argv[2] if len(sys.argv) > 2 else "").split(",") if x.strip())
here = os.path.dirname(os.path.abspath(__file__))
core = os.path.join(root, "submodules/TelegramCore/Sources")
app_dir = os.path.join(root, "Telegram/Telegram-iOS")
APP_NAME = "GFPGRAM"
CRITICAL = ["branding-name", "branding-icon", "group-fallback", "gfp-menu-enum", "gfp-menu-action", "gfp-menu-item", "gfp-menu-dep", "gfp-ghost-button", "gfp-deleted-chat", "gfp-deleted-bubble", "gfp-badges", "gfp-icons-build", "gfp-icons-list", "bypass-peer"]
hits_by_label = {}

def read(p):
    with open(p, encoding="utf-8") as f:
        return f.read()

def write(p, s):
    with open(p, "w", encoding="utf-8") as f:
        f.write(s)

def walk(base, exts=(".swift",)):
    for d, _, fs in os.walk(base):
        for f in fs:
            if f.endswith(exts):
                yield os.path.join(d, f)

def patch(label, pattern, repl, base=None, filename=None, flags=re.M | re.S):
    """Применяет regex-замену. filename — имя файла (basename), base — каталог поиска."""
    if label in disabled:
        print(f"SKIP {label}: disabled"); return
    base = base or core
    total = 0
    for p in walk(base):
        if filename and os.path.basename(p) != filename:
            continue
        try:
            src = read(p)
        except Exception:
            continue
        new, n = re.subn(pattern, repl, src, flags=flags)
        if n:
            write(p, new)
            total += n
            print(f"OK   {label}: {n} in {os.path.relpath(p, root)}")
    hits_by_label[label] = hits_by_label.get(label, 0) + total
    if total == 0:
        print(f"MISSING {label}: anchor not found")


def patch_plain(label, path, pattern, repl):
    if label in disabled:
        print(f"SKIP {label}: disabled"); return
    if not os.path.exists(path):
        print(f"MISSING {label}: {path} not found"); return
    src = read(path)
    new, n = re.subn(pattern, repl, src, flags=re.M | re.S)
    if n:
        write(path, new)
    hits_by_label[label] = hits_by_label.get(label, 0) + n
    print(f"OK   {label}: {n} in {os.path.relpath(path, root)}" if n else f"MISSING {label}: anchor not found")

# ---------- свои Swift-файлы ----------
shutil.copy(os.path.join(here, "AyuSettings.swift"), os.path.join(core, "AyuSettings.swift"))
shutil.copy(os.path.join(here, "AyuProfile.swift"), os.path.join(core, "AyuProfile.swift"))
shutil.copy(os.path.join(here, "AyuPremium.swift"), os.path.join(core, "AyuPremium.swift"))
if "forward-copy" in disabled:
    print("SKIP forward-copy: disabled")
else:
    shutil.copy(os.path.join(here, "AyuForward.swift"), os.path.join(core, "AyuForward.swift"))
print("OK   Ayu*.swift added")

# ---------- Режим призрака ----------
# Прочитано: не отправляем readHistory на сервер (локально чат остаётся прочитанным)
patch("ghost-read",
      r"(func pushPeerReadState\([^{]*?\)\s*->\s*Signal<PeerReadState, PeerReadStateValidationError>\s*\{)",
      r"\1\n    if AyuSettings.ghostRead { return .single(readState) }",
      filename="SynchronizePeerReadState.swift")

patch("ghost-typing",
      r"(private func requestActivity\([^{]*?\)\s*->\s*Signal<Void, NoError>\s*\{)",
      r"\1\n    if AyuSettings.ghostTyping { return .complete() }",
      filename="ManagedLocalInputActivities.swift")

patch("ghost-online",
      r"account\.updateStatus\(offline: ([^()\n]*(?:\([^()\n]*\))?[^()\n]*)\)",
      r"account.updateStatus(offline: AyuSettings.ghostOnline ? .boolTrue : (\1))",
      filename="ManagedAccountPresence.swift")

patch("ghost-stories",
      r"(func _internal_markStoryAsSeen\([^{]*?\)\s*->\s*Signal<Never, NoError>\s*\{)",
      r"\1\n    if AyuSettings.ghostStories { return .complete() }")

patch("ghost-screenshot",
      r"(func _internal_addSecretChatMessageScreenshot\([^{]*?\)\s*->\s*Signal<Void, NoError>\s*\{)",
      r"\1\n    if AyuSettings.ghostScreenshot { return .complete() }")

# «Прослушано»/просмотрено: локально помечаем, но на сервер не синхронизируем
patch("ghost-consume",
      r"(func addSynchronizeConsumeMessageContentsOperation\(transaction: Transaction, messageIds: \[MessageId\]\)\s*\{)",
      r"\1\n    if AyuSettings.ghostConsume { return }",
      filename="SynchronizeConsumeMessageContentsOperation.swift")

# ---------- Удалённые сообщения / история ----------
patch("keep-deleted",
      r"(case let \.DeleteMessages\(ids\):\n)",
      r"\1                if AyuSettings.keepDeleted {\n"
      r"                    for ayuId in ids where transaction.getMessage(ayuId) != nil {\n"
      r"                        AyuDeleted.mark(ayuId)\n"
      r"                    }\n"
      r"                    break\n"
      r"                }\n",
      filename="AccountStateManagementUtils.swift")
# Личные чаты и обычные группы присылают удаление по глобальным id: здесь раньше не ставилась метка 🗑
patch("keep-deleted",
      r"(case let \.DeleteMessagesWithGlobalIds\(ids\):\n)",
      r"\1                if AyuSettings.keepDeleted {\n"
      r"                    for ayuId in transaction.messageIdsForGlobalIds(ids) where transaction.getMessage(ayuId) != nil {\n"
      r"                        AyuDeleted.mark(ayuId)\n"
      r"                    }\n"
      r"                    break\n"
      r"                }\n",
      filename="AccountStateManagementUtils.swift")

patch("keep-cleared",
      r"(case let \.UpdateMinAvailableMessage\(id\):\n)",
      r"\1                if AyuSettings.keepCleared { break }\n",
      filename="AccountStateManagementUtils.swift")

patch("edit-history",
      r"(case let \.EditMessage\(id, [A-Za-z_]+\):\n)",
      r"\1                if let ayuPrev = transaction.getMessage(id) { AyuEditHistory.record(id: id, text: ayuPrev.text) }\n",
      filename="AccountStateManagementUtils.swift")

# Самоудаляющиеся сообщения не стираются
patch("keep-selfdestruct",
      r"if message\.id\.peerId\.namespace == Namespaces\.Peer\.SecretChat \|\| isRemove \{",
      r"if AyuSettings.keepSelfDestruct {\n                        } else if message.id.peerId.namespace == Namespaces.Peer.SecretChat || isRemove {",
      filename="ManagedAutoremoveMessageOperations.swift")

# ---------- Реклама ----------
patch("hide-ads",
      r"(\n    func activate\(\) \{\n)",
      r"\1        if AyuSettings.hideAds { return }\n",
      filename="AdMessages.swift")

# ---------- Копирование из закрытых каналов ----------
patch("allow-copy",
      r"(func isCopyProtected\(\)\s*->\s*Bool\s*\{)",
      r"\1\n        if AyuSettings.allowCopy { return false }",
      filename="MessageUtils.swift")

# ---------- Инфо в профиле (экспериментально, по умолчанию выключено) ----------
patch("profile-info",
      r"^(\s*)(if let user = data\.peer as\? TelegramUser \{)\s*$",
      r"\1\2\n\1    items[.peerInfo, default: []].append(PeerInfoScreenLabeledValueItem(id: 9001, label: \"Ayu\", text: AyuProfile.infoText(for: user), textColor: .primary, action: nil, longTapAction: nil, requestLayout: { _ in }))",
      base=os.path.join(root, "submodules/TelegramUI"), filename="PeerInfoScreen.swift", flags=re.M)

# ======================= БРЕНДИНГ =======================
# 1) Название. В актуальном Telegram-iOS оно зашито в Telegram/BUILD (plist_fragment), а не в Info.plist.
if "branding-name" in disabled:
    print("SKIP branding-name: disabled")
else:
    n_total = 0
    build_path = os.path.join(root, "Telegram/BUILD")
    if os.path.exists(build_path):
        s = read(build_path)
        s, n1 = re.subn(r"(<key>CFBundleDisplayName</key>\s*<string>)Telegram(</string>)", r"\g<1>%s\g<2>" % APP_NAME, s)
        # CFBundleName — только в TelegramInfoPlist (главное приложение)
        m = re.search(r'name = "TelegramInfoPlist".*?\n\)', s, flags=re.S)
        n2 = 0
        if m:
            block, n2 = re.subn(r"(<key>CFBundleName</key>\s*<string>)Telegram(</string>)", r"\g<1>%s\g<2>" % APP_NAME, m.group(0))
            s = s[:m.start()] + block + s[m.end():]
        write(build_path, s)
        n_total += n1 + n2
        print(f"OK   branding-name: Telegram/BUILD DisplayName x{n1}, BundleName x{n2}")
    # старые версии: Info.plist / InfoPlist.strings
    for d, _, fs in os.walk(app_dir):
        for f in fs:
            p = os.path.join(d, f)
            if f == "Info.plist":
                s = open(p, encoding="utf-8", errors="ignore").read()
                s2, c = re.subn(r"(<key>(?:CFBundleDisplayName|CFBundleName)</key>\s*<string>)[^<$]*(</string>)", r"\g<1>%s\g<2>" % APP_NAME, s)
                if c: write(p, s2); n_total += c
            elif f == "InfoPlist.strings":
                s = open(p, encoding="utf-8", errors="ignore").read()
                s2, c = re.subn(r'("CFBundle(?:DisplayName|Name)"\s*=\s*)"[^"]*";', r'\1"%s";' % APP_NAME, s)
                if c: write(p, s2); n_total += c
    hits_by_label["branding-name"] = n_total
    if n_total == 0:
        print("MISSING branding-name")

# 2) Иконка. Основная иконка — Telegram.icon (Icon Composer, iOS 26), плюс PNG альтернативных иконок.
if "branding-icon" in disabled:
    print("SKIP branding-icon: disabled")
else:
    try:
        from PIL import Image
        src_icon = Image.open(os.path.join(here, "..", "assets", "icon.png")).convert("RGB")
        n = 0
        # 2a) Telegram.icon -> один PNG-слой на весь холст
        icon_pkg = os.path.join(app_dir, "Telegram.icon")
        if os.path.isdir(icon_pkg):
            shutil.rmtree(icon_pkg)
            os.makedirs(os.path.join(icon_pkg, "Assets"))
            src_icon.resize((1024, 1024), Image.LANCZOS).save(os.path.join(icon_pkg, "Assets", "icon.png"))
            doc = {
                "fill": {"solid": "srgb:1.00000,1.00000,1.00000,1.00000"},
                "groups": [{"layers": [{"glass": False, "image-name": "icon.png", "name": "icon"}],
                            "shadow": {"kind": "neutral", "opacity": 0.5},
                            "translucency": {"enabled": False, "value": 0.5}}],
                "supported-platforms": {"circles": ["watchOS"], "squares": "shared"},
            }
            with open(os.path.join(icon_pkg, "icon.json"), "w") as f:
                json.dump(doc, f, indent=2)
            n += 1
            print("OK   branding-icon: Telegram.icon replaced")
        # 2b) все PNG в *.appiconset и *.alticon и IconDefault-*.png
        for d, _, fs in os.walk(app_dir):
            in_icons = d.endswith((".appiconset", ".alticon")) or os.path.basename(d) == "Telegram-iOS"
            if not in_icons:
                continue
            for f in fs:
                if not f.lower().endswith(".png"):
                    continue
                if os.path.basename(d) == "Telegram-iOS" and not f.startswith("IconDefault"):
                    continue
                p = os.path.join(d, f)
                try:
                    w, h = Image.open(p).size
                    src_icon.resize((w, h), Image.LANCZOS).save(p)
                    n += 1
                except Exception as e:
                    print(f"WARN icon {f}: {e}")
        hits_by_label["branding-icon"] = n
        print(f"OK   branding-icon: {n} items")
    except ImportError:
        print("MISSING branding-icon: Pillow not installed")

# 3) «Владелец» -> «#»
if "owner-hash" in disabled:
    print("SKIP owner-hash: disabled")
else:
    n = 0
    for d, _, fs in os.walk(app_dir):
        for f in fs:
            if f == "Localizable.strings":
                p = os.path.join(d, f)
                s = open(p, encoding="utf-8", errors="ignore").read()
                s2, c = re.subn(r'^("Channel\.Management\.Label(?:Owner|Creator)"\s*=\s*)"[^"]*";', r'\1"#";', s, flags=re.M)
                if c: write(p, s2); n += c
    print(f"OK   owner-hash (bundled): {n}" if n else "MISSING owner-hash (bundled)")
    # серверный языковой пакет перекрывает встроенные строки
    patch("owner-hash",
          r"(public func dictFromLocalization\(_ value: Localization\) -> \[String: String\] \{.*?)(\n    return dict\n\})",
          r'\1\n    dict["Channel.Management.LabelOwner"] = "#"\n    dict["Channel.Management.LabelCreator"] = "#"\2',
          base=os.path.join(root, "submodules/TelegramPresentationData"), filename="PresentationData.swift")

# ======================= Чёрный экран на Sideloadly =======================
# Бесплатный Apple ID не даёт App Groups: containerURL(...) == nil, AppDelegate показывает «Error 2»
# и выходит -> чёрный экран. Подставляем обычную папку в Application Support.
GROUP_FALLBACK = (
    "{ () -> URL? in "
    "guard let ayuBase = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }; "
    "let ayuUrl = ayuBase.appendingPathComponent(\"gfp-group\", isDirectory: true); "
    "try? FileManager.default.createDirectory(at: ayuUrl, withIntermediateDirectories: true, attributes: nil); "
    "return ayuUrl }()"
)
if "group-fallback" in disabled:
    print("SKIP group-fallback: disabled")
else:
    rx = re.compile(r"\b(let|var)\s+maybeAppGroupUrl(?:\s*:\s*URL\?)?\s*=\s*FileManager\.default\.containerURL\(forSecurityApplicationGroupIdentifier:\s*([^)\n]*)\)")
    n = 0
    for base in (os.path.join(root, "submodules"), app_dir):
        for p in walk(base):
            try:
                src = read(p)
            except Exception:
                continue
            new, c = rx.subn(lambda m: "%s maybeAppGroupUrl: URL? = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: %s) ?? %s" % (m.group(1), m.group(2), GROUP_FALLBACK), src)
            if c:
                write(p, new); n += c
                print(f"OK   group-fallback: {c} in {os.path.relpath(p, root)}")
    hits_by_label["group-fallback"] = n
    if n == 0:
        print("MISSING group-fallback")


# ======================= Меню GFPGRAM, маркеры, иконки, значки =======================
ui_core = os.path.join(root, "submodules")
shutil.copy(os.path.join(here, "GfpramSettingsController.swift"),
            os.path.join(root, "submodules/SettingsUI/Sources/GfpramSettingsController.swift"))
shutil.copy(os.path.join(here, "GfpramPremiumController.swift"),
            os.path.join(root, "submodules/SettingsUI/Sources/GfpramPremiumController.swift"))
print("OK   GfpramSettingsController.swift + GfpramPremiumController.swift added")

# SettingsUI: зависимость PromptUI (поле ввода кода)
patch_plain("gfp-menu-dep", os.path.join(root, "submodules/SettingsUI/BUILD"),
      r'(        "//submodules/OverlayStatusController:OverlayStatusController",\n)',
      r'\1        "//submodules/PromptUI:PromptUI",\n')

PEER_INFO = os.path.join(root, "submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen")
# пункт «GFPGRAM» в Настройках
patch("gfp-menu-enum",
      r"(enum PeerInfoSettingsSection \{\n)",
      r"\1    case gfpram\n    case gfpramSupport\n",
      base=PEER_INFO, filename="PeerInfoScreen.swift")
patch("gfp-menu-action",
      r"(        case \.appearance:\n            push\(themeSettingsController\(context: self\.context\)\)\n)",
      r"        case .gfpram:\n            push(gfpramSettingsController(context: self.context))\n        case .gfpramSupport:\n            gfpramOpenSupport(context: self.context)\n\1",
      base=PEER_INFO, filename="PeerInfoScreenSettingsActions.swift")
patch("gfp-menu-item",
      r"(    items\[\.advanced\]!\.append\(PeerInfoScreenDisclosureItem\(id: 0, label: notificationsWarning)",
      r'    items[.advanced]!.append(PeerInfoScreenDisclosureItem(id: 50, label: .text(AyuSettings.ghostMaster ? "👻" : ""), text: "GFPGRAM", icon: gfpramHashIcon(), action: {\n'
      r'        interaction.openSettings(.gfpram)\n'
      r'    }))\n'
      r'    items[.advanced]!.append(PeerInfoScreenDisclosureItem(id: 53, label: .text("@gfpgram_support"), text: "Тех-поддержка", icon: nil, action: {\n'
      r'        interaction.openSettings(.gfpramSupport)\n'
      r'    }))\n\1',
      base=PEER_INFO, filename="PeerInfoSettingsItems.swift")

# кнопка 👻 в шапке списка чатов
patch("gfp-ghost-button",
      r"(        if let proxyButton = self\.proxyButton \{\n            result\.append\(proxyButton\)\n        \}\n)(        return result)",
      r'\1        if case .chatList(.root) = self.location {\n'
      r'            result.append(AnyComponentWithIdentity(id: "gfpghost", component: AnyComponent(NavigationButtonComponent(\n'
      r'                content: .text(title: AyuSettings.ghostMaster ? "👻" : "🙂", isBold: false),\n'
      r'                pressed: { [weak self] _ in\n'
      r'                    AyuSettings.setGhostMaster(!AyuSettings.ghostMaster)\n'
      r'                    self?.parentController?.requestLayout(transition: .immediate)\n'
      r'                }\n'
      r'            ))))\n'
      r'        }\n\2',
      base=os.path.join(root, "submodules/ChatListUI"), filename="ChatListController.swift")

# удалённый чат: 🗑 + серый цвет в списке чатов
patch("gfp-deleted-chat",
      r"(            if let titleAttributedStringValue = titleAttributedString, titleAttributedStringValue\.length == 0 \{)",
      r'            if let ayuTitle = titleAttributedString, let ayuLast = messages.last, AyuDeleted.contains(ayuLast.id) {\n'
      r'                titleAttributedString = NSAttributedString(string: "🗑 " + ayuTitle.string, font: titleFont, textColor: theme.titleColor.withMultipliedAlpha(0.5))\n'
      r'            }\n\1',
      base=os.path.join(root, "submodules/ChatListUI"), filename="ChatListItem.swift")

# маркеры 🗑 / ✏️ рядом со временем сообщения
patch("gfp-deleted-bubble",
      r"public func stringForMessageTimestampStatus\(\n",
      r'public func stringForMessageTimestampStatus(\n'
      r'    context: AccountContext,\n'
      r'    message: EngineMessage,\n'
      r'    dateTimeFormat: PresentationDateTimeFormat,\n'
      r'    nameDisplayOrder: PresentationPersonNameOrder,\n'
      r'    strings: PresentationStrings,\n'
      r'    format: MessageTimestampStatusFormat = .regular,\n'
      r'    associatedData: ChatMessageItemAssociatedData,\n'
      r'    ignoreAuthor: Bool = false\n'
      r') -> String {\n'
      r'    let ayuBase = ayuBaseStringForMessageTimestampStatus(context: context, message: message, dateTimeFormat: dateTimeFormat, nameDisplayOrder: nameDisplayOrder, strings: strings, format: format, associatedData: associatedData, ignoreAuthor: ignoreAuthor)\n'
      r'    if AyuDeleted.contains(message.id) {\n'
      r'        return "🗑 " + ayuBase\n'
      r'    }\n'
      r'    if !AyuEditHistory.history(id: message.id).isEmpty {\n'
      r'        return "✏️ " + ayuBase\n'
      r'    }\n'
      r'    return ayuBase\n'
      r'}\n\n'
      r'private func ayuBaseStringForMessageTimestampStatus(\n',
      base=os.path.join(root, "submodules/TelegramUI/Components/Chat/ChatMessageDateAndStatusNode"), filename="StringForMessageTimestampStatus.swift")

# локальный значок «#» рядом с именем
patch("gfp-badges",
      r"(    func displayTitle\(strings: PresentationStrings, displayOrder: PresentationPersonNameOrder\) -> String \{\n)(        switch self \{)",
      r'\1        return AyuBadges.decorate(id: self.id.id._internalGetInt64Value(), title: self.ayuBaseDisplayTitle(strings: strings, displayOrder: displayOrder))\n'
      r'    }\n\n'
      r'    private func ayuBaseDisplayTitle(strings: PresentationStrings, displayOrder: PresentationPersonNameOrder) -> String {\n\2',
      base=os.path.join(root, "submodules/LocalizedPeerData"), filename="PeerTitle.swift")

# обход запрета пересылки/копирования на уровне чата/канала
patch("bypass-peer",
      r"(    var isCopyProtectionEnabled: Bool \{\n)(        switch self \{)",
      r"\1        if AyuSettings.allowCopy { return false }\n\2",
      filename="PeerUtils.swift")


# ======================= Новое в 1.1 =======================
TUI = os.path.join(root, "submodules/TelegramUI")

# Пересылка из закрытых чатов -> копия обычным сообщением (сервер не принимает forwardMessages)
patch("forward-copy",
      r"(func enqueueMessages\(transaction: Transaction, [^{]*?)messages: (\[\(Bool, EnqueueMessage\)\])([^{]*?\)\s*->\s*\[MessageId\?\]\s*\{)",
      r"\1messages ayuRawMessages: \2\3\n    let messages = AyuForward.transform(transaction: transaction, messages: ayuRawMessages)",
      filename="EnqueueMessage.swift")

# До 10 аккаунтов (лимит стоит в клиенте)
if "more-accounts" in disabled:
    print("SKIP more-accounts: disabled")
else:
    n = 0
    rx_acc = re.compile(r"\b(maximumAvailableAccounts(?:\s*:\s*Int)?\s*=\s*)([34])\b")
    rx_acc2 = re.compile(r"\b((?:let|var)\s+maximumNumberOfAccounts(?:\s*:\s*Int)?\s*=\s*)([34])\b")
    for base in (os.path.join(root, "submodules"), app_dir):
        for pth in walk(base):
            try:
                src = read(pth)
            except Exception:
                continue
            if "maximum" not in src:
                continue
            new, c1 = rx_acc.subn(lambda m: m.group(1) + "(AyuSettings.moreAccounts ? 10 : " + m.group(2) + ")", src)
            new, c2 = rx_acc2.subn(lambda m: m.group(1) + "(AyuSettings.moreAccounts ? 10 : " + m.group(2) + ")", new)
            if c1 + c2:
                write(pth, new); n += c1 + c2
                print(f"OK   more-accounts: {c1 + c2} in {os.path.relpath(pth, root)}")
    hits_by_label["more-accounts"] = n
    if n == 0:
        print("MISSING more-accounts: anchor not found")

# Меню сообщения: «Показать оригинал» (история правок), «ID сообщения», «Выдать значок #»
CTX_MENU = (
    "\n        if let ayuMessage = messages.first {\n"
    "            let ayuHistory = AyuEditHistory.history(id: ayuMessage.id)\n"
    "            if !ayuHistory.isEmpty {\n"
    "                actions.append(.action(ContextMenuActionItem(text: \"Показать оригинал\", icon: { _ in return nil }, action: { _, f in\n"
    "                    f(.default)\n"
    "                    var ayuText = \"\"\n"
    "                    for (ayuIndex, ayuItem) in ayuHistory.enumerated() {\n"
    "                        ayuText += (ayuIndex == 0 ? \"Оригинал:\\n\" : \"Версия \\(ayuIndex):\\n\") + ayuItem + \"\\n\\n\"\n"
    "                    }\n"
    "                    controllerInteraction?.presentController(textAlertController(context: context, title: \"Сообщение изменено\", text: ayuText, actions: [TextAlertAction(type: .defaultAction, title: \"OK\", action: {})]), nil)\n"
    "                })))\n"
    "            }\n"
    "            if AyuSettings.showIds {\n"
    "                actions.append(.action(ContextMenuActionItem(text: \"ID сообщения: \\(ayuMessage.id.id)\", icon: { _ in return nil }, action: { _, f in\n"
    "                    f(.default)\n"
    "                    UIPasteboard.general.string = \"\\(ayuMessage.id.id)\"\n"
    "                })))\n"
    "            }\n"
    "            if AyuSettings.adminUnlocked {\n"
    "                var ayuTargetId = ayuMessage.author?.id ?? ayuMessage.id.peerId\n"
    "                if let ayuChannel = ayuMessage.peers[ayuMessage.id.peerId] as? TelegramChannel, case .broadcast = ayuChannel.info {\n"
    "                    ayuTargetId = ayuChannel.id\n"
    "                }\n"
    "                let ayuTarget = ayuTargetId.id._internalGetInt64Value()\n"
    "                let ayuHas = AyuBadges.contains(ayuTarget)\n"
    "                let ayuTitle = ayuMessage.peers[ayuTargetId]?.debugDisplayTitle ?? \"ID \\(ayuTarget)\"\n"
    "                actions.append(.action(ContextMenuActionItem(text: ayuHas ? \"Убрать значок #\" : \"Выдать значок #\", icon: { _ in return nil }, action: { _, f in\n"
    "                    f(.default)\n"
    "                    if ayuHas {\n"
    "                        AyuBadges.remove(id: ayuTarget)\n"
    "                    } else {\n"
    "                        AyuBadges.add(id: ayuTarget, name: ayuTitle)\n"
    "                    }\n"
    "                })))\n"
    "            }\n"
    "        }\n"
)
patch("gfp-context-menu",
      r"(func contextMenuForChatPresentationInterfaceState\(.*?\n\s*var actions: \[ContextMenuItem\] = \[\]\n)",
      lambda m: m.group(1) + CTX_MENU,
      base=TUI, filename="ChatInterfaceStateContextMenus.swift")

# ID и страна под аккаунтом в Настройках (перед строкой GFPGRAM)
ACC_ROWS = (
    "    items[.advanced]!.append(PeerInfoScreenDisclosureItem(id: 51, label: .text(String(context.account.peerId.id._internalGetInt64Value())), text: \"ID\", icon: nil, action: {\n"
    "        UIPasteboard.general.string = String(context.account.peerId.id._internalGetInt64Value())\n"
    "    }))\n"
    "    items[.advanced]!.append(PeerInfoScreenDisclosureItem(id: 52, label: .text(AyuProfile.country(phone: ((data as PeerInfoScreenData?)?.peer as? TelegramUser)?.phone) ?? \"не определена\"), text: \"Страна номера\", icon: nil, action: {\n"
    "    }))\n"
    "    items[.advanced]!.append(PeerInfoScreenDisclosureItem(id: 54, label: .text((((data as PeerInfoScreenData?)?.peer as? TelegramUser)?.username).map { \"@\" + $0 } ?? \"не задан\"), text: \"Юзер\", icon: nil, action: {\n"
    "        if let ayuName = (((data as PeerInfoScreenData?)?.peer as? TelegramUser)?.username) { UIPasteboard.general.string = \"@\" + ayuName }\n"
    "    }))\n"
)
patch("gfp-account-info",
      r"(    items\[\.advanced\]!\.append\(PeerInfoScreenDisclosureItem\(id: 50, label: \.text\(AyuSettings\.ghostMaster)",
      lambda m: ACC_ROWS + m.group(1),
      base=PEER_INFO, filename="PeerInfoSettingsItems.swift")

# сменные иконки: основная (заменяется выше), красная, чёрная, аниме, океан, Губка Боб. Остальные стандартные убираем.
GFP_ICONS = [("GfpRed", "red.jpg"), ("GfpBlack", "black.jpg"), ("GfpAnime", "anime.jpg"), ("GfpOcean", "ocean.jpg"), ("GfpSponge", "sponge.jpg")]
try:
    from PIL import Image as _Image
    sizes = {"{n}@2x.png": 120, "{n}@3x.png": 180, "{n}Ipad.png": 76, "{n}Ipad@2x.png": 152, "{n}LargeIpad@2x.png": 167,
             "{n}NotificationIcon.png": 20, "{n}NotificationIcon@2x.png": 40, "{n}NotificationIcon@3x.png": 60}
    made = 0
    for name, fn in GFP_ICONS:
        img = _Image.open(os.path.join(here, "..", "assets", "icons", fn)).convert("RGB")
        d = os.path.join(app_dir, name + ".alticon")
        os.makedirs(d, exist_ok=True)
        for pat, px in sizes.items():
            img.resize((px, px), _Image.LANCZOS).save(os.path.join(d, pat.format(n=name)))
            made += 1
    hits_by_label["gfp-icons-files"] = made
    print(f"OK   gfp-icons-files: {made} png")
except Exception as e:
    print(f"MISSING gfp-icons-files: {e}")

def _keep_primary(lines_text):
    """Из старого списка оставляем только основную иконку BlueIcon (она уже перекрашена в твою)."""
    keep = [l.rstrip() for l in lines_text.split("\n") if '"BlueIcon"' in l]
    return [l if l.endswith(",") else l + "," for l in keep]

# Telegram/BUILD: список папок альтернативных иконок
if "gfp-icons-build" in disabled:
    print("SKIP gfp-icons-build: disabled")
else:
    bp = os.path.join(root, "Telegram/BUILD")
    n = 0
    if os.path.exists(bp):
        src = read(bp)
        def _build_list(m):
            keep = _keep_primary(m.group(2))
            body = "\n".join(keep + ['    "%s",' % x for x, _ in GFP_ICONS])
            return m.group(1) + "\n" + body + "\n" + m.group(3)
        new, n = re.subn(r"(alternate_icon_folders = \[)([^\]]*)(\])", _build_list, src, count=1)
        if n:
            write(bp, new)
    hits_by_label["gfp-icons-build"] = n
    print("OK   gfp-icons-build: список иконок заменён" if n else "MISSING gfp-icons-build")

# Список иконок в выборе (Настройки -> GFPGRAM -> Иконка приложения)
if "gfp-icons-list" in disabled:
    print("SKIP gfp-icons-list: disabled")
else:
    n = 0
    for pth in walk(os.path.join(root, "submodules/TelegramUI/Sources")):
        if os.path.basename(pth) != "AppDelegate.swift":
            continue
        src = read(pth)
        def _swift_list(m):
            keep = _keep_primary(m.group(2))
            mine = ['        PresentationAppIcon(name: "%s", imageName: "%s"),' % (x, x) for x, _ in GFP_ICONS]
            return m.group(1) + "\n" + "\n".join(keep + mine) + "\n" + m.group(3)
        new, c = re.subn(r"(var icons = \[)(.*?)(\n\s*\])", _swift_list, src, count=1, flags=re.S)
        if c:
            write(pth, new); n += c
            print(f"OK   gfp-icons-list: {c} in {os.path.relpath(pth, root)}")
    hits_by_label["gfp-icons-list"] = n
    if n == 0:
        print("MISSING gfp-icons-list")

# Плашка «# Официальный аккаунт клиента GFPGRAM» в профиле (у аккаунтов со значком «#» и у @gfpgram_support)
if "gfp-verified" in disabled:
    print("SKIP gfp-verified: disabled")
else:
    n = 0
    for pth in walk(os.path.join(root, "submodules/TelegramUI")):
        if os.path.basename(pth) != "PeerInfoScreen.swift":
            continue
        src = read(pth)
        new_src, c = re.subn(r"^(\s*)(if let user = data\.peer as\? TelegramUser \{)\s*$",
                             r"\1\2\n\1    if let ayuVerified = AyuVerified.text(id: user.id.id._internalGetInt64Value(), username: user.username) {\n"
                             r'\1        items[.peerInfo, default: []].append(PeerInfoScreenLabeledValueItem(id: 9002, label: "#", text: ayuVerified, textColor: .primary, action: nil, longTapAction: nil, requestLayout: { _ in }))\n'
                             r"\1    }",
                             src, count=1, flags=re.M)
        if c:
            write(pth, new_src); n += c
            print(f"OK   gfp-verified: {c} in {os.path.relpath(pth, root)}")
    hits_by_label["gfp-verified"] = n
    if n == 0:
        print("MISSING gfp-verified: anchor not found")

# Фоновые функции Premium (заглушка при упоминании, бэкап): запускаются при открытии списка чатов
patch("gfp-premium-start",
      r"(    override public func loadDisplayNode\(\) \{\n)",
      r"\1        AyuPremiumService.start(account: self.context.account)\n",
      base=os.path.join(root, "submodules/ChatListUI"), filename="ChatListController.swift")

# ======================= Итог =======================
bad = [l for l in CRITICAL if l not in disabled and hits_by_label.get(l, 0) == 0]
for l in ("ghost-read", "ghost-typing", "ghost-online", "ghost-stories", "keep-deleted", "edit-history", "hide-ads", "ghost-consume", "keep-selfdestruct", "forward-copy", "more-accounts", "gfp-context-menu", "gfp-account-info", "gfp-premium-start", "gfp-verified"):
    if l not in disabled and hits_by_label.get(l, 0) == 0:
        print(f"::warning::патч {l} не применился (якорь не найден) — функция работать не будет")
if bad:
    print(f"::error::Критичные патчи не применились: {', '.join(bad)}. Сборка остановлена.")
    sys.exit(1)
print("ALL CRITICAL PATCHES OK")
