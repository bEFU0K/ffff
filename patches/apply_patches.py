#!/usr/bin/env python3
"""Патчи Ayu для Telegram-iOS. Печатает OK/MISSING, не падает.
Использование: apply_patches.py <telegram-dir> [группы,которые,отключить]"""
import os, re, shutil, sys

root = sys.argv[1]
disabled = set(x.strip() for x in (sys.argv[2] if len(sys.argv) > 2 else "").split(",") if x.strip())
core = os.path.join(root, "submodules/TelegramCore/Sources")
here = os.path.dirname(os.path.abspath(__file__))

shutil.copy(os.path.join(here, "AyuSettings.swift"), os.path.join(core, "AyuSettings.swift"))
print("OK   AyuSettings.swift added")
open(os.path.join(core, "AyuSettingsExtra.swift"), "w", encoding="utf-8").write(
    "import Foundation\n\npublic extension AyuSettings {\n"
    "    static var keepSelfDestruct: Bool {\n"
    "        if UserDefaults.standard.object(forKey: \"ayu.keepSelfDestruct\") == nil { return true }\n"
    "        return UserDefaults.standard.bool(forKey: \"ayu.keepSelfDestruct\")\n"
    "    }\n}\n")
print("OK   AyuSettingsExtra.swift added")
shutil.copy(os.path.join(here, "AyuProfile.swift"), os.path.join(core, "AyuProfile.swift"))
print("OK   AyuProfile.swift added")

swift_files = []
for d, _, fs in os.walk(core):
    for f in fs:
        if f.endswith(".swift") and f not in ("AyuSettings.swift", "AyuProfile.swift", "AyuSettingsExtra.swift"):
            swift_files.append(os.path.join(d, f))

def patch(label, pattern, repl, filename=None, flags=re.M | re.S):
    if label in disabled:
        print(f"SKIP {label}: disabled"); return
    files = [p for p in swift_files if filename is None or os.path.basename(p) == filename]
    total = 0
    for p in files:
        try:
            src = open(p, encoding="utf-8").read()
        except Exception:
            continue
        new, n = re.subn(pattern, repl, src, flags=flags)
        if n:
            open(p, "w", encoding="utf-8").write(new)
            total += n
            print(f"OK   {label}: {n} in {os.path.relpath(p, root)}")
    if total == 0:
        print(f"MISSING {label}: anchor not found")

# --- Режим призрака ---
patch("ghost-read",
      r"(func synchronizePeerReadState\([^{]*?\)\s*->\s*Signal<Never, NoError>\s*\{)",
      r"\1\n    if AyuSettings.ghostRead { return .complete() }",
      filename="ManagedSynchronizePeerReadStates.swift")

patch("ghost-typing",
      r"(func requestActivity\([^{]*?\)\s*->\s*Signal<Void, NoError>\s*\{)",
      r"\1\n    if AyuSettings.ghostTyping { return .complete() }",
      filename="ManagedLocalInputActivities.swift")

patch("ghost-online",
      r"account\.updateStatus\(offline: ([^)]*)\)",
      r"account.updateStatus(offline: AyuSettings.ghostOnline ? .boolTrue : \1)")

patch("ghost-stories",
      r"(func _internal_markStoryAsSeen\([^{]*?\)\s*->\s*Signal<Never, NoError>\s*\{)",
      r"\1\n    if AyuSettings.ghostStories { return .complete() }")

# --- Удалённые сообщения ---
patch("keep-deleted",
      r"^(\s*)(transaction\.deleteMessages\([^\n]*\))[ \t]*$",
      r"\1if !AyuSettings.keepDeleted { \2 }",
      filename="AccountStateManagementUtils.swift", flags=re.M)

# --- История правок: запоминаем старый текст перед применением правки ---
patch("edit-history",
      r"(case let \.EditMessage\(id, [A-Za-z_]+\):)",
      r"\1\n                    if let ayuPrev = transaction.getMessage(id) { AyuEditHistory.record(id: id, text: ayuPrev.text) }",
      filename="AccountStateManagementUtils.swift")

