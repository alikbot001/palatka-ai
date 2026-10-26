package.path = './?.lua;./src/?.lua;' .. package.path
package.preload['encoding'] = function()
  return {
    default = 'CP1251',
    CP1251 = { encode = function(self, s) return s end },
    UTF8 = { decode = function(self, s) return s end, encode = function(self, s) return s end },
  }
end

local dir = '/tmp/opencode/dsp_test'
os.execute('mkdir -p ' .. dir)
getWorkingDirectory = function() return dir end
doesDirectoryExist = function() return true end
createDirectory = function() end
encodeJson = function() return '{}' end
decodeJson = function() return {} end
sampAddChatMessage = function() end
isPauseMenuActive = function() return false end
PLAYER_PED = 1
sampGetPlayerIdByCharHandle = function() return true, 0 end
sampGetPlayerNickname = function() return 'Tester' end

local function loadmod(name)
  local f, err = loadfile('src/' .. name)
  assert(f, err)
  f()
end
loadmod('00_core.lua')
loadmod('05_items.lua')
loadmod('10_market.lua')
loadmod('15_prices.lua')
loadmod('05_trades.lua')
loadmod('20_presets.lua')

sampGetCurrentServerName = function() return 'Arizona Mobile II' end
assert(DSP.detect_server() == 102, 'detect Mobile II')
sampGetCurrentServerName = function() return 'Arizona Mobile III' end
assert(DSP.detect_server() == 103, 'detect Mobile III')
sampGetCurrentServerName = function() return 'Arizona Mobile I' end
assert(DSP.detect_server() == 101, 'detect Mobile I')

DSP.ui = { search = '', page = 1 }
DSP.settings.only_profit = false
DSP.settings.liquid = false
DSP.settings.sort = 1

local payload = { shops = {
  { owner = 'A', shop_num = '1', server_id = 102, updated_at = 100, sell_slots = {
      { name = 'Item', price = 200, qty = 1, ench = 0 },
      { name = 'Item', price = 100, qty = 2, ench = 13 },
    }, buy_slots = {
      { name = 'Item', price = 390, qty = 1, ench = 0 },
      { name = 'Item', price = 500, qty = 1, ench = 13 },
    } },
  { owner = 'B', shop_num = '2', server_id = 102, updated_at = 200, sell_slots = {
      { name = 'Item', price = 180, qty = 1, ench = 0 },
    }, buy_slots = {
      { name = 'Item', price = 300, qty = 2, ench = 0 },
    } },
} }
DSP.market.rebuild(payload, 102)
assert(DSP.market.state.shops == 2, 'shops')
assert(DSP.market.state.offers == 6, 'offers ' .. DSP.market.state.offers)
assert(#DSP.market.state.rows == 2, 'rows ' .. #DSP.market.state.rows)

local r0 = DSP.market.row_for('Item', 0)
assert(r0, 'row +0')
assert(r0.sell.best == 180, 'sell min ' .. tostring(r0.sell.best))
assert(r0.buy.best == 390, 'buy max ' .. tostring(r0.buy.best))
assert(r0.profit == 210, 'profit ' .. tostring(r0.profit))
assert(r0.profit_med > 0, 'profit med sign')
assert(r0.sell.count == 2 and r0.buy.count == 2, 'counts')

local r13 = DSP.market.row_for('Item', 13)
assert(r13, 'row +13')
assert(r13.sell.best == 100 and r13.buy.best == 500, 'ench prices')
assert(r13.profit == 400, 'ench profit')

assert(DSP.market.buy_target(r0, 10) == 343, 'buy target ' .. DSP.market.buy_target(r0, 10))
assert(DSP.market.sell_target(r0, 2) == 176, 'sell target ' .. DSP.market.sell_target(r0, 2))

DSP.auto = {}
local row = r0
assert(DSP.presets.add(row, 'buy'))
assert(#DSP.settings.buy_preset.items == 1)
local it = DSP.settings.buy_preset.items[1]
assert(it.price == 343 and it.key == row.key)
assert(DSP.presets.add(row, 'buy'))
assert(#DSP.settings.buy_preset.items == 1, 'dedup')

print('core tests: ok')
