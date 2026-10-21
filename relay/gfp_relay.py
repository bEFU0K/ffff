#!/usr/bin/env python3
"""Ретранслятор уведомлений GFPGRAM -> Sreppush (web-push на iPhone).

Работает на сервере/ПК, который включён постоянно. Заходит в ТВОЙ аккаунт Telegram как
ещё одно устройство (Telethon), слушает события и отправляет их на endpoint портала.
Файл gfp_relay.session = полный доступ к аккаунту: храни как пароль, никому не давай.

Что приходит на телефон:
  - новые сообщения (текст или тип медиа: фото, голосовое, видео, файл и т.д.);
  - упоминания и ответы тебе в группах (даже если NOTIFY_GROUPS=0);
  - входящие звонки (обычные и видео) и пропущенные звонки;
  - изменённые сообщения (NOTIFY_EDITS=1);
  - удаления (NOTIFY_DELETES=1, Telegram не отдаёт текст удалённого, только факт).
Секретные чаты Telethon не видит, звонок отвечать с уведомления нельзя: это только оповещение.

Установка:  pip install telethon
Запуск:     API_ID=... API_HASH=... PUSH_URL=https://srepportal.craft-host.ru/api/gfp_push.php \\
            PUSH_SECRET=длинный_секрет python3 gfp_relay.py

Настройки (переменные окружения, 1 = да, 0 = нет):
  NOTIFY_GROUPS=0   все сообщения групп и каналов (иначе только личные + упоминания)
  SHOW_TEXT=1       показывать текст (0 = «Новое сообщение»)
  RESPECT_MUTE=1    не присылать из чатов с выключенными уведомлениями
  NOTIFY_EDITS=0    уведомлять об изменённых сообщениях
  NOTIFY_DELETES=0  уведомлять об удалениях
  NOTIFY_CALLS=1    звонки и пропущенные
"""
import asyncio, json, os, time, urllib.request
from telethon import TelegramClient, events, functions, types

API_ID = int(os.environ["API_ID"])
API_HASH = os.environ["API_HASH"]
PUSH_URL = os.environ["PUSH_URL"]
PUSH_SECRET = os.environ["PUSH_SECRET"]

def flag(name, default):
    return os.environ.get(name, "1" if default else "0") == "1"

NOTIFY_GROUPS = flag("NOTIFY_GROUPS", False)
SHOW_TEXT = flag("SHOW_TEXT", True)
RESPECT_MUTE = flag("RESPECT_MUTE", True)
NOTIFY_EDITS = flag("NOTIFY_EDITS", False)
NOTIFY_DELETES = flag("NOTIFY_DELETES", False)
NOTIFY_CALLS = flag("NOTIFY_CALLS", True)

client = TelegramClient("gfp_relay", API_ID, API_HASH, receive_updates=True)
calls = {}        # id звонка -> имя звонящего (для «пропущенный звонок»)
mute_cache = {}   # id чата -> (до какого времени кэш, замучен ли)


def post(payload):
    req = urllib.request.Request(
        PUSH_URL, data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json", "X-Push-Secret": PUSH_SECRET})
    try:
        urllib.request.urlopen(req, timeout=15).read()
    except Exception as e:
        print("push error:", e)


async def push(title, body, tag):
    await asyncio.to_thread(post, {"title": title, "body": body, "tag": tag, "ts": int(time.time() * 1000)})


def display_name(entity):
    if entity is None:
        return "Telegram"
    first = getattr(entity, "first_name", None)
    if first:
        last = getattr(entity, "last_name", None)
        return f"{first} {last}" if last else first
    return getattr(entity, "title", None) or "Telegram"


def describe(msg):
    if msg.raw_text:
        return msg.raw_text
    if msg.photo: return "📷 Фото"
    if msg.voice: return "🎤 Голосовое сообщение"
    if msg.video_note: return "⚪ Видеосообщение"
    if msg.gif: return "GIF"
    if msg.video: return "🎬 Видео"
    if msg.sticker: return "Стикер"
    if msg.audio: return "🎵 Аудио"
    if msg.poll: return "📊 Опрос"
    if msg.contact: return "👤 Контакт"
    if msg.geo: return "📍 Геопозиция"
    if msg.document: return "📎 Файл"
    return "Сообщение"


async def is_muted(event):
    if not RESPECT_MUTE:
        return False
    cid = event.chat_id
    cached = mute_cache.get(cid)
    now = time.time()
    if cached and cached[0] > now:
        return cached[1]
    muted = False
    try:
        settings = await client(functions.account.GetNotifySettingsRequest(
            peer=types.InputNotifyPeer(peer=await event.get_input_chat())))
        until = getattr(settings, "mute_until", None)
        if until is not None:
            muted = int(until.timestamp()) > now if hasattr(until, "timestamp") else int(until) > now
    except Exception as e:
        print("mute check error:", e)
    mute_cache[cid] = (now + 120, muted)
    return muted


async def format_message(event, prefix=""):
    sender = await event.get_sender()
    name = display_name(sender)
    title = name
    if not event.is_private:
        chat = await event.get_chat()
        title = f"{display_name(chat)} · {name}"
    text = describe(event.message)
    body = (prefix + text[:140]) if SHOW_TEXT else (prefix + "Новое сообщение")
    return title, body


def addressed_to_me(event):
    msg = event.message
    return bool(getattr(msg, "mentioned", False))


@client.on(events.NewMessage(incoming=True))
async def on_message(event):
    if not (event.is_private or NOTIFY_GROUPS or addressed_to_me(event)):
        return
    if await is_muted(event) and not addressed_to_me(event):
        return
    title, body = await format_message(event, "@ " if (not event.is_private and addressed_to_me(event)) else "")
    await push(title, body, f"tg{event.chat_id}")


@client.on(events.MessageEdited(incoming=True))
async def on_edit(event):
    if not NOTIFY_EDITS:
        return
    if not (event.is_private or NOTIFY_GROUPS):
        return
    if await is_muted(event):
        return
    title, body = await format_message(event, "✏️ ")
    await push(title, body, f"tgedit{event.chat_id}")


@client.on(events.MessageDeleted())
async def on_delete(event):
    if not NOTIFY_DELETES:
        return
    chat_id = getattr(event, "chat_id", None)
    name = "Telegram"
    if chat_id:
        try:
            name = display_name(await client.get_entity(chat_id))
        except Exception:
            pass
    count = len(event.deleted_ids)
    await push(name, f"🗑 Удалено сообщений: {count}", f"tgdel{chat_id}")


@client.on(events.Raw(types.UpdatePhoneCall))
async def on_call(update):
    if not NOTIFY_CALLS:
        return
    call = update.phone_call
    if isinstance(call, types.PhoneCallRequested):
        try:
            name = display_name(await client.get_entity(call.admin_id))
        except Exception:
            name = "Telegram"
        calls[call.id] = name
        kind = "📹 Входящий видеозвонок" if call.video else "📞 Входящий звонок"
        await push(name, kind, f"call{call.id}")
    elif isinstance(call, types.PhoneCallDiscarded):
        name = calls.pop(call.id, None)
        if name and isinstance(call.reason, types.PhoneCallDiscardReasonMissed):
            await push(name, "📵 Пропущенный звонок", f"call{call.id}")


client.start()
print("GFPGRAM relay запущен")
client.run_until_disconnected()
