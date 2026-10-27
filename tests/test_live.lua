package.path = './?.lua;./src/?.lua;' .. package.path
package.preload['encoding'] = function()
  return {
    default = 'CP1251',
    CP1251 = { encode = function(self, s) return s end },
    UTF8 = { decode = function(self, s) return s end, encode = function(self, s) return s end },
  }
end
local ffi = require('ffi')
local dir = '/tmp/opencode/dsp_live'
os.execute('mkdir -p ' .. dir)
os.execute('mkdir -p ' .. dir .. '/PalatkaAI')
local f = io.open(dir .. '/PalatkaAI/arz_items.json', 'w')
f:write('return { [22]="Бандана", [23]="Очки", [24]="Скин" }')
f:close()
getWorkingDirectory = function() return dir end
doesDirectoryExist = function() return true end
createDirectory = function() end
sampAddChatMessage = function() end
wait = function() end
lua_thread = { create = function(fn) fn() end }
addEventHandler = function() end

local fixtures = {
  ['{"name":"Ivan_Petrov","shopNum":75}'] = { name = 'Ivan_Petrov', shopNum = 75 },
  ['{"name":"Petr"}'] = { name = 'Petr' },
}
encodeJson = function() return '{}' end
decodeJson = function(s)
  if fixtures[s] then return fixtures[s] end
  local fn = loadstring(s)
  if fn then
    local ok, r = pcall(fn)
    if ok and type(r) == 'table' then return r end
  end
  return nil
end

local function loadmod(name)
  local fn, err = loadfile('src/' .. name)
  assert(fn, err)
  fn()
end
loadmod('00_core.lua')
loadmod('05_items.lua')
loadmod('10_market.lua')
loadmod('15_prices.lua')
loadmod('45_live.lua')

assert(DSP.items.load(), 'catalog')
assert(DSP.items.name(22) == 'Бандана', DSP.items.name(22))
local pid, pench = DSP.parse_item_id('22(4)', 0)
assert(pid == 22 and pench == 4, 'inline enchant ' .. tostring(pid) .. '/' .. tostring(pench))

DSP.market.state.updated = os.time()
DSP.db.set_rows({
  { key = 'бандана|0', name = 'Бандана', ench = 0, display = 'Бандана',
    sell = {min=1000,p25=1000,med=1200,p75=1500,max=2000,best=1000,count=5},
    buy = {min=700,max=900,med=800,p75=850,best=900,count=5} },
  { key = 'очки|0', name = 'Очки', ench = 0, display = 'Очки',
    sell = {min=500,p25=500,med=600,p75=700,max=800,best=500,count=4},
    buy = {min=300,max=450,med=400,p75=420,best=450,count=4} },
}, 102)
local e = DSP.db.get('Бандана', 0)
assert(e and e.sell.min == 1000, 'db get')
DSP.db.learn(22, 4, 1500, 'sell')
local le = DSP.db.learned[DSP.item_key('Бандана', 4)]
assert(le and le.name == 'Бандана', 'learned ench name')
assert(le.sell.min == 1500, 'learned ench min')

