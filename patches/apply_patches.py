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
CRITICAL = ["branding-name", "branding-icon", "group-fallback", "gfp-menu-enum", "gfp-menu-action", "gfp-menu-item", "gfp-menu-dep", "gfp-ghost-button", "gfp-deleted-chat", "gfp-deleted-bubble", "gfp-badges", "gfp-icons-build", "gfp-icons-list", "bypass-peer", "gfp-support-item", "gfp-profile-id"]
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
shutil.copy(os.path.join(here, "AyuIconKeeper.swift"), os.path.join(core, "AyuIconKeeper.swift"))
print("OK   Ayu*.swift added (+AyuIconKeeper)")

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
      r"(case let \.EditMessage\(id, ([A-Za-z][A-Za-z0-9_]*)\):\n)",
      r"\1                if let ayuPrev = transaction.getMessage(id), ayuPrev.text != \2.text { AyuEditHistory.record(id: id, text: ayuPrev.text) }\n",
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
for _extra in ("GfpramPremiumUI.swift", "GfpramAssets.swift", "GfpramIcons.swift", "GfpramIconImages.swift", "GfpramEditHistory.swift", "GfpramTriggers.swift", "GfpramFont.swift"):
    shutil.copy(os.path.join(here, _extra), os.path.join(root, "submodules/SettingsUI/Sources/" + _extra))
print("OK   GfpramSettingsController/PremiumController/PremiumUI/Assets/Icons/IconImages/EditHistory/Triggers/Font added")

# Автоподстройка GfpramPremiumUI.swift под реальный API Display из этого чекаута
def _adapt_premium_ui():
    target = os.path.join(root, "submodules/SettingsUI/Sources/GfpramPremiumUI.swift")
    src = read(target)
    node_sig = None
    proto = None
    for _p in walk(os.path.join(root, "submodules/Display/Source")):
        t = read(_p)
        if node_sig is None and re.search(r"class\s+ListViewItemNode\b", t):
            m = re.search(r"\binit\s*\(\s*layerBacked[^)]*\)", t)
            if m:
                node_sig = m.group(0)
        if proto is None and re.search(r"protocol\s+ListViewItem\b", t):
            i = t.find("protocol ListViewItem")
            proto = t[i:i + 4000]
        if node_sig and proto:
            break
    if node_sig:
        print("INFO ListViewItemNode: " + re.sub(r"\s+", " ", node_sig))
        if "dynamicBounce" not in node_sig:
            src = src.replace("super.init(layerBacked: false, dynamicBounce: false)", "super.init(layerBacked: false)")
            print("OK   gfp-premiumui: dynamicBounce убран (в этом Telegram-iOS такого аргумента нет)")
    else:
        print("::warning::gfp-premiumui: не нашёл init ListViewItemNode, оставляю как есть")
    if proto:
        # Диагностика: реальные требования протокола — видно в логе, если снова не сойдётся
        for _line in proto.split("\n"):
            _t = _line.strip()
            if _t.startswith("}") and not _t.startswith("})"):
                break
            if _t.startswith(("func ", "var ", "static ", "associatedtype ", "init")):
                print("INFO ListViewItem: " + _t[:260])
    write(target, src)
_adapt_premium_ui()

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
      r'\1',
      base=PEER_INFO, filename="PeerInfoSettingsItems.swift")

# gfpramHashIcon()/gfpramSettingsController живут в модуле SettingsUI — в этих файлах его может не быть в импортах
for _fn in ("PeerInfoSettingsItems.swift", "PeerInfoScreenSettingsActions.swift", "PeerInfoScreen.swift"):
    for _p in walk(PEER_INFO):
        if os.path.basename(_p) != _fn:
            continue
        _src = read(_p)
        if "gfpram" in _src and not re.search(r"^import SettingsUI\s*$", _src, flags=re.M):
            write(_p, re.sub(r"^(import Foundation\n)", r"\1import SettingsUI\n", _src, count=1, flags=re.M)
                  if re.search(r"^import Foundation\n", _src, flags=re.M) else "import SettingsUI\n" + _src)
            print(f"OK   gfp-import-settingsui: {os.path.relpath(_p, root)}")

