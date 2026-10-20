#!/usr/bin/env python3
"""Ретранслятор уведомлений GFPGRAM -> Sreppush (web-push на iPhone).

Работает на сервере/ПК, который включён постоянно. Заходит в ТВОЙ аккаунт Telegram как
ещё одно устройство (Telethon), слушает новые входящие и отправляет их на endpoint портала.
Файл gfp_relay.session = полный доступ к аккаунту: храни как пароль, никому не давай.

Установка:  pip install telethon
Запуск:     API_ID=... API_HASH=... PUSH_URL=https://srepportal.craft-host.ru/api/gfp_push.php \
            PUSH_SECRET=длинный_секрет python3 gfp_relay.py
"""
import asyncio, json, os, urllib.request
from telethon import TelegramClient, events

API_ID = int(os.environ["API_ID"])
API_HASH = os.environ["API_HASH"]
PUSH_URL = os.environ["PUSH_URL"]
PUSH_SECRET = os.environ["PUSH_SECRET"]
NOTIFY_GROUPS = os.environ.get("NOTIFY_GROUPS", "0") == "1"   # по умолчанию только личные чаты
SHOW_TEXT = os.environ.get("SHOW_TEXT", "1") == "1"            # 0 = «Новое сообщение» без текста

client = TelegramClient("gfp_relay", API_ID, API_HASH, receive_updates=True)

def post(payload):
    req = urllib.request.Request(
        PUSH_URL, data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json", "X-Push-Secret": PUSH_SECRET})
    try:
        urllib.request.urlopen(req, timeout=15).read()
    except Exception as e:
        print("push error:", e)

@client.on(events.NewMessage(incoming=True))
async def on_message(event):
    if not (event.is_private or NOTIFY_GROUPS):
        return
    sender = await event.get_sender()
    name = getattr(sender, "first_name", None) or getattr(sender, "title", None) or "Telegram"
    if getattr(sender, "bot", False):
        pass
    text = event.raw_text or ("Медиа" if event.media else "Сообщение")
    body = text[:140] if SHOW_TEXT else "Новое сообщение"
    await asyncio.to_thread(post, {
        "title": name, "body": body, "tag": f"tg{event.chat_id}", "ts": int(event.date.timestamp() * 1000)})

client.start()
print("GFPGRAM relay запущен")
client.run_until_disconnected()
