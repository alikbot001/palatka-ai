package.path = './?.lua;./src/?.lua;' .. package.path
package.preload['encoding'] = function()
  return {
    default = 'CP1251',
    CP1251 = { encode = function(self, s) return s end },
    UTF8 = { decode = function(self, s) return s end, encode = function(self, s) return s end },
  }
end
package.preload['effil'] = function()
  return {
    thread = function(fn)
      return function(url)
        return {
          status = function() return 'completed' end,
          get = function() return { code = 200, body = 'return {shops={{server_id=102,owner="X",shop_num="1",sell_slots={{name="Item",price=100,ench=0,qty=1}}}}}', err = nil } end,
          cancel = function() end,
        }
      end
    end,
  }
end

local dir = '/tmp/opencode/dsp_http'
os.execute('mkdir -p ' .. dir .. '/PalatkaAI')
getWorkingDirectory = function() return dir end
doesDirectoryExist = function() return true end
createDirectory = function() end
sampAddChatMessage = function() end
sampGetPlayerIdByCharHandle = function() return true, 0 end
sampGetPlayerNickname = function() return 'Tester' end
sampGetCurrentPlayerName = function() return 'Tester' end
PLAYER_PED = 1
wait = function() end
lua_thread = { create = function(fn) fn() end }
encodeJson = function() return '{}' end
decodeJson = function(s)
  local fn = loadstring(s)
  if fn then
    local ok, r = pcall(fn)
    if ok and type(r) == 'table' then return r end
  end
  return nil
end

local function loadmod(name)
  local f, err = loadfile('src/' .. name)
  assert(f, err)
  f()
end
loadmod('00_core.lua')
loadmod('05_items.lua')
loadmod('10_market.lua')
loadmod('15_prices.lua')

DSP.market.pull(102)
assert(DSP.market.state.status == 'live', 'http pull status=' .. tostring(DSP.market.state.status) .. ' err=' .. tostring(DSP.market.state.error))
assert(#DSP.market.state.rows == 1, 'http pull rows=' .. tostring(#DSP.market.state.rows))

local lf = assert(io.open(dir .. '/PalatkaAI/market_102.json', 'w'))
lf:write('return {ts=1700000000, shops=1, offers=2, items={{name="Legacy",'
    .. 'sell={min=100,p25=100,med=120,max=150,n=2,qty=2},'
    .. 'buy={min=80,max=90,med=85,n=2,qty=2}}}}')
lf:close()
assert(DSP.market.load_cache(102), 'legacy cache load')
assert(#DSP.market.state.rows == 1, 'legacy rows=' .. tostring(#DSP.market.state.rows))
local le = DSP.db.get('Legacy', 0)
assert(le and le.sell.min == 100 and le.buy.max == 90, 'legacy db')
print('http tests: ok')