# «Тех-поддержка» — в самом низу Настроек (после «Советы Telegram»)
patch("gfp-support-item",
      r"(    items\[\.support\]!\.append\(PeerInfoScreenDisclosureItem\(id: 2, text: presentationData\.strings\.Settings_Tips, icon: PresentationResourcesSettings\.tips, action: \{\n        interaction\.openSettings\(\.tips\)\n    \}\)\)\n)",
      lambda m: m.group(1)
      + '    items[.support]!.append(PeerInfoScreenDisclosureItem(id: 3, label: .text(""), text: "Тех-поддержка", icon: gfpramFeatureIcon(101), action: {\n'
      + '        interaction.openSettings(.gfpramSupport)\n'
      + '    }))\n',
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
      r'    if AyuEditHistory.isEdited(id: message.id, text: message.text) {\n'
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
CTX_MENU = r"""
        if let ayuMessage = messages.first {
            if AyuEditHistory.isEdited(id: ayuMessage.id, text: ayuMessage.text) {
                actions.append(.action(ContextMenuActionItem(text: "Показать оригинал", icon: { _ in return nil }, action: { _, f in
                    f(.default)
                    var ayuEditDate: Int32? = nil
                    for ayuAttribute in ayuMessage.attributes {
                        if let ayuEdited = ayuAttribute as? EditedMessageAttribute {
                            ayuEditDate = ayuEdited.date
                        }
                    }
                    let ayuController = gfpramEditHistoryController(context: context, messageText: ayuMessage.text, editDate: ayuEditDate, entries: AyuEditHistory.entries(id: ayuMessage.id))
                    controllerInteraction.navigationController()?.pushViewController(ayuController)
                })))
            }
            if AyuSettings.showIds {
                actions.append(.action(ContextMenuActionItem(text: "ID сообщения: \(ayuMessage.id.id)", icon: { _ in return nil }, action: { _, f in
                    f(.default)
                    UIPasteboard.general.string = "\(ayuMessage.id.id)"
                })))
            }
            if AyuSettings.adminUnlocked {
                var ayuTargetId = ayuMessage.author?.id ?? ayuMessage.id.peerId
                if let ayuChannel = ayuMessage.peers[ayuMessage.id.peerId] as? TelegramChannel, case .broadcast = ayuChannel.info {
                    ayuTargetId = ayuChannel.id
                }
                let ayuTarget = ayuTargetId.id._internalGetInt64Value()
                let ayuHas = AyuBadges.contains(ayuTarget)
                let ayuTitle = ayuMessage.peers[ayuTargetId]?.debugDisplayTitle ?? "ID \(ayuTarget)"
                actions.append(.action(ContextMenuActionItem(text: ayuHas ? "Убрать значок #" : "Выдать значок #", icon: { _ in return nil }, action: { _, f in
                    f(.default)
                    if ayuHas {
                        AyuBadges.remove(id: ayuTarget)
                    } else {
                        AyuBadges.add(id: ayuTarget, name: ayuTitle)
                    }
                })))
            }
        }
"""
patch("gfp-context-menu",
      r"(        let isPremium = accountPeer\?\.isPremium \?\? false\n\n        var actions: \[ContextMenuItem\] = \[\]\n)",
      lambda m: m.group(1) + CTX_MENU,
      base=TUI, filename="ChatInterfaceStateContextMenus.swift")

# окно «История изменений» живёт в SettingsUI: подключаем модуль в файле контекстного меню
if "gfp-context-menu" not in disabled:
    for _p in walk(TUI):
        if os.path.basename(_p) != "ChatInterfaceStateContextMenus.swift":
            continue
        _src = read(_p)
        if "gfpramEditHistoryController" in _src and not re.search(r"^import SettingsUI\s*$", _src, flags=re.M):
            write(_p, "import SettingsUI\n" + _src)
            print(f"OK   gfp-import-settingsui: {os.path.relpath(_p, root)}")

# сменные иконки: основная (заменяется выше), красная, чёрная, аниме, океан, Губка Боб. Остальные стандартные убираем.
GFP_FREE_ICONS = [("GfpRed", "red.jpg"), ("GfpBlack", "black.jpg"), ("GfpAnime", "anime.jpg"), ("GfpOcean", "ocean.jpg"), ("GfpSponge", "sponge.jpg")]
# Premium-иконки: попадают в сборку (BUILD), но в стандартный список Telegram не выводятся, их показывает окно GFPGRAM с замком
GFP_PREMIUM_ICONS = [("GfpGold", "gold.jpg"), ("GfpTurbo", "turbo.jpg"), ("GfpNight", "night.jpg"), ("GfpDuck", "duck.jpg")]
GFP_ICONS = GFP_FREE_ICONS + GFP_PREMIUM_ICONS
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
            mine = ['        PresentationAppIcon(name: "%s", imageName: "%s"),' % (x, x) for x, _ in GFP_FREE_ICONS]
            return m.group(1) + "\n" + "\n".join(keep + mine) + "\n" + m.group(3)
        new, c = re.subn(r"(var icons = \[)(.*?)(\n\s*\])", _swift_list, src, count=1, flags=re.S)
        if c:
            write(pth, new); n += c
            print(f"OK   gfp-icons-list: {c} in {os.path.relpath(pth, root)}")
    hits_by_label["gfp-icons-list"] = n
    if n == 0:
        print("MISSING gfp-icons-list")

# Профиль: «ID» и «страна номера» под именем пользователя (описание значка — отдельный патч gfp-profile-verified ниже)
PROFILE_ITEMS = (
    '        items[currentPeerInfoSection]!.append(PeerInfoScreenLabeledValueItem(id: 3100, label: "ID", text: String(user.id.id._internalGetInt64Value()), textColor: .primary, action: { _, _ in\n'
    '            UIPasteboard.general.string = String(user.id.id._internalGetInt64Value())\n'
    '        }, requestLayout: { _ in }))\n'
    '        if let ayuCountry = AyuProfile.country(phone: user.phone) {\n'
    '            items[currentPeerInfoSection]!.append(PeerInfoScreenLabeledValueItem(id: 3101, label: "страна номера", text: ayuCountry, textColor: .primary, action: nil, requestLayout: { _ in }))\n'
    '        }\n'
)
patch("gfp-profile-id",
      r"(\n)(        if let cachedData = data\.cachedData as\? CachedUserData \{\n            if let birthday = cachedData\.birthday \{)",
      lambda m: m.group(1) + PROFILE_ITEMS + "\n" + m.group(2),
      base=PEER_INFO, filename="PeerInfoProfileItems.swift")

# Описание значка под карточкой профиля — как «This bot was verified by ...» у Major.
# Берём штатную строку-комментарий PeerInfoScreenCommentItem. Если её init в этой сборке Telegram-iOS не подходит
# (нет id/text или есть обязательные параметры), ставим обычную строку «GFPGRAM» внутри карточки — сборка не падает.
def _split_top(params):
    parts, depth, cur = [], 0, ""
    for ch in params:
        if ch in "([<":
            depth += 1
        elif ch in ")]>":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append(cur.strip()); cur = ""
        else:
            cur += ch
    if cur.strip():
        parts.append(cur.strip())
    return parts

def _comment_item_usable():
    for p in walk(PEER_INFO):
        if os.path.basename(p) != "PeerInfoScreenCommentItem.swift":
            continue
        src = read(p)
        cls = src.find("class PeerInfoScreenCommentItem")
        i = src.find("init(", cls if cls >= 0 else 0)
        if i < 0:
            return False
        j, depth = i + 5, 1
        while j < len(src) and depth:
            depth += {"(": 1, ")": -1}.get(src[j], 0)
            j += 1
        params = _split_top(src[i + 5:j - 1])
        if len(params) < 2 or not params[0].startswith("id:") or not params[1].startswith("text:"):
            return False
        return all("=" in x for x in params[2:])
    return False

def _insert_verified_footer():
    label = "gfp-profile-verified"
    if label in disabled:
        print(f"SKIP {label}: disabled"); return
    verified_if = '        if let ayuVerified = AyuVerified.text(id: user.id.id._internalGetInt64Value(), username: user.username) {\n'
    for p in walk(PEER_INFO):
        if os.path.basename(p) != "PeerInfoProfileItems.swift":
            continue
        src = read(p)
        anchor = src.find("        if let cachedData = data.cachedData as? CachedUserData {\n")
        if anchor < 0 or "AyuVerified" in src:
            continue
        if _comment_item_usable():
            # ищем конец блока cachedData (парные фигурные скобки), вставляем описание после него — под всей карточкой
            depth, j = 0, src.find("{", anchor)
            while j < len(src):
                if src[j] == "{": depth += 1
                elif src[j] == "}":
                    depth -= 1
                    if depth == 0: break
                j += 1
            if j < len(src):
                end = src.find("\n", j) + 1
                block = verified_if + '            items[currentPeerInfoSection]!.append(PeerInfoScreenCommentItem(id: 3102, text: ayuVerified))\n        }\n'
                write(p, src[:end] + block + src[end:])
                hits_by_label[label] = hits_by_label.get(label, 0) + 1
                print(f"OK   {label}: footer (PeerInfoScreenCommentItem) in {os.path.relpath(p, root)}")
                return
        block = verified_if + '            items[currentPeerInfoSection]!.append(PeerInfoScreenLabeledValueItem(id: 3102, label: "GFPGRAM", text: ayuVerified, textColor: .primary, action: nil, requestLayout: { _ in }))\n        }\n'
        write(p, src[:anchor] + block + src[anchor:])
        hits_by_label[label] = hits_by_label.get(label, 0) + 1
        print(f"OK   {label}: row fallback (CommentItem не подошёл) in {os.path.relpath(p, root)}")
        return
    print(f"MISSING {label}: anchor not found")
_insert_verified_footer()

# Оформление: вместо сетки иконок — кнопка «Иконка приложения» (открывает окно иконок GFPGRAM)
def _balanced_end(src, open_idx):
    """Индекс сразу после ')', парной для '(' в open_idx (строки в кавычках пропускаем)."""
    depth, i, in_str = 0, open_idx, False
    while i < len(src):
        ch = src[i]
        if in_str:
            if ch == "\\":
                i += 1
            elif ch == '"':
                in_str = False
        elif ch == '"':
            in_str = True
        elif ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return -1

def _split_top(s):
    parts, d, cur = [], 0, ""
    for ch in s:
        if ch in "([<": d += 1
        elif ch in ")]>": d -= 1
        if ch == "," and d == 0:
            parts.append(cur.strip()); cur = ""
        else:
            cur += ch
    if cur.strip(): parts.append(cur.strip())
    return parts

def _appearance_icon_button():
    label = "gfp-appearance-icons"
    if label in disabled:
        print(f"SKIP {label}: disabled"); return
    for p in walk(os.path.join(root, "submodules/SettingsUI")):
        if os.path.basename(p) != "ThemeSettingsController.swift":
            continue
        src = read(p)
        if "gfpram.open" in src:
            return
        m_item = re.search(r"return\s+ThemeSettingsAppIconItem\(", src)
        if not m_item:
            print(f"MISSING {label}: в ThemeSettingsController.swift нет 'return ThemeSettingsAppIconItem(', сетка осталась"); return
        item_end = _balanced_end(src, m_item.end() - 1)
        if item_end < 0:
            print(f"MISSING {label}: не удалось найти конец ThemeSettingsAppIconItem(...)"); return
        old_call = src[m_item.start():item_end]
        m_style = re.search(r"systemStyle:\s*([^,\n]+),", old_call)
        style_arg = ("systemStyle: " + m_style.group(1).strip() + ", ") if m_style else ""
        m_sel = re.search(r"selectAppIcon:\s*\{\s*(\w+)\s+in\b[^\n]*\n", src)
        if not m_sel:
            print(f"MISSING {label}: не найден closure 'selectAppIcon: {{ icon in', сетка осталась"); return
        push_name = None
        for m_push in re.finditer(r"var\s+(\w+)\s*:\s*\(\(ViewController\)\s*->\s*Void\)\?", src[:m_sel.start()]):
            push_name = m_push.group(1)
            if "push" in push_name.lower():
                break
        if not push_name:
            print(f"MISSING {label}: не найдена переменная push-замыкания перед selectAppIcon, сетка осталась"); return
        icon_var = m_sel.group(1)
        # привязки из `case let .icon(...)` теперь не используются -> warning=error; гасим через `_ = x`
        keep = ""
        _pre = src[:m_item.start()]
        _mc = None
        for _mc in re.finditer(r"case\s+let\s+\.\w+\(([^\n]*)\)\s*:", _pre):
            pass
        if _mc:
            for _part in _split_top(_mc.group(1)):
                if re.fullmatch(r"[A-Za-z]\w*", _part):
                    keep += "            _ = " + _part + "\n"
        button = (keep + 'return ItemListDisclosureItem(presentationData: presentationData, ' + style_arg + 'icon: nil, title: "Иконка приложения", label: "", labelStyle: .text, sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: {\n'
                  '                arguments.selectAppIcon(PresentationAppIcon(name: "gfpram.open", imageName: "gfpram.open"))\n'
                  '            })')
        hook = ('            if ' + icon_var + '.name == "gfpram.open" {\n'
                '                ' + push_name + '?(gfpramIconsController(context: context))\n'
                '                return\n'
                '            }\n')
        # правим с конца файла к началу, чтобы индексы не поехали (порядок closure и item() зависит от версии)
        edits = sorted([(m_sel.end(), m_sel.end(), hook), (m_item.start(), item_end, button)], key=lambda e: e[0], reverse=True)
        for start, end, text in edits:
            src = src[:start] + text + src[end:]
        write(p, src)
        hits_by_label[label] = hits_by_label.get(label, 0) + 1
        print(f"OK   {label}: кнопка вместо сетки в {os.path.relpath(p, root)}")
        return
    print(f"MISSING {label}: ThemeSettingsController.swift not found")
_appearance_icon_button()

# Шрифт всего интерфейса: Font.regular/medium/... в модуле Display берут выбранное семейство из AyuFont
def _font_patch():
    label = "gfp-font"
    if label in disabled:
        print(f"SKIP {label}: disabled"); return
    display_src = os.path.join(root, "submodules/Display/Source")
    for p in walk(display_src):
        if os.path.basename(p) != "Font.swift":
            continue
        src = read(p)
        if "AyuFont." in src:
            return
        shutil.copy(os.path.join(here, "AyuFont.swift"), os.path.join(display_src, "AyuFont.swift"))
        table = {"regular": (".regular", "false"), "light": (".light", "false"), "medium": (".medium", "false"),
                 "semibold": (".semibold", "false"), "bold": (".bold", "false"), "heavy": (".heavy", "false"),
                 "italic": (".regular", "true"), "semiboldItalic": (".semibold", "true")}
        total = 0
        for name, (weight, italic) in table.items():
            pat = r"(public static func " + name + r"\(_ size: CGFloat\) -> UIFont \{\n)"
            rep = r"\1        if let ayuFont = AyuFont.font(size: size, weight: " + weight + ", italic: " + italic + ") { return ayuFont }\n"
            src, n = re.subn(pat, rep, src, count=1)
            total += n
        src, n_with = re.subn(r"(public static func with\(size: CGFloat, design: Design = \.regular, weight: Weight = \.regular, traits: Traits = \[\]\) -> UIFont \{\n)",
                              r"\1        if design == .regular, traits.isEmpty, let ayuFont = AyuFont.font(size: size, weight: AyuFont.weight(String(describing: weight))) { return ayuFont }\n", src, count=1)
        total += n_with
        if total == 0:
            os.remove(os.path.join(display_src, "AyuFont.swift"))
            print(f"MISSING {label}: в Font.swift не найдены функции Font.regular/... , шрифт не меняется"); return
        write(p, src)
        hits_by_label[label] = total
        print(f"OK   {label}: {total} функций Font.* в {os.path.relpath(p, root)} (with: {n_with})")
        return
    print(f"MISSING {label}: Font.swift not found")
_font_patch()

# Фоновые функции Premium (заглушка при упоминании, бэкап): запускаются при открытии списка чатов
patch("gfp-premium-start",
      r"(    override public func loadDisplayNode\(\) \{\n)",
      r"\1        AyuPremiumService.start(account: self.context.account)\n",
      base=os.path.join(root, "submodules/ChatListUI"), filename="ChatListController.swift")

# ======================= Облачная копия Premium/иконки и массовое добавление подарков =======================
# Оба блока зависят от внутреннего API Telegram-iOS, который меняется. Поэтому перед копированием настоящих файлов
# проверяем, что нужные типы и методы есть в чекауте; если нет — ставим заглушку (сборка не падает), причина идёт в лог.
def _all_core_sources():
    for p in walk(os.path.join(root, "submodules/TelegramCore")):
        try:
            yield p, read(p)
        except Exception:
            continue

def _balanced_params(src, name):
    """Находит func name(...) и возвращает (список параметров, хвост после ')'), по всем совпадениям."""
    for m in re.finditer(r"func\s+" + name + r"\(", src):
        i, d = m.end(), 1
        while i < len(src) and d:
            d += (src[i] == "(") - (src[i] == ")")
            i += 1
        params = src[m.end():i - 1]
        tail = src[i:i + 200]
        yield _split_top(params), tail

def _split_top(s):
    parts, d, cur = [], 0, ""
    for ch in s:
        if ch in "([<": d += 1
        elif ch in ")]>": d -= 1
        if ch == "," and d == 0:
            parts.append(cur.strip()); cur = ""
        else:
            cur += ch
    if cur.strip(): parts.append(cur.strip())
    return parts

def check_gifts():
    """Проверяет API профильных подарков и папок. Возвращает список причин провала (пусто = всё ок)."""
    ctx_src = col_src = ""
    all_src = ""
    for p, src in _all_core_sources():
        all_src += src
        if re.search(r"class\s+ProfileGiftsContext\b", src) and not ctx_src:
            ctx_src = src
        if re.search(r"class\s+ProfileGiftsCollectionsContext\b", src) and not col_src:
            col_src = src
    why = []
    if not ctx_src:
        why.append("нет класса ProfileGiftsContext")
    else:
        ok_init = False
        for m in re.finditer(r"init\(\s*account:\s*Account,\s*peerId:\s*(?:EnginePeer\.Id|PeerId)((?:[^()]|\([^()]*\))*)\)", ctx_src):
            rest = _split_top(m.group(1).lstrip(", \n"))
            if all("=" in x for x in rest if x):
                ok_init = True
        if not ok_init: why.append("ProfileGiftsContext.init(account:peerId:...) не совпал")
        if not re.search(r"var\s+state:\s*Signal<(?:ProfileGiftsContext\.)?State,\s*NoError>", ctx_src): why.append("ProfileGiftsContext.state не Signal<State, NoError>")
        if not re.search(r"func\s+loadMore\(", ctx_src): why.append("нет ProfileGiftsContext.loadMore()")
        if not re.search(r"(let|var)\s+gifts:\s*\[StarGift\]", ctx_src): why.append("нет State.gifts: [StarGift]")
        if not re.search(r"(let|var)\s+fromPeer:\s*EnginePeer\?", ctx_src): why.append("нет StarGift.fromPeer: EnginePeer?")
        if not re.search(r"case\s+ready\(canLoadMore:\s*Bool,\s*nextOffset:", ctx_src): why.append("DataState.ready(canLoadMore:nextOffset:) другой формы")
    if not col_src:
        why.append("нет класса ProfileGiftsCollectionsContext")
    else:
        if not re.search(r"init\(\s*account:\s*Account,\s*peerId:\s*(?:EnginePeer\.Id|PeerId)\s*\)", col_src): why.append("ProfileGiftsCollectionsContext.init(account:peerId:) не совпал")
        if not re.search(r"var\s+state:\s*Signal<(?:ProfileGiftsCollectionsContext\.)?State,\s*NoError>", col_src): why.append("ProfileGiftsCollectionsContext.state не Signal<State, NoError>")
        if not re.search(r"(let|var)\s+collections:\s*\[StarGiftCollection\]", col_src): why.append("нет State.collections: [StarGiftCollection]")
        if not re.search(r"func\s+addGifts\(\s*collectionId:\s*Int32,\s*gifts:\s*\[ProfileGiftsContext\.State\.StarGift\]\s*\)\s*->\s*Signal", col_src): why.append("нет addGifts(collectionId: Int32, gifts: [ProfileGiftsContext.State.StarGift]) -> Signal")
    if not re.search(r"struct\s+StarGiftCollection\b", all_src) or not re.search(r"struct\s+StarGiftCollection\b.*?(let|var)\s+id:\s*Int32.*?(let|var)\s+title:\s*String", all_src, re.S):
        why.append("у StarGiftCollection нет id: Int32 / title: String")
    return why

_gift_target = os.path.join(root, "submodules/SettingsUI/Sources/GfpramGifts.swift")
if "gfp-gifts" in disabled:
    print("SKIP gfp-gifts: disabled (ставлю заглушку)")
    shutil.copy(os.path.join(here, "GfpramGiftsStub.swift"), _gift_target)
else:
    _gwhy = check_gifts()
    if not _gwhy:
        shutil.copy(os.path.join(here, "GfpramGifts.swift"), _gift_target)
        print("OK   gfp-gifts: массовое добавление подарков в коллекцию")
    else:
        shutil.copy(os.path.join(here, "GfpramGiftsStub.swift"), _gift_target)
        print("::warning::gfp-gifts: массовое добавление подарков отключено (заглушка): " + "; ".join(_gwhy))
        # Диагностика: настоящие сигнатуры API коллекций подарков из этого Telegram-iOS — по ним подгоняется GfpramGifts.swift
        for _p, _src in _all_core_sources():
            if re.search(r"class\s+ProfileGiftsCollectionsContext\b", _src):
                print("INFO gifts-api file: " + os.path.relpath(_p, root))
                _i = _src.find("class ProfileGiftsCollectionsContext")
                for _line in _src[_i:].split("\n"):
                    _t = _line.strip()
                    if re.match(r"(public |private |fileprivate )?(init\(|func |var |let |final class |struct |enum |case )", _t) and not _t.startswith("private"):
                        print("INFO gifts-api: " + _t[:220])
                    if _line.startswith("}"):
                        break
                break

# ---------- Автоподстройка под актуальный API Telegram-iOS ----------
# API Telegram меняется (EngineOutgoingMessageContent.text получил доп. аргументы и т.п.).
# Читаем реальное определение из чекаута и подгоняем наши вызовы `content: .text(...)`.
def _split_top(s):
    parts, d, cur = [], 0, ""
    for ch in s:
        if ch in "([<": d += 1
        elif ch in ")]>": d -= 1
        if ch == "," and d == 0:
            parts.append(cur.strip()); cur = ""
        else:
            cur += ch
    if cur.strip(): parts.append(cur.strip())
    return parts

def _default_for(t):
    t = t.strip()
    if t.startswith("["): return "[]"
    if t.endswith("?"): return "nil"
    return None

def adapt_text_content():
    case_line, defn = None, None
    for p in walk(os.path.join(root, "submodules/TelegramCore")):
        try: src = read(p)
        except Exception: continue
        m = re.search(r"enum\s+EngineOutgoingMessageContent\b.*?\{(.*?)^\s*\}", src, re.S | re.M)
        if m:
            defn = os.path.relpath(p, root)
            c = re.search(r"^\s*case\s+text\((.*)\)\s*$", m.group(1), re.M)
            if c: case_line = c.group(1)
            break
    print(f"INFO EngineOutgoingMessageContent: {defn}; case text({case_line})")
    if case_line is None:
        print("::warning::не нашёл case text(...) в EngineOutgoingMessageContent — вызовы .text(...) не трогаю"); return
    payload = _split_top(case_line)
    if len(payload) <= 1:
        print("OK   .text(...) — один аргумент, подгонять не нужно"); return
    extra = []
    for item in payload[1:]:
        if ":" in item and not item.strip().startswith("["):
            label, typ = [x.strip() for x in item.split(":", 1)]
            d = _default_for(typ)
            if d is None: print(f"::error::не знаю значение по умолчанию для {item} в case text({case_line})"); sys.exit(1)
            extra.append(f"{label}: {d}")
        else:
            d = _default_for(item)
            if d is None: print(f"::error::не знаю значение по умолчанию для {item} в case text({case_line})"); sys.exit(1)
            extra.append(d)
    targets = [os.path.join(core, "AyuPremium.swift"), os.path.join(root, "submodules/SettingsUI/Sources/GfpramPremiumController.swift"),
               os.path.join(root, "submodules/SettingsUI/Sources/GfpramSettingsController.swift")]
    for t in targets:
        if not os.path.exists(t): continue
        src, out, i, n = read(t), "", 0, 0
        key = "content: .text("
        while True:
            j = src.find(key, i)
            if j < 0: out += src[i:]; break
            k, d = j + len(key), 1
            while d and k < len(src):
                d += (src[k] == "(") - (src[k] == ")"); k += 1
            inner = src[j + len(key):k - 1]
            if len(_split_top(inner)) == 1:
                out += src[i:j] + key + inner + ", " + ", ".join(extra) + ")"; n += 1
            else:
                out += src[i:k]
            i = k
        if n:
            write(t, out); print(f"OK   .text(...) +{', '.join(extra)}: {n} в {os.path.relpath(t, root)}")

adapt_text_content()

# ======================= Итог =======================
bad = [l for l in CRITICAL if l not in disabled and hits_by_label.get(l, 0) == 0]
for l in ("ghost-read", "ghost-typing", "ghost-online", "ghost-stories", "keep-deleted", "edit-history", "hide-ads", "ghost-consume", "keep-selfdestruct", "forward-copy", "more-accounts", "gfp-context-menu", "gfp-premium-start"):
    if l not in disabled and hits_by_label.get(l, 0) == 0:
        print(f"::warning::патч {l} не применился (якорь не найден) — функция работать не будет")
if bad:
    print(f"::error::Критичные патчи не применились: {', '.join(bad)}. Сборка остановлена.")
    sys.exit(1)
print("ALL CRITICAL PATCHES OK")
