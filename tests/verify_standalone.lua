-- Standalone startup + market/cache regression. Desktop measurements only.
-- Run python3 build.py, then luajit tests/verify_standalone.lua.
dofile('tests/test_standalone.lua')
print('[TEST 1/2] Built CP1251 artifact startup fixture: OK')
print('[TEST 3] Генерация тестового рынка на 90 лавок (синтетическая фикстура)...')
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
local cold_start=os.clock()
local prepared=DSP.market.arbitrage_grouped()
print(string.format('  Холодная подготовка вне UI: %.2f мс', (os.clock()-cold_start)*1000))
local start_clock = os.clock()
for frame = 1, 300 do
    -- Вызов метода выборки арбитража для экрана
    local arb_list = DSP.market.arbitrage_grouped()
    assert(arb_list==prepared,'group/cache identity changed during warm frames')
    assert(type(arb_list) == 'table', 'ОШИБКА: арбитраж не вернул список')
end
local duration = os.clock() - start_clock
local ms_per_frame = (duration / 300) * 1000
print(string.format('  Время на 1 кадр арбитража: %.4f мс (суммарно 300 кадров: %.3f сек)', ms_per_frame, duration))
assert(ms_per_frame < 1.0, string.format('КРИТИЧЕСКИЙ ПРОВАЛ: Кадр арбитража занимает %.2f мс (должно быть < 1 мс). Кэширование не работает!', ms_per_frame))
print('  OK: Повторные выборки используют кэш в этой фикстуре.')

print('[TEST 5] Проверка Item Finder...')
local found = DSP.market.find_item('Предмет 1')
assert(#found > 0, 'ОШИБКА: Item Finder ничего не нашёл')
print('  OK: Item Finder находит товары мгновенно (' .. #found .. ' совпадений)')

print('════════════════════════════════════════════════════════════════')
print(' DESKTOP STARTUP / MARKET / CACHE CHECKS PASSED. ANDROID IS A SEPARATE CHECK. ')
print('════════════════════════════════════════════════════════════════')
