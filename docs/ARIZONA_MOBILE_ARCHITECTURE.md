# Архитектура Arizona Mobile (Arizona Mobile Architecture)

> **Статус проверки:** [Подтверждено в игре / Подтверждено анализом APK и библиотек]  
> **Пакет игры:** `com.arizona.game` (v17.3.8, versionCode 1738)  
> **UI Фреймворк:** Нативный Jetpack Compose + ViewBinding (`ru.mrlargha.commonui`)

---

## 1. Главное открытие: Отличие Mobile от PC CEF

На серверах **Arizona RP (PC)** подавляющее большинство кастомных интерфейсов (новый инвентарь, донат, баттлпасс, лавки, кастомные диалоги) работают через **CEF (Chromium Embedded Framework)** — по сути браузерные веб-страницы на HTML/JS/CSS, общающиеся с клиентом через вызовы `window.executeEvent(...)`.

На **Arizona Mobile (Android)** CEF **ОТСУТСТВУЕТ ПОЛНОСТЬЮ**. Вместо него используется:
1. **Нативный Android GUI (`ru.mrlargha.commonui`)**:  
   Все современные экраны написаны на **Kotlin / Jetpack Compose / ViewBinding** и скомпилированы в байт-код DEX приложения `base.apk`.
2. **Слой JNI и C++**:  
   Библиотеки `libsamp.so` и `libarzmod.so` обрабатывают сетевые пакеты RakNet и через JNI передают структуры данных напрямую в Java/Kotlin контроллеры.

---

## 2. Карта компонентов и модулей интерфейса

При анализе DEX-классов `com.arizona.game` обнаружены следующие специализированные экраны в пакете `ru.mrlargha.commonui.elements.*`:

| Название элемента | Kotlin класс | Назначение в игре | Сетевой механизм |
|---|---|---|---|
| **Инвентарь игрока** | `inventory.presentation.InventoryScreen` | Сетка предметов, слоты экипировки, аксессуары | Packet 220 (JSON payload) |
| **Багажники авто** | `inventory.presentation.InventoryScreen` | Вторичный контейнер инвентаря (`SubInventoryAdapter`) | Packet 220 (sub-interface) |
| **Шкафы домов** | `inventory.presentation.InventoryScreen` | Вторичный контейнер инвентаря (`SubInventoryAdapter`) | Packet 220 (sub-interface) |
| **Склады игроков** | `inventory.presentation.InventoryScreen` | Складские ячейки (`WarehouseMoney`, слоты) | Packet 220 (sub-interface) |
| **Лавки и рынок** | `trade` / `shop` | Скупка и продажа на ЦР, витрины лавок | Packet 220 Marker 84 (iface 6, 7, 8) |
| **Призовые контейнеры** | `new_container.NewContainerScreen` | Открытие кейсов и контейнеров | Packet 220 |
| **Классические диалоги** | `dialogs.*` / native SA-MP | Старые системные списки и подтверждения | RPC 61 (`onShowDialog`) |
| **Интерфейсы спидометра/худа** | `hud.presentation.Hud` | Спидометр, радар, полосы здоровья/брони | Нативный Compose UI + TextDraws |

---

## 3. Структура данных предмета инвентаря (`InventoryItem`)

В Kotlin-модели `ru.mrlargha.commonui.elements.inventory.domain.models.InventoryItem` зафиксированы следующие обязательные поля:
- `id` (int): уникальный номер/идентификатор предмета в глобальной базе Arizona.
- `slot` (int): номер ячейки в контейнере (0..N).
- `count` / `amount` (int): фактическое количество единиц в пачке.
- `name` (String): отображаемое название предмета.
- `model` (int): SA-MP модель или ID иконки.
- `color` / `effect`: визуальный модификатор / свечение.

---

## 4. Карта потока данных (Data Flow Architecture)

```
[ Сервер Arizona RP ]
         │
         │  Сетевой протокол RakNet (UDP)
         ▼
[ libsamp.so / libraknet.so ]
         │
         ├──► Packet 220 (0xDC) / Packet 221 (0xDD) ───► [ libarzmod.so ]
         │                                                      │  (JNI вызов)
         │                                                      ▼
         │                                         [ ru.mrlargha.commonui ]
         │                                         (Native Android Compose UI)
         │                                         - InventoryScreen
         │                                         - SubInventoryAdapter (Trunk/Cabinet/Storage)
         │
         └──► Стандартные RPC (RPC 61 ShowDialog)
                     │
                     ▼
         [ SA-MP Dialog Manager ] (Classic Dialog)
```

### Доступность для Lua (MonetLoader):
Lua-скрипты в MonetLoader подключены через библиотеку `libsamp.so` на уровне **RakNet BitStream**:
1. События `onReceivePacket` перехватывают **любые входящие пакеты** ДО того, как они передаются в `libarzmod.so` или Java!
2. Это означает, что **любые данные инвентаря, багажника или склада, отправляемые сервером на клиент, гарантированно проходят через точку перехвата `onReceivePacket(220, bs)`**!
3. Перехват на уровне `onShowDialog` или `onShowTextDraw` не видит эти данные, потому что движок игры отображает их в обход стандартных диалогов через нативный слой `ru.mrlargha.commonui`.
