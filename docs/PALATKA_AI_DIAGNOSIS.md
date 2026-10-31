# Диагностика Palatka AI (Palatka AI Diagnosis)

> **Аудит проекта:** Palatka AI v2.2.10 & v2.2.11  
> **Исследованные модули:**  
> - `src/47_storage.lua`  
> - `src/47a_storage_textdraw.lua`  
> - `src/60b_carbon_storage.lua`  
> - `src/99_main.lua`

---

## 1. Конкретные архитектурные дефекты текущей реализации

### Дефект 1: Изоляция модулей и разрыв между рынком и хранилищем
- В проекте Palatka AI модуль работы с лавками и рынком (`src/10_market.lua` / `src/45_live.lua` / прототип `Market_Helper.lua`) уже использует `onReceivePacket` для пакета `220`.
- Однако модуль хранилищ (`src/47_storage.lua`) был написан полностью изолированно и подвязан **только на `onShowDialog`**.
- В результате хранилища вообще не имели доступа к сетевому потоку пакета 220!

### Дефект 2: Тупиковая ветвь с TextDraw в v2.2.10 (`src/47a_storage_textdraw.lua`)
- Попытка решить проблему сбора через `arm_textdraw` и перехват `onShowTextDraw` / `onTextDrawSetString` была основана на ошибочном предположении, что мобильный интерфейс — это TextDraw.
- Как доказал анализ APK `com.arizona.game`, контейнеры рендерятся через Kotlin Jetpack Compose (`ru.mrlargha.commonui.elements.inventory`). В SA-MP TextDraw эти данные никогда не попадают.

### Дефект 3: Эвристический парсер количества (`parse_line`)
- Функция `parse_line` в `src/47_storage.lua` пытается угадать количество предметов регулярными выражениями:
  ```lua
  name, qty = s:match('^(.-)%s*%(%s*([%d%., ]+)%s*шт%.?%s*%)%s*$')
  ```
- Если название предмета нестандартное или без слова «шт», предмет либо отбрасывается, либо получает флаг `quantity_confirmed = false`.
- При получении данных из нативного пакета 220 поле `count` приходит как строгое целое число `int`, что полностью устраняет необходимость в хрупких регулярных выражениях!

---

## 2. Необходимый план изменений для восстановления сканера

1. **Создать модуль `src/47b_storage_packet.lua`**:
   - Подключить прослушивание `addEventHandler('onReceivePacket')` для `packet_id == 220`.
   - Подключить обработчик `onArizonaDisplay` через библиотеку `arizona-events`.
   - Фильтровать события `event.inventory.*` и `containerContent.*`.

2. **Парсить нативный JSON**:
   - Извлекать массив `items` из полученного JSON:
     ```lua
     for _, it in ipairs(data.items or {}) do
         rows[#rows+1] = {
             name = it.name or DSP.item_name_by_id(it.id),
             qty = tonumber(it.count or it.amount or 1),
             id = tonumber(it.id or 0),
             quantity_confirmed = true,
             source = 'packet220'
         }
     end
     ```

3. **Обновить интерфейс хранилищ (`src/60b_carbon_storage.lua`)**:
   - Добавить индикатор источника: `[Сетевой пакет 220]` / `[Диалог]` / `[Ручной]`.
   - Автоматически создавать снимок при открытии контейнера без необходимости вручную запускать сбор TextDraw.