# --- Скрытие рекламы (спонсорских сообщений) ---
patch("hide-ads",
      r"(func _internal_getSponsoredMessages\([^{]*?\)\s*->\s*Signal<[^{]*?,\s*NoError>\s*\{)",
      r"\1\n    if AyuSettings.hideAds { return .single(nil) }")

# --- Сохранение контента из каналов с запретом копирования ---
patch("allow-copy",
      r"(func isCopyProtected\(\)\s*->\s*Bool\s*\{)",
      r"\1\n        if AyuSettings.allowCopy { return false }")

# --- Не отправлять уведомления о скриншотах ---
patch("ghost-screenshot",
      r"(func [A-Za-z_]*[sS]creenshot[A-Za-z_]*\([^{]*?\)\s*->\s*Signal<(?:Never|Void), NoError>\s*\{)",
      r"\1\n    if AyuSettings.ghostScreenshot { return .complete() }")

# --- Не отправлять «прослушано/просмотрено» для голосовых, кружков, view-once ---
patch("ghost-consume",
      r"(func [A-Za-z_]*[mM]arkMessageContentAsConsumed[A-Za-z_]*\([^{]*?\)\s*->\s*Signal<Never, NoError>\s*\{)",
      r"\1\n    if AyuSettings.ghostConsume { return .complete() }")

# --- Сохранять историю, если собеседник очистил чат у обоих ---
patch("keep-cleared",
      r"^(\s*)(transaction\.clearHistory\([^\n]*\))[ \t]*$",
      r"\1if !AyuSettings.keepCleared { \2 }",
      filename="AccountStateManagementUtils.swift", flags=re.M)

# --- ЭКСПЕРИМЕНТАЛЬНО: строка «ID · DC · страна» в профиле пользователя (UI, по умолчанию отключено) ---
def patch_ui(label, pattern, repl):
    if label in disabled:
        print(f"SKIP {label}: disabled"); return
    hits = 0
    for d, _, fs in os.walk(os.path.join(root, "submodules/TelegramUI")):
        for f in fs:
            if f == "PeerInfoScreen.swift":
                p = os.path.join(d, f)
                src = open(p, encoding="utf-8").read()
                new, n = re.subn(pattern, repl, src, flags=re.M)
                if n:
                    open(p, "w", encoding="utf-8").write(new); hits += n
                    print(f"OK   {label}: {n} in {os.path.relpath(p, root)}")
    if hits == 0:
        print(f"MISSING {label}: anchor not found")

patch_ui("profile-info",
         r"^(\s*)(if let user = data\.peer as\? TelegramUser \{)\s*$",
         r"\1\2\n\1    items[.peerInfo, default: []].append(PeerInfoScreenLabeledValueItem(id: 9001, label: \"Ayu\", text: AyuProfile.infoText(for: user), textColor: .primary, action: nil, longTapAction: nil, requestLayout: { _ in }))")

# ================= Брендинг GFPGRAM =================
APP_NAME = "GFPGRAM"
app_dir = os.path.join(root, "Telegram/Telegram-iOS")

if "branding-name" in disabled:
    print("SKIP branding-name: disabled")
else:
    hits = 0
    for d, _, fs in os.walk(app_dir):
        for f in fs:
            p = os.path.join(d, f)
            if f == "Info.plist":
                s = open(p, encoding="utf-8", errors="ignore").read()
                n2, c = re.subn(r"(<key>(?:CFBundleDisplayName|CFBundleName)</key>\s*<string>)[^<]*(</string>)", r"\g<1>%s\g<2>" % APP_NAME, s)
                if c: open(p, "w", encoding="utf-8").write(n2); hits += c
            elif f == "InfoPlist.strings":
                s = open(p, encoding="utf-8", errors="ignore").read()
                n2, c = re.subn(r'("CFBundle(?:DisplayName|Name)"\s*=\s*)"[^"]*";', r'\1"%s";' % APP_NAME, s)
                if c: open(p, "w", encoding="utf-8").write(n2); hits += c
    print(f"OK   branding-name: {hits} replacement(s)" if hits else "MISSING branding-name: Info.plist keys not found")

if "branding-icon" in disabled:
    print("SKIP branding-icon: disabled")
