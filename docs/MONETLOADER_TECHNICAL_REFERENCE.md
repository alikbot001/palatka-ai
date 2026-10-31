# Технический справочник MonetLoader (MonetLoader Technical Reference)

> **Статус проверки:** [Подтверждено в игре / Подтверждено исходным кодом]  
> **Целевая система:** Samsung Galaxy A15 (SM-A155F, Android 16, ARM64-v8a)  
> **Версия MonetLoader:** 3.8.0-os  
> **Версия Arizona Mobile:** v17.3.8 (build 1738)

---

## 1. Общие сведения и среда выполнения

- **Исполняемая среда:** LuaJIT 2.1.0-beta3 (совместимость с синтаксисом Lua 5.1).
- **Архитектура процесса:** 64-бит ARM (`arm64-v8a`). Все указатели памяти 64-битные (`uintptr_t`).
- **Совместимость с MoonLoader:** MonetLoader эмулирует MoonLoader v027 (`getMoonloaderVersion() == 27`).
- **Связующий слой C++/Lua:** `sol2` (`sol::state`).
- **Графический бэкенд:** `mimgui` (cimgui v1.88) поверх мобильного пайплайна OpenGL ES (инжекция в RenderWare через хук `rw::RsGlobal`).

---

## 2. Различия MonetLoader (Android) и MoonLoader (Windows)

| Подсистема | MoonLoader (Windows) | MonetLoader (Android) | Влияние на разработку |
|---|---|---|---|
| **ОС и вызовы API** | Win32 API (`kernel32`, `user32`) | Android NDK / Linux / POSIX | Запрещены вызовы Win32 DLL через FFI (`GetTickCount`, `VirtualProtect`). Использовать `os.clock()`, POSIX или `android.jnienv`. |
| **Управление памятью** | Чтение/запись по адресам SA-MP PC (`0xB70000`) | Хуки через `monethook` на адреса `libsamp.so` / `libGTASA.so` | Статические PC-адреса не работают. Хуки ставятся через `monethook.new(cast, callback, hook_addr)`. |
| **Ввод / Интерактивность** | Virtual Keys (`vkeys.VK_*`), оконные сообщения Windows | Сенсорный ввод Android (`onTouch`, `monetloader.touch_events`) | Нельзя ожидать нажатия клавиш клавиатуры ПК. Использовать `onTouch(type, id, x, y)` или ImGui-кнопки. |
| **Библиотека mimgui** | DirectX 9 / DirectX 11 backend | OpenGL ES RenderWare backend | Полная совместимость API mimgui. Иконки загружаются через `imrw.load_image` / `imrw.load_image_from_memory`. |
| **Рендеринг TextDraw** | Доступен через память и функции SA-MP | Только перехват входящего RPC `onShowTextDraw` | Функции `sampTextdrawIsExists`, `sampTextdrawGetString` в C++ ядре **отсутствуют**. |
| **Штатные диалоги** | `sampShowDialog`, `onShowDialog` | `sampShowDialog`, `onShowDialog` | Полностью поддержаны. Диалоги отображаются нативно. |

---

## 3. Проверенные доступные библиотеки и API

### 3.1. Встроенные библиотеки (Native & Lua)
- **`ffi`** [Подтверждено в игре]: Полная поддержка Foreign Function Interface (ARM64 ABI).
- **`bit` / `bitex`** [Подтверждено в игре]: Побитовые операции (`band`, `bor`, `bxor`, `lshift`, `rshift`).
- **`cjson`** [Подтверждено в игре]: Быстрый C-парсер JSON (`cjson.decode`, `cjson.encode`).
- **`samp.events` (v4)** [Подтверждено в игре]: Поддерживает полный перечень SA-MP 0.3.7 RPC и пакетов.
- **`mimgui`** [Подтверждено в игре]: Полная поддержка виртуализированных списков, акцентов DrawList, модальных окон.
- **`monethook`** [Подтверждено исходным кодом]: Встроенный модуль инжекции и хукинга ARM64 инструкций.
- **`webviews`** (Radare) [Подтверждено в игре]: Модуль управления прозрачными Android WebViews через `WebViews.jar`.

### 3.2. RakNet BitStream API (Экспортировано напрямую в глобальный Lua scope)
Все функции проверены по исходному коду `cpp/script/luafuncs.cpp`:
- `raknetNewBitStream()` -> `BitStream*`
- `raknetDeleteBitStream(bs)`
- `raknetResetBitStream(bs)`
- `raknetBitStreamReadInt8(bs)`, `ReadInt16(bs)`, `ReadInt32(bs)`, `ReadFloat(bs)`, `ReadBool(bs)`
- `raknetBitStreamWriteInt8(bs, val)`, `WriteInt16(bs, val)`, `WriteInt32(bs, val)`, `WriteFloat(bs, val)`, `WriteBool(bs, val)`
- `raknetBitStreamReadString(bs, length)`
- `raknetBitStreamWriteString(bs, str)`
- `raknetBitStreamDecodeString(bs, size)` — декодирование сжатых строк через `RakNet::StringCompressor`.
- `raknetBitStreamEncodeString(bs, str)` — сжатие строк.
- `raknetBitStreamIgnoreBits(bs, count)`
- `raknetBitStreamSetReadOffset(bs, offset)`, `SetWriteOffset(bs, offset)`
- `raknetBitStreamGetNumberOfUnreadBits(bs)`
- `raknetSendBitStream(bs)` / `raknetSendBitStreamEx(bs, priority, reliability, channel)`
- `raknetEmulPacketReceiveBitStream(packetId, bs)` — эмуляция входящего пакета клиенту.
- `raknetEmulRpcReceiveBitStream(rpcId, bs)` — эмуляция входящего RPC клиенту.

---

## 4. Жизненный цикл скриптов и система событий

- **Регистрация событий:**  
  В MonetLoader глобальные сетевые события регистрируются через `addEventHandler`:
  ```lua
  addEventHandler('onReceivePacket', function(packet_id, bs) ... end)
  addEventHandler('onReceiveRpc', function(rpc_id, bs) ... end)
  addEventHandler('onSendPacket', function(packet_id, bs) ... end)
  addEventHandler('onSendRpc', function(rpc_id, bs) ... end)
  ```
- **Обработка ошибок:**  
  Ошибка в обработчике события или корутине не крашит всю игру, но убивает поток скрипта с записью в `monetloader/logs/monetloader.log`:
  ```text
  [HH:MM:SS] (error) script.lua: ... error description ...
  [HH:MM:SS] (error) script.lua: Script died due to an error.
  ```
- **Потоки (Threads):**  
  Поддерживаются `lua_thread.create(func)` и `lua_thread.create_suspended(func)`. Функции задержки `wait(ms)` работают штатно внутри корутин.
- **Работа при сворачивании игры:**  
  Для предотвращения выгрузки скрипта при переключении приложений используется:
  ```lua
  script_properties('work-in-pause', 'forced-reloading-only')
  ```
