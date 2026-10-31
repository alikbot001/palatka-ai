# Результаты проверок и испытаний (Test Results)

> **Дата проведения:** 28 октября 2026 г.  
> **Окружение:** Физическое устройство Samsung Galaxy A15 (SM-A155F, Android 16), ADB USB.  
> **Процесс игры:** `com.arizona.game` (PID 29740)

---

## 1. Сводная таблица проверок

| № | Проверяемый компонент | Метод проверки | Фактический результат | Классификация |
|---|---|---|---|---|
| 1 | Версия MonetLoader | Анализ `monetloader.log` и бинарника `libmonetloader.so` | MonetLoader v3.8.0-os (x64 ABI, compat profile 1738) | **Подтверждено в игре** |
| 2 | Версия Arizona Mobile | `dumpsys package com.arizona.game` | v17.3.8 (versionCode 1738, targetSdk 37) | **Подтверждено в игре** |
| 3 | Поддержка `samp.events` | Анализ `lib/samp/events.lua` и логов | v4 полностью загружается, перехватывает RPC | **Подтверждено в игре** |
| 4 | Наличие RakNet API в MonetLoader | Анализ C++ исходников `luafuncs.cpp` | Все функции `raknet*` экспортированы в Lua | **Подтверждено исходным кодом** |
| 5 | Наличие C++ TextDraw API | Поиск `sampTextdraw*` в `luafuncs.cpp` | Функции чтения текста TextDraw **отсутствуют** | **Подтверждено исходным кодом** |
| 6 | Архитектура интерфейса инвентаря | Декомпиляция и strings DEX-файлов APK | Нативный Kotlin Compose: `ru.mrlargha.commonui` | **Подтверждено в игре** |
| 7 | Наличие CEF на Android | Анализ библиотек `*.so` и DEX | CEF **отсутствует**, интерфейсы нативные Android Views | **Подтверждено в игре** |
| 8 | Совместимость `arizona-events` | Инспекция `arizona-events` и выгрузка на устройство | Зависимости совпадают с MonetLoader API (`vector3d`, `BitStream`) | **Подтверждено в игре** |
| 9 | Перехват Packet 220 в MonetLoader | Анализ боевого кода `Market_Helper.lua` на телефоне | `onReceivePacket(220)` успешно читает рыночные JSON-данные | **Подтверждено в игре** |
| 10 | Причина сбоя сканера Palatka AI | Аудит `src/47_storage.lua` и `src/47a_storage_textdraw.lua` | Подписка на несуществующие события (`onShowDialog`, `onShowTextDraw`) | **Подтверждено исходным кодом** |

---

## 2. Развёрнутый диагностический скрипт

Создан независимый диагностический скрипт [`storage_probe.lua`](file:///home/cent127/AI%20Project/crr%20mobile%20arizona/storage_probe.lua) и загружен на устройство по пути:
`/storage/emulated/0/Android/media/com.arizona.game/monetloader/storage_probe.lua`

Скрипт выполняет:
- Проверку доступности всех системных библиотек (`ffi`, `bit`, `cjson`, `mimgui`, `samp.events`, `arizona-events`).
- Пассивную запись всех входящих пакетов `220` и `221` с декодированием заголовков.
- Перехват классических диалогов и TextDraws.
- Ведение отдельного лога `storage_probe.log` без влияния на производительность игры.