DSP.live.handle_shop_owner('{"name":"Ivan_Petrov","shopNum":75}')
assert(DSP.live.shop.owner == 'Ivan_Petrov', DSP.live.shop.owner)
assert(tostring(DSP.live.shop.num) == '75', tostring(DSP.live.shop.num))
DSP.live.handle(52, 2, '{"type":13,"item":22,"amount":1000,"slot":0,"enchant":0}')
DSP.live.handle(52, 2, '{"type":13,"item":23,"amount":500,"slot":1,"enchant":0}')
DSP.live.handle(52, 2, '{"type":28,"item":22,"amount":800,"slot":2,"enchant":0}')
assert(#DSP.live.shop.sell == 2, 'shop sell ' .. #DSP.live.shop.sell)
assert(#DSP.live.shop.buy == 1, 'shop buy ' .. #DSP.live.shop.buy)
assert(DSP.live.shop.sell[1].name == 'Бандана', DSP.live.shop.sell[1].name)
DSP.live.handle(60, 0, '{"type":13,"item":24,"amount":700,"slot":0}')
assert(#DSP.live.shop.sell == 2, 'same side/slot replaces the old offer: ' .. #DSP.live.shop.sell)
DSP.live.shop.menu_closed = os.time()
DSP.live.handle(60, 0, '{"type":13,"item":24,"amount":700,"slot":0}')
assert(#DSP.live.shop.sell == 1, 'new shop reset ' .. #DSP.live.shop.sell)
assert(DSP.live.shop.menu_closed == 0, 'menu_closed reset')
DSP.live.handle(60, 0, '{"type":13,"item":23,"amount":600,"slot":1}')
assert(#DSP.live.shop.sell == 2, 'second item')
DSP.live.shop.items_updated = os.time() - 11
DSP.live.handle(60, 0, '{"type":13,"item":24,"amount":700,"slot":0}')
assert(#DSP.live.shop.sell == 1, 'stale shop reset ' .. #DSP.live.shop.sell)
DSP.live.handle_shop_owner('{"name":"Other_Owner","shopNum":76}')
assert(DSP.live.shop.owner == 'Other_Owner', DSP.live.shop.owner)
assert(#DSP.live.shop.sell == 1, 'late owner must retain only pending new-generation items')
assert(#DSP.live.shop.buy == 0, 'owner change must reset old buys')
DSP.live.handle(52, 2, '{"type":13,"item":22,"amount":1100,"slot":0}')
assert(#DSP.live.shop.sell == 1, 'new owner items')

DSP.live.handle_trade(0, '{"name":"Petr"}')
assert(DSP.live.trade.partner == 'Petr', DSP.live.trade.partner)
DSP.live.handle(57, 2, '{"type":3,"item":22,"amount":2}')
DSP.live.handle(57, 2, '{"type":4,"item":23,"amount":1}')
DSP.live.handle(57, 6, '{"self":{"value":1000},"target":{"value":2000}}')
assert(#DSP.live.trade.give == 1 and DSP.live.trade.give[1].qty == 2, 'trade give')
assert(#DSP.live.trade.get == 1 and DSP.live.trade.get[1].qty == 1, 'trade get')
assert(DSP.live.trade.money_give == 1000 and DSP.live.trade.money_get == 2000, 'trade money')

DSP.live.parse_dialog_trade('Результат сделки с Petr',
  'Перед\nБандана x2\nПолуч\nОчки x1\n2000$')
assert(DSP.live.trade.money_get == 2000, 'dialog money')

DSP.ui = { d = 1.25 }

local im = {}
im.new = setmetatable({}, { __index = function(t, k)
  if k == 'char' then return setmetatable({}, { __index = function() return function() return ffi.new('char[128]') end end }) end
  if k == 'bool' then return function(v) local b=ffi.new('bool[1]'); b[0]=v and true or false; return b end end
  return function() return ffi.new('int[1]') end
end })
im.ImVec2 = function(x, y) return { x = x or 0, y = y or 0 } end
im.ImVec4 = function(r, g, b, a) return { r = r, g = g, b = b, a = a or 1 } end
im.Col = setmetatable({}, { __index = function() return 0 end })
im.WindowFlags = setmetatable({}, { __index = function() return 0 end })
im.Cond = setmetatable({}, { __index = function() return 0 end })
im.GetIO = function() return { DisplaySize = { x = 2340, y = 1080 } } end
im.Begin = function() return true end
im.BeginChild = function() return true end
im.Button = function() return false end
im.SmallButton = function() return false end
im.OnFrame = function() end
im.PushStyleColor = function() end
im.PopStyleColor = function() end
im.SetNextWindowFocus = function() end
im.SetNextWindowBgAlpha = function() end
im.SetNextWindowPos = function() end
im.SetNextWindowSize = function() end
im.Text = function() end
im.TextColored = function() end
im.TextDisabled = function() end
im.SameLine = function() end
im.Separator = function() end
im.End = function() end
im.EndChild = function() end
imgui = im
loadmod('50_overlay.lua')

assert(DSP.overlay.show_trade(), 'show trade')
DSP.overlay.draw_trade()
assert(DSP.overlay.show_shop(), 'show shop')
DSP.overlay.shop_tab = 1
DSP.overlay.draw_shop()
DSP.overlay.shop_tab = 2
DSP.overlay.draw_shop()
DSP.live.shop.menu_closed = os.time()
assert(not DSP.overlay.show_shop(), 'shop hidden after close')
DSP.live.shop.menu_closed = 0
assert(DSP.overlay.show_shop(), 'shop visible after reopen')
print('live tests: ok')
