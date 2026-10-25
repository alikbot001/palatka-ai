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
sampRegisterChatCommand = function() end
sampSendChat = function(cmd) _G.last_chat = cmd end
sampIsDialogActive = function() return false end
sampGetCurrentDialogId = function() return -1 end
sampGetDialogText = function() return '' end
sampSendDialogResponse = function(id, btn, idx, text) _G.last_resp = { id=id, btn=btn, idx=idx, text=text } end
wait = function(ms) end
lua_thread = { create = function(fn) fn() end }

local function loadmod(name)
  local f, err = loadfile('src/' .. name)
  assert(f, err)
  f()
end
loadmod('00_core.lua')
loadmod('10_market.lua')
loadmod('20_presets.lua')
loadmod('40_auto.lua')

local text = '[12] Item {FFFFFF}[2 шт]\r\n[13] Other {FFFFFF}[1 шт]\r\nСледующая страница'
DSP.auto.scanning = true
local intercept = DSP.auto.on_dialog(25494, 0, 'Инвентарь', '', '', text)
assert(intercept == true, 'intercept')
assert(#DSP.auto.inv == 2, 'inv groups ' .. #DSP.auto.inv)
assert(DSP.auto.inv[1].name == 'Item' and DSP.auto.inv[1].count == 2)
assert(DSP.auto.inv[1].stacks[1].slot == 12)
assert(_G.last_resp and _G.last_resp.btn == 1 and _G.last_resp.idx == 1, 'next page response')

DSP.auto.scanning = true
DSP.auto.inv = {}
DSP.auto.on_dialog(25494, 0, 'Инвентарь', '', '', '[12] Item {FFFFFF}[2 шт]')
assert(DSP.auto.scanning == false, 'scan finished')
assert(DSP.auto.inv_status:find('1 поз.'), DSP.auto.inv_status)

DSP.settings.sell_preset.items = {
  { key = 'item|0', name = 'Item', ench = 0, price = 500, qty = 2, enabled = true },
}
DSP.auto.inv = { { name = 'Item', count = 2, stacks = { { slot = 12, count = 2 } } } }
DSP.settings.dry_run = true
DSP.auto.start_sell()
assert(not DSP.auto.sell_running, 'sell stopped')
assert(_G.last_chat == '/mm', 'post-scan /mm')

print('auto tests: ok')
