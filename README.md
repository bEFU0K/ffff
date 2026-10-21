# GFPGRAM — сборка

1. В репозитории: Settings → Secrets and variables → Actions → создать секреты `API_ID` и `API_HASH` (с https://my.telegram.org/apps).
2. Actions → Build GFPGRAM ipa → Run workflow (поля по умолчанию).
3. Скачать артефакт, установить через Sideloadly файл **GFPGRAM-Sideloadly.ipa** (не GFPGRAM.ipa).

Если критичный патч (название, иконка, App Group) не применился, сборка остановится сразу с понятной ошибкой,
а не через 2 часа с приложением «Telegram» и чёрным экраном.
