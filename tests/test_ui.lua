package.path = './?.lua;./src/?.lua;' .. package.path
package.preload['encoding'] = function()
  return {
    default = 'CP1251',
    CP1251 = { encode = function(self, s) return s end },
    UTF8 = { decode = function(self, s) return s end, encode = function(self, s) return s end },
  }
end
local ffi = require('ffi')
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
wait = function() end
lua_thread = { create = function(fn) fn() end }

local function nilfn() return false end
local im = {}
im.new = setmetatable({}, { __index = function(t, k)
  if k == 'char' then return setmetatable({}, { __index = function() return function() return ffi.new('char[128]') end end }) end
  if k == 'bool' then return function(v) local b=ffi.new('bool[1]'); b[0]=v and true or false; return b end end
  return function(...) return ffi.new('int[1]') end
end })
im.ImVec2 = function(x, y) return { x = x or 0, y = y or 0 } end
im.ImVec4 = function(r, g, b, a) return { r = r, g = g, b = b, a = a or 1 } end
im.Col = setmetatable({}, { __index = function(t, k) return 0 end })
im.StyleVar = setmetatable({}, { __index = function(t, k) return 0 end })
im.WindowFlags = setmetatable({}, { __index = function(t, k) return 0 end })
im.SelectableFlags = setmetatable({}, { __index = function(t, k) return 0 end })
im.Cond = setmetatable({}, { __index = function(t, k) return 0 end })
im.GetContentRegionAvail = function() return { x = 900, y = 600 } end
im.GetWindowWidth = function() return 1100 end
im.GetWindowHeight = function() return 800 end
im.GetWindowSize = function() return { x = 1100, y = 760 } end
im.GetCursorPosY = function() return 10 end
im.CalcTextSize = function(s) return { x = #tostring(s or '') * 7, y = 14 } end
im.Begin = function() return true end
im.BeginChild = function() return true end
im.Button = function() return false end
im.SmallButton = function() return false end
im.Selectable = function() return false end
im.Checkbox = function() return false end
im.InputTextWithHint = function() return false end
im.InputText = function() return false end
im.InputTextMultiline = function() return false end       -- v1.2 Stage 3
im.SliderFloat = function() return false end             -- v1.2 Stage 1 (settings_tab)
im.IsItemActive = function() return false end            -- v1.2 Stage 3 (drag handle)
im.GetWindowPos = function() return { x = 28, y = 215 } end
im.InputTextFlags = { Multiline = 0x2000 }               -- v1.2 Stage 3
im.GetIO = function() return { DisplaySize = { x = 2340, y = 1080 }, MouseDelta = { x = 0, y = 0 } } end
im.OnFrame = function() end
im.PushStyleColor = function() end
im.PopStyleColor = function() end
im.PushStyleVarFloat = function() end
im.PushStyleVarVec2 = function() end
im.PopStyleVar = function() end
im.SetNextWindowSize = function() end
im.SetNextWindowPos = function() end
im.SetNextWindowBgAlpha = function() end
im.SetNextItemWidth = function() end
im.PushItemWidth = function() end
im.PopItemWidth = function() end
im.InputInt = function() end
im.SetColumnWidth = function() end
im.Columns = function() end
im.NextColumn = function() end
im.SameLine = function() end
im.Text = function() end
im.TextDisabled = function() end
im.TextColored = function() end
im.Separator = function() end
im.Spacing = function() end
im.NewLine = function() end
im.End = function() end
im.EndChild = function() end
im.OpenPopup = function() end
im.BeginPopup = function() end
imgui = im

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
DSP.auto = {
  buy_running = false, sell_running = false, inv_status = 'не сканирован',
  inv = {},
  status_text = function() return 'готов' end,
}
loadmod('30_ui.lua')
loadmod('35_screens.lua')
loadmod('55_craglog.lua')

local payload = { shops = {
  { owner = 'A', shop_num = '1', server_id = 102, updated_at = os.time(), sell_slots = {
      { name = 'Item', price = 200, qty = 1, ench = 0 },
      { name = 'Item', price = 100, qty = 2, ench = 13 },
    }, buy_slots = {
      { name = 'Item', price = 390, qty = 1, ench = 0 },
    } },
} }
DSP.market.rebuild(payload, 102)
DSP.ui.init()
DSP.ui.install()
DSP.ui.open = true
DSP.ui.open_ref[0] = true
DSP.ui.selected = DSP.market.state.rows[1].key
for tab = 1, 7 do
  DSP.ui.tab = tab
  DSP.ui.draw()
end
DSP.ui.selected = nil
DSP.ui.tab = 1
DSP.ui.draw()
print('ui tests: ok')
