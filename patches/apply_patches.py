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
CRITICAL = ["branding-name", "branding-icon", "group-fallback"]
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

# ---------- свои Swift-файлы ----------
shutil.copy(os.path.join(here, "AyuSettings.swift"), os.path.join(core, "AyuSettings.swift"))
shutil.copy(os.path.join(here, "AyuProfile.swift"), os.path.join(core, "AyuProfile.swift"))
print("OK   Ayu*.swift added")

# ---------- Режим призрака ----------
# Прочитано: не отправляем readHistory на сервер (локально чат остаётся прочитанным)
patch("ghost-read",
      r"(func pushPeerReadState\([^{]*?readState: PeerReadState\)\s*->\s*Signal<PeerReadState, PeerReadStateValidationError>\s*\{)",
      r"\1\n    if AyuSettings.ghostRead { return .single(readState) }",
      filename="SynchronizePeerReadState.swift")

patch("ghost-typing",
      r"(private func requestActivity\([^{]*?\)\s*->\s*Signal<Void, NoError>\s*\{)",
      r"\1\n    if AyuSettings.ghostTyping { return .complete() }",
      filename="ManagedLocalInputActivities.swift")

patch("ghost-online",
      r"account\.updateStatus\(offline: \.boolFalse\)",
      r"account.updateStatus(offline: AyuSettings.ghostOnline ? .boolTrue : .boolFalse)",
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
      r"\1                if AyuSettings.keepDeleted { break }\n",
      filename="AccountStateManagementUtils.swift")
patch("keep-deleted",
      r"(case let \.DeleteMessagesWithGlobalIds\(ids\):\n)",
      r"\1                if AyuSettings.keepDeleted { break }\n",
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

# ======================= Итог =======================
bad = [l for l in CRITICAL if l not in disabled and hits_by_label.get(l, 0) == 0]
for l in ("ghost-read", "ghost-typing", "ghost-online", "ghost-stories", "keep-deleted", "hide-ads", "ghost-consume", "keep-selfdestruct"):
    if l not in disabled and hits_by_label.get(l, 0) == 0:
        print(f"::warning::патч {l} не применился (якорь не найден) — функция работать не будет")
if bad:
    print(f"::error::Критичные патчи не применились: {', '.join(bad)}. Сборка остановлена.")
    sys.exit(1)
print("ALL CRITICAL PATCHES OK")
