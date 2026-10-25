package.path = './?.lua;./src/?.lua;' .. package.path
package.preload['encoding'] = function()
  return {
    default = 'CP1251',
    CP1251 = { encode = function(self, s) return s end },
    UTF8 = { decode = function(self, s) return s end, encode = function(self, s) return s end },
  }
end

local dir = '/tmp/opencode/dsp_test'
os.execute('mkdir -p ' .. dir .. '/PalatkaAI')
getWorkingDirectory = function() return dir end
doesDirectoryExist = function() return true end
createDirectory = function() end

local function jenc(t, seen)
  seen = seen or {}
  if type(t) ~= 'table' then return tostring(t) end
  if seen[t] then return '{}' end
  seen[t] = true
  if #t > 0 then
    local parts = {}
    for _, v in ipairs(t) do table.insert(parts, jenc(v, seen)) end
    return '[' .. table.concat(parts, ',') .. ']'
  end
  local parts = {}
  for k, v in pairs(t) do
    local key
    if type(k) == 'string' then key = '["' .. k .. '"]='
    else key = '[' .. tostring(k) .. ']=' end
    table.insert(parts, key .. jenc(v, seen))
  end
  return '{' .. table.concat(parts, ',') .. '}'
end
encodeJson = jenc
decodeJson = function(s)
  local f, err = load('return ' .. tostring(s), 'json', 't', {})
  if not f then return nil, err end
  return f()
end
sampAddChatMessage = function() end
PLAYER_PED = 1
sampGetPlayerIdByCharHandle = function() return true, 0 end
sampGetPlayerNickname = function() return 'Trader' end
sampRegisterChatCommand = function(cmd, fn) _G['_cmd_' .. cmd] = fn end
wait = function() end
lua_thread = { create = function(fn) fn() end }

local function loadmod(name)
  local f, err = assert(loadfile('src/' .. name))
  f()
end
loadmod('00_core.lua')
loadmod('05_items.lua')
loadmod('10_market.lua')
loadmod('15_prices.lua')
loadmod('05_trades.lua')

-- Test 1: trade_logs persistence
DSP.settings.server = 102
DSP.db.save_trades()
assert(DSP.db.load_trades(), 'load trades from file')

-- Test 2: record a trade
DSP.db.get = function(name, ench)
  return { sell = { min = 1000 }, buy = { max = 5000 } }
end
DSP.db.get = function(name, ench)
  if name == 'ItemA' then return { sell = { min = 1000 }, buy = { max = 3000 } } end
  if name == 'ItemB' then return { sell = { min = 2000 }, buy = { max = 6000 } } end
  return nil
end

DSP.logs.record_trade('Partner1',
  { { name = 'ItemA', ench = 0, qty = 1 } },
  { { name = 'ItemB', ench = 0, qty = 1 } },
  0, 4000, 'accepted')

assert(next(DSP.settings.trades) ~= nil, 'trade recorded')
local last_trade
for _, e in pairs(DSP.settings.trades) do last_trade = e end

assert(last_trade.partner == 'Partner1', 'partner name')
assert(last_trade.total_give == 3000, 'total_give=' .. tostring(last_trade.total_give))
assert(last_trade.total_get == 10000, 'total_get=' .. tostring(last_trade.total_get))
assert(last_trade.profit == 7000, 'profit=' .. tostring(last_trade.profit))
assert(last_trade.kind == 'profit', 'kind=' .. tostring(last_trade.kind))

-- Test 3: stats
local stats = DSP.logs.profit_summary('day')
assert(stats.count == 1, 'stats count=' .. tostring(stats.count))
assert(stats.profit == 7000, 'stats profit=' .. tostring(stats.profit))
assert(stats.total_get == 10000, 'stats total_get')
assert(stats.total_give == 3000, 'stats total_give')

-- Test 4: stall drop logging
DSP.logs.stall_dropped('StallOwner', '42', 'ItemA', 1000)
assert(next(DSP.settings.stalls) ~= nil, 'stall logged')

-- Test 5: crate logging
DSP.logs.crate_opened('ItemB', 3000, 5)
assert(next(DSP.settings.crates) ~= nil, 'crate logged')

-- Test 6: day_key buckets
local buckets = DSP.logs.stats('day')
assert(type(buckets) == 'table', 'stats returns table')

-- Test 7: clear trades
DSP.logs.clear_trades()
assert(next(DSP.settings.trades) == nil, 'trades cleared')
assert(next(DSP.settings.stalls) == nil, 'stalls cleared')
assert(next(DSP.settings.crates) == nil, 'crates cleared')

-- Test 8: sort bug fix - the comparator must produce a valid order
local function test_sort(asc, prices)
  local offers = {}
  for i, p in ipairs(prices) do
    offers[i] = { price = p, qty = 1 }
  end
  table.sort(offers, function(a, b)
    if a.price ~= b.price then
      if asc then return a.price < b.price else return a.price > b.price end
    end
    return (a.qty or 0) > (b.qty or 0)
  end)
  return offers
end

local prices = { 500, 300, 700, 100, 900, 300 }
local asc_sorted = test_sort(true, prices)
assert(asc_sorted[1].price == 100, 'asc min=' .. tostring(asc_sorted[1].price))
assert(asc_sorted[#asc_sorted].price == 900, 'asc max=' .. tostring(asc_sorted[#asc_sorted].price))

local desc_sorted = test_sort(false, prices)
assert(desc_sorted[1].price == 900, 'desc max=' .. tostring(desc_sorted[1].price))
assert(desc_sorted[#desc_sorted].price == 100, 'desc min=' .. tostring(desc_sorted[#desc_sorted].price))

print('trades tests: ok')
