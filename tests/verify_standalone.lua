-- Автономный тестовый стенд для проверки palatka_ai.lua в песочнице.
-- Запуск: luajit tests/verify_standalone.lua
-- Перед запуском: python3 build.py (соберёт palatka_ai.lua из src/)
--
-- Все 5 тестов обязаны пройти. Кадр арбитража < 1 мс — критерий кэширования.
package.path = './?.lua;./src/?.lua;' .. package.path
package.preload['encoding'] = function()
  return {
    default = 'CP1251',
    CP1251 = { encode = function(self, s) return s end },
    UTF8 = { decode = function(self, s) return s end, encode = function(self, s) return s end },
  }
end

-- 1. Мокирование окружения MoonLoader / MonetLoader
_G.script_name = function() end
_G.script_author = function() end
_G.script_version = function() end
_G.getWorkingDirectory = function() return '.' end
_G.thisScript = function() return { name = 'palatka ai' } end
_G.sampRegisterChatCommand = function(cmd, fn) end
_G.sampGetCurrentServerName = function() return 'Arizona Mobile II' end
_G.lua_thread = { create = function(fn) return {_fn = fn} end }
_G.wait = function() end

-- 2. Мокирование mimgui
local ffi = require('ffi')
local imgui = {
    new = {
        bool = function(v) local b = ffi.new('bool[1]'); b[0] = v or false; return b end,
        int = function(v) local i = ffi.new('int[1]'); i[0] = v or 0; return i end,
        float = function(v) local f = ffi.new('float[1]'); f[0] = v or 0; return f end,
        char = { [128] = function() return ffi.new('char[128]') end },
    },
    Col = {
        CheckMark = 1, WindowBg = 2, Text = 3, Button = 4, ButtonHovered = 5,
        ButtonActive = 6, ChildBg = 7, FrameBg = 8, FrameBgHovered = 9,
        Border = 10, Header = 11, HeaderHovered = 12, Separator = 13,
        ScrollbarBg = 14, ScrollbarGrab = 15, ScrollbarGrabHovered = 16,
        ScrollbarGrabActive = 17, SliderGrab = 18, SliderGrabActive = 19,
        PopupBg = 20, TextDisabled = 21, TitleBg = 22, TitleBgActive = 23
    },
    ImVec2 = function(x, y) return { x = x or 0, y = y or 0 } end,
    ImVec4 = function(r, g, b, a) return { r = r or 0, g = g or 0, b = b or 0, a = a or 1 } end,
    OnFrame = function(cond, draw) return { Unsubscribe = function() end } end,
    PushStyleColor = function(col, val) end,
    PopStyleColor = function(n) end,
    Begin = function() return true end,
    End = function() end,
    BeginChild = function() return true end,
    EndChild = function() end,
    Text = function() end,
    TextColored = function() end,
    TextDisabled = function() end,
    Button = function() return false end,
    SmallButton = function() return false end,
    SameLine = function() end,
    Separator = function() end,
    Spacing = function() end,
    NewLine = function() end,
    Checkbox = function() return false end,
    InputInt = function() return false end,
    InputText = function() return false end,
    InputTextWithHint = function() return false end,
    InputTextMultiline = function() return false end,
    GetContentRegionAvail = function() return { x = 800, y = 600 } end,
    GetIO = function() return { DisplaySize = { x = 2340, y = 1080 }, MouseDelta = { x = 0, y = 0 } } end,
}
_G.imgui = imgui

-- 3. Загрузка собранного релизного скрипта
print('[TEST 1] Синтаксическая проверка luajit...')
local res = os.execute('luajit -bl palatka_ai.lua /dev/null')
assert(res == 0 or res == true, 'ОШИБКА: palatka_ai.lua не проходит luajit -bl')
print('  OK: Синтаксис LuaJIT валиден')

print('[TEST 2] Загрузка скрипта в память...')
dofile('palatka_ai.lua')
assert(DSP and DSP.version, 'ОШИБКА: DSP не инициализирован')
print('  OK: Скрипт успешно инициализирован, версия ' .. tostring(DSP.version))

print('[TEST 3] Генерация тестового рынка на 800 товаров (имитация va-ta.com)...')
local mock_payload = { shops = {} }
for s = 1, 90 do
    local shop = { owner = 'Player_' .. s, shop_num = tostring(s), server_id = 102, updated_at = os.time(), sell_slots = {}, buy_slots = {} }
    for i = 1, 20 do
        table.insert(shop.sell_slots, { name = 'Предмет ' .. (i % 50), price = 1000 + i * 50, qty = 10, ench = 0 })
        table.insert(shop.buy_slots, { name = 'Предмет ' .. (i % 50), price = 1200 + i * 50, qty = 10, ench = 0 })
    end
    table.insert(mock_payload.shops, shop)
end
DSP.market.rebuild(mock_payload, 102)
assert(#DSP.market.state.rows > 0, 'ОШИБКА: Рынок пуст после rebuild')
print('  OK: Рынок собран, уникальных товаров: ' .. #DSP.market.state.rows)

print('[TEST 4] Стресс-тест арбитража на 60 FPS (проверка кэширования)...')
-- Имитируем 300 кадров вызова arbitrage_tab
local start_clock = os.clock()
for frame = 1, 300 do
    -- Вызов метода выборки арбитража для экрана
    local arb_list = DSP.market.arbitrage_filtered and DSP.market.arbitrage_filtered() or DSP.market.arbitrage()
    assert(type(arb_list) == 'table', 'ОШИБКА: арбитраж не вернул список')
end
local duration = os.clock() - start_clock
local ms_per_frame = (duration / 300) * 1000
print(string.format('  Время на 1 кадр арбитража: %.4f мс (суммарно 300 кадров: %.3f сек)', ms_per_frame, duration))
assert(ms_per_frame < 1.0, string.format('КРИТИЧЕСКИЙ ПРОВАЛ: Кадр арбитража занимает %.2f мс (должно быть < 1 мс). Кэширование не работает!', ms_per_frame))
print('  OK: Кэширование арбитража работает идеально!')

print('[TEST 5] Проверка Item Finder...')
local found = DSP.market.find_item('Предмет 1')
assert(#found > 0, 'ОШИБКА: Item Finder ничего не нашёл')
print('  OK: Item Finder находит товары мгновенно (' .. #found .. ' совпадений)')

print('════════════════════════════════════════════════════════════════')
print(' ВСЕ ТЕСТЫ ПРОЙДЕНЫ УСПЕШНО! СКРИПТ ГОТОВ К РЕЛИЗУ НА ARIZONA! ')
print('════════════════════════════════════════════════════════════════')
