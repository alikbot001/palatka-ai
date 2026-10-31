# Справочник сетевых событий Arizona (Arizona Event Reference)

> **Статус проверки:** [Подтверждено в игре / Подтверждено исходным кодом / Подтверждено тестами]

---

## 1. Кастомный сетевой пакет Arizona: Packet 220 (`0xDC`)

Пакет `220` является базовым транспортным контейнером для всех кастомных систем Arizona RP (рынок, инвентарь, хранилища, интерфейсы).

### 1.1. Структура заголовка пакета 220 (Режим CEF / Display)
Используется сервером для передачи событий интерфейса (инвентарь, контейнеры, диалоги):
```
[1 байт]   packet_id = 220 (0xDC)
[1 байт]   event_id  = 17 (0x11, onArizonaDisplay)
[4 байта]  server_id (uint32)
[2 байта]  length (uint16, длина строки данных)
[1 байт]   is_encoded (uint8, 0 = обычный текст, 1 = сжато StringCompressor)
[N байт]   payload (строка в формате JavaScript вызова: window.executeEvent(...))
```

#### Обработка в Lua (библиотека `arizona-events`):
```lua
local acef = require('arizona-events')

function acef.onArizonaDisplay(packet)
    if acef.decode(packet) then
        -- packet.event: имя события (например, 'event.inventory.playerInventory')
        -- packet.json: декодированная JSON-таблица
        if packet.event:find('event.inventory') or packet.event:find('containerContent') then
            print('Получены данные хранилища/инвентаря:', packet.event)
        end
    end
end
```

---

### 1.2. Структура заголовка пакета 220 (Режим Marker 84 / Торговый протокол)
Используется мобильным клиентом и сервером для обмена данными рынка, лавок, торговли и кликов по слотам (обнаружено и подтверждено в коде `Market_Helper.lua`):
```
[1 байт]   packet_id = 220 (0xDC)
[1 байт]   marker    = 84 (0x54, символ 'T')
[1 байт]   iface     = Interface ID (uint8)
[1 байт]   subid     = Sub-Action ID (uint8)
[2 байта]  length    = Длина JSON строки (uint16)
[1 байт]   is_encoded= Флаг сжатия (uint8)
[N байт]   json_str  = Полезная нагрузка JSON
```

#### Подтверждённые Interface ID (`iface`):
- `4` — **MARKET_ACTION** (Действия на центральном рынке)
- `6` — **SHOP_LIST** (Список лавок на сервере и их владельцы)
- `7` — **SHOP_ITEMS** (Список товаров в конкретной лавке с ценами и остатком)
- `8` — **SHOP_ACTION** (Покупка/продажа товара в лавке)
- `57` — **TRADE** (Окно прямого обмена между игроками)
- `60` — **SLOT_CLICK** (Клик по слоту инвентаря/хранилища)
- `255` — **CLOSE_MENU** (Закрытие активного меню)

#### Функция распаковки строки (из `Market_Helper.lua`):
```lua
function read_packet220_string(bs)
    local length  = raknetBitStreamReadInt16(bs)
    local encoded = raknetBitStreamReadInt8(bs)
    if encoded ~= 0 then
        return raknetBitStreamDecodeString(bs, length + encoded)
    else
        return raknetBitStreamReadString(bs, length)
    end
end
```

---

## 2. Кастомный пакет Arizona: Packet 221 (`0xDD`)

Используется для расширенной синхронизации кастомных ботов, NPC и серверных сущностей:
- `onArizonaBotStreamIn` (sub 50)
- `onArizonaBotStreamOut` (sub 51)
- `onArizonaBotOnfootSync` (sub 52)
- `onArizonaSetBotAttachedObject` (sub 86)

---

## 3. Стандартные SA-MP RPC (Через `samp.events`)

### 3.1. `onShowDialog` (RPC 61)
- **Сигнатура:** `function sampev.onShowDialog(dialogId, style, title, button1, button2, text)`
- **Статус на Arizona Mobile:** Активно работает для классических серверных меню (пароли, выбор спавна, старые квесты).
- **Стили диалогов:**
  - `0` — `DIALOG_STYLE_MSGBOX`
  - `1` — `DIALOG_STYLE_INPUT`
  - `2` — `DIALOG_STYLE_LIST`
  - `3` — `DIALOG_STYLE_PASSWORD`
  - `4` — `DIALOG_STYLE_TABLIST`
  - `5` — `DIALOG_STYLE_TABLIST_HEADERS`

### 3.2. `onShowTextDraw` (RPC 83) & `onTextDrawSetString` (RPC 105)
- **Сигнатуры:**
  - `function sampev.onShowTextDraw(textdrawId, textdraw)`
  - `function sampev.onTextDrawSetString(textdrawId, text)`
- **Статус на Arizona Mobile:** Активно используется для спидометра, серверного логотипа, уведомлений на экране и подсказок клавиш.  
- **ВНИМАНИЕ:** Инвентарь и контейнеры на современном клиенте v17.3.8 **НЕ** используют TextDraw.