else:
    try:
        from PIL import Image
        src_icon = Image.open(os.path.join(here, "..", "assets", "icon.png")).convert("RGB")
        hits = 0
        for d, _, fs in os.walk(app_dir):
            if not d.endswith(".appiconset"):
                continue
            for f in fs:
                if f.lower().endswith(".png"):
                    p = os.path.join(d, f)
                    try:
                        w, h = Image.open(p).size
                        src_icon.resize((w, h), Image.LANCZOS).save(p)
                        hits += 1
                    except Exception as e:
                        print(f"WARN icon {f}: {e}")
        print(f"OK   branding-icon: {hits} png replaced" if hits else "MISSING branding-icon: no *.appiconset png found")
    except ImportError:
        print("MISSING branding-icon: Pillow not installed")

# Надпись «Владелец» -> «#»
if "owner-hash" in disabled:
    print("SKIP owner-hash: disabled")
else:
    hits = 0
    for d, _, fs in os.walk(app_dir):
        for f in fs:
            if f == "Localizable.strings":
                p = os.path.join(d, f)
                s = open(p, encoding="utf-8", errors="ignore").read()
                n2, c = re.subn(r'^("(?:Channel|Group)\.Management\.Label(?:Owner|Creator)"\s*=\s*)"[^"]*";', r'\1"#";', s, flags=re.M)
                if c: open(p, "w", encoding="utf-8").write(n2); hits += c
    print(f"OK   owner-hash (bundled strings): {hits}" if hits else "MISSING owner-hash: bundled key not found")
    # серверный языковой пакет (ru и др.) перекрывает встроенные строки — подменяем при загрузке
    pres = os.path.join(root, "submodules/TelegramPresentationData")
    done = 0
    for d, _, fs in os.walk(pres):
        for f in fs:
            if f.endswith(".swift"):
                p = os.path.join(d, f)
                s = open(p, encoding="utf-8", errors="ignore").read()
                n2, c = re.subn(
                    r"(class PresentationStringsComponent[^{]*\{.*?init\([^)]*dict: \[String: String\][^)]*\)\s*\{[^}]*?)self\.dict = dict",
                    r'\1var ayuDict = dict; ayuDict["Channel.Management.LabelOwner"] = "#"; ayuDict["Channel.Management.LabelCreator"] = "#"; self.dict = ayuDict',
                    s, count=1, flags=re.S)
                if c: open(p, "w", encoding="utf-8").write(n2); done += c; print(f"OK   owner-hash (lang packs): {os.path.relpath(p, root)}")
    if not done:
        print("MISSING owner-hash (lang packs): в русском пакете останется «Владелец»")

# --- Самоудаляющиеся сообщения: не стирать при истечении таймера ---
patch("keep-selfdestruct",
      r"^(\s*)(transaction\.deleteMessages\([^\n]*\))[ \t]*$",
      r"\1if !AyuSettings.keepSelfDestruct { \2 }",
      filename="ManagedAutoremoveMessageOperations.swift", flags=re.M)

# ================= Диагностика: где искать якоря для ненайденных патчей =================
DIAG = {
    "ghost-read": r"func [A-Za-z_]*(ReadState|readHistory|ReadHistory|applyMaxReadIndex|markMessagesAsRead)[A-Za-z_]*\(",
    "hide-ads": r"func [A-Za-z_]*[sS]ponsored[A-Za-z_]*\(",
    "ghost-consume": r"func [A-Za-z_]*[cC]onsum[A-Za-z_]*\(",
    "keep-cleared": r"clearHistory\(",
    "keep-selfdestruct": r"ExpiredContent|AutoremoveTimeoutMessageAttribute|AutoclearTimeoutMessageAttribute",
    "ghost-consume2": r"ConsumePersonal|MessageContentConsumed|consumePersonalMessage|markMessageContentAsConsumed|readMessageContents",
}
for label, rx in DIAG.items():
    n = 0
    for p in swift_files:
        try:
            for i, line in enumerate(open(p, encoding="utf-8", errors="ignore"), 1):
                if re.search(rx, line):
                    n += 1
                    if n <= 30:
                        print(f"DIAG {label}: {os.path.relpath(p, root)}:{i}: {line.strip()[:170]}")
        except Exception:
            pass
