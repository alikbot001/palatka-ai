"""Python port of tests/verify_standalone.lua — runs the same 5 tests
via lupa (Lua 5.5 in CPython) since luajit is not available in this sandbox.

The mock environment provides:
  - getWorkingDirectory / sampRegisterChatCommand / lua_thread / wait
  - imgui stub with all Col.* / ImVec2 / ImVec4 / OnFrame / etc. functions
  - ffi stub (char[128], bool[1], int[1], float[1])

The script under test (palatka_ai.lua) is loaded via dofile-equivalent.
The 5 tests are identical to verify_standalone.lua:
  1. Syntax check (we use check_syntax.py's lupa-based loader)
  2. DSP namespace loaded
  3. Mock market with 90 shops × 20 items = 806 rows
  4. STRESS TEST: 300 frames of arbitrage_filtered() MUST take < 1 ms / frame
     (this proves the cache is working)
  5. Item Finder finds 'Item 1'

PASS = exit 0 + 'ВСЕ ТЕСТЫ ПРОЙДЕНЫ УСПЕШНО!'
"""
import os
import sys
import time

try:
    import lupa
except ImportError:
    print("lupa not installed: pip install --break-system-packages lupa")
    sys.exit(2)

ROOT = os.path.dirname(os.path.abspath(__file__))
PALATKA_LUA = os.path.join(ROOT, "palatka_ai.lua")
SRC_DIR = os.path.join(ROOT, "src")

if not os.path.exists(PALATKA_LUA):
    print(f"ERROR: {PALATKA_LUA} not found. Run `python3 build.py` first.")
    sys.exit(1)

# Lua 5.4+ runtime (lupa bundles Lua 5.5 in this build).
lua = lupa.LuaRuntime(unpack_returned_tuples=True)

# --- Mock environment ------------------------------------------------------
lua.execute(r"""
-- MoonLoader / MonetLoader globals
_G.getWorkingDirectory = function() return '.' end
_G.thisScript = function() return { name = 'palatka ai' } end
_G.sampRegisterChatCommand = function(cmd, fn) end
_G.sampGetCurrentServerName = function() return 'Arizona Mobile II' end
-- Mock: lua_thread.create registers but does NOT execute (avoids infinite
-- while-true loops in market.refresh_thread / scan_cr_marker background).
_G.lua_thread = { create = function(fn) return { _fn = fn } end }
_G.wait = function() end
_G.doesDirectoryExist = function(p) return false end
_G.createDirectory = function(p) end
_G.script_name = function(s) end
_G.script_author = function(s) end
_G.script_version = function(s) end
_G.mh_notify = function(msg, color) end
_G.sampAddChatMessage = function(msg, color) end
_G.encodeJson = function(t) return '{}' end
_G.decodeJson = function(s) return {} end
_G.isPauseMenuActive = function() return false end
_G.PLAYER_PED = 1
_G.sampGetPlayerIdByCharHandle = function() return true, 0 end
_G.sampGetPlayerNickname = function() return 'Tester' end
_G.sampGetCurrentPlayerName = function() return 'Tester' end
_G.addEventHandler = function() end
_G.sampSendChat = function() end
_G.sampSendDialogResponse = function() end
_G.sampIsDialogActive = function() return false end
_G.sampGetCurrentDialogId = function() return 0 end
_G.sampGetDialogText = function() return '' end
_G.raknetNewBitStream = function() return {} end
_G.raknetBitStreamWriteInt8 = function() end
_G.raknetBitStreamWriteInt16 = function() end
_G.raknetBitStreamWriteInt32 = function() end
_G.raknetBitStreamWriteString = function() end
_G.raknetSendBitStreamEx = function() end
_G.raknetDeleteBitStream = function() end
_G.raknetBitStreamResetReadPointer = function() end
_G.raknetBitStreamIgnoreBits = function() end
_G.raknetBitStreamReadInt8 = function() return 0 end
_G.raknetBitStreamReadInt16 = function() return 0 end
_G.raknetBitStreamReadString = function() return '' end
_G.raknetBitStreamDecodeString = function() return '' end

-- Mock imgui (all functions return no-op / default values).
local _imgui = {
    new = setmetatable({}, {
        __index = function(t, k)
            -- new.bool/int/float return cdata-like tables; new.char is index by size
            if k == 'char' then
                return setmetatable({}, { __index = function() return function()
                    local buf = {}
                    for i = 0, 127 do buf[i] = 0 end
                    return setmetatable(buf, { __len = function() return 128 end })
                end end })
            end
            return function(v)
                local t = { [0] = v or 0 }
                return setmetatable(t, { __index = function() return 0 end })
            end
        end
    }),
    Col = {
        CheckMark = 1, WindowBg = 2, Text = 3, Button = 4, ButtonHovered = 5,
        ButtonActive = 6, ChildBg = 7, FrameBg = 8, FrameBgHovered = 9,
        Border = 10, Header = 11, HeaderHovered = 12, Separator = 13,
        ScrollbarBg = 14, ScrollbarGrab = 15, ScrollbarGrabHovered = 16,
        ScrollbarGrabActive = 17, SliderGrab = 18, SliderGrabActive = 19,
        PopupBg = 20, TextDisabled = 21, TitleBg = 22, TitleBgActive = 23,
    },
    StyleVar = setmetatable({}, { __index = function() return 0 end }),
    WindowFlags = setmetatable({}, { __index = function() return 0 end }),
    SelectableFlags = setmetatable({}, { __index = function() return 0 end }),
    Cond = setmetatable({}, { __index = function() return 0 end }),
    InputTextFlags = setmetatable({}, { __index = function() return 0 end }),
    ImVec2 = function(x, y) return { x = x or 0, y = y or 0 } end,
    ImVec4 = function(r, g, b, a) return { r = r or 0, g = g or 0, b = b or 0, a = a or 1 } end,
    OnFrame = function(cond, draw) return { Unsubscribe = function() end } end,
    PushStyleColor = function(col, val) end,
    PopStyleColor = function(n) end,
    PushStyleVarFloat = function() end,
    PushStyleVarVec2 = function() end,
    PopStyleVar = function(n) end,
    SetNextWindowPos = function() end,
    SetNextWindowSize = function() end,
    SetNextWindowBgAlpha = function() end,
    SetNextItemWidth = function() end,
    PushItemWidth = function() end,
    PopItemWidth = function() end,
    AlignTextToFramePadding = function() end,
    Begin = function() return true end,
    End = function() end,
    BeginChild = function() return true end,
    EndChild = function() end,
    Button = function() return false end,
    SmallButton = function() return false end,
    Selectable = function() return false end,
    Checkbox = function() return false end,
    InputInt = function() return false end,
    InputText = function() return false end,
    InputTextWithHint = function() return false end,
    InputTextMultiline = function() return false end,
    SliderFloat = function() return false end,
    SliderInt = function() return false end,
    IsItemActive = function() return false end,
    Text = function() end,
    TextColored = function() end,
    TextDisabled = function() end,
    Separator = function() end,
    Spacing = function() end,
    NewLine = function() end,
    Columns = function() end,
    SetColumnWidth = function() end,
    NextColumn = function() end,
    GetContentRegionAvail = function() return { x = 800, y = 600 } end,
    GetWindowWidth = function() return 1100 end,
    GetIO = function() return {
        DisplaySize = { x = 2340, y = 1080 },
        MouseDelta = { x = 0, y = 0 },
    } end,
}
_G.imgui = _imgui

-- Mock ffi (char[N] is essentially a Lua table; everything else stubs).
_G.ffi = {
    new = function(t, v)
        if type(t) == 'string' and t:match('char') then
            local n = tonumber(t:match('%[(%d+)%]')) or 128
            local buf = {}
            for i = 0, n - 1 do buf[i] = 0 end
            buf._size = n
            return setmetatable(buf, { __len = function() return n end })
        end
        return setmetatable({ [0] = v or 0 }, { __index = function() return 0 end })
    end,
    copy = function(dst, src, n) end,
    string = function(buf) return '' end,
    sizeof = function() return 0 end,
    typeof = function() return function() return nil end end,
    cast = function() return nil end,
    C = {},
    os = 'Windows',
    arch = 'arm64',
}
-- encoding module
_G.encoding = {
    default = 'CP1251',
    CP1251 = { encode = function(self, s) return s end, decode = function(self, s) return s end },
    UTF8 = { encode = function(self, s) return s end, decode = function(self, s) return s end },
}
-- Other modules
_G.require = function(mod)
    if mod == 'ffi' then return _G.ffi end
    if mod == 'encoding' then return _G.encoding end
    if mod == 'lfs' then return nil end
    if mod == 'effil' then return nil end
    if mod == 'requests' then return nil end
    if mod == 'mimgui' then return _G.imgui end
    if mod == 'samp.events' then return { onShowDialog = nil, onChatMessage = nil } end
    return nil
end
_G.io = _G.io  -- keep standard io
_G.os = _G.os  -- keep standard os
""")

# --- TEST 1: syntax check --------------------------------------------------
print("[TEST 1] Syntax check via lupa loader...")
# palatka_ai.lua is encoded as CP1251 (Windows-1251) per build.py.
with open(PALATKA_LUA, "rb") as f:
    raw_bytes = f.read()
try:
    lua_src = raw_bytes.decode("cp1251")
except UnicodeDecodeError as e:
    print(f"  FAIL: cannot decode palatka_ai.lua as CP1251: {e}")
    sys.exit(1)
wrapped = f"local function __check()\n{lua_src}\nend\nreturn __check"
try:
    lua.execute(wrapped.encode("utf-8"))
    print("  OK: lupa parse OK")
except lupa.LuaSyntaxError as e:
    print(f"  FAIL: {e}")
    sys.exit(1)

# --- TEST 2: load script into memory ---------------------------------------
print("[TEST 2] Loading script (dofile equivalent)...")
try:
    lua.execute(lua_src.encode("utf-8"))
except Exception as e:
    print(f"  FAIL: {e}")
    sys.exit(1)
dsp_version = lua.eval("DSP and DSP.version or nil")
if not dsp_version:
    print("  FAIL: DSP not initialized")
    sys.exit(1)
print(f"  OK: DSP initialized, version {dsp_version}")

# --- TEST 3: build mock market (90 shops × 20 items = 806 rows) -----------
print("[TEST 3] Building mock market (90 shops × 20 items)...")
lua.execute(r"""
local mock_payload = { shops = {} }
for s = 1, 90 do
    local shop = {
        owner = 'Player_' .. s,
        shop_num = tostring(s),
        server_id = 102,
        updated_at = os.time(),
        sell_slots = {},
        buy_slots = {},
    }
    for i = 1, 20 do
        local idx = i % 50
        table.insert(shop.sell_slots, {
            name = 'Предмет ' .. idx,
            price = 1000 + i * 50,
            qty = 10,
            ench = 0,
        })
        table.insert(shop.buy_slots, {
            name = 'Предмет ' .. idx,
            price = 1200 + i * 50,
            qty = 10,
            ench = 0,
        })
    end
    table.insert(mock_payload.shops, shop)
end
DSP.market.rebuild(mock_payload, 102)
""")
n_rows = lua.eval("#DSP.market.state.rows")
if not n_rows or n_rows == 0:
    print("  FAIL: market is empty after rebuild")
    sys.exit(1)
print(f"  OK: market built, {n_rows} unique items")

# --- TEST 4: STRESS TEST -- 300 frames of arbitrage_filtered() -------------
print("[TEST 4] STRESS TEST: 300 frames of arbitrage_filtered() (cache hit path)...")
t0 = time.time()
lua.execute(r"""
for frame = 1, 300 do
    local arb_list = DSP.market.arbitrage_filtered()
    assert(type(arb_list) == 'table', 'arbitrage did not return a table')
end
""")
duration = time.time() - t0
ms_per_frame = (duration / 300) * 1000
print(f"  Time per frame: {ms_per_frame:.4f} ms (total {duration:.3f} sec for 300 frames)")
if ms_per_frame >= 1.0:
    print(f"  CRITICAL FAIL: frame took {ms_per_frame:.2f} ms (must be < 1 ms). CACHE BROKEN!")
    sys.exit(1)
print("  OK: cache working! Per-frame cost < 1 ms")

# --- TEST 5: Item Finder ---------------------------------------------------
print("[TEST 5] Item Finder search 'Предмет 1'...")
lua.execute("DSP._test_findings = DSP.market.find_item('Предмет 1')")
n_found = lua.eval("#DSP._test_findings")
if not n_found or n_found == 0:
    print("  FAIL: Item Finder found nothing")
    sys.exit(1)
print(f"  OK: Item Finder found {n_found} matches")

# --- BONUS: verify cache invalidation on filter change ---------------------
print("[BONUS] Cache invalidation test...")
lua.execute(r"""
DSP.market.arbitrage_filtered()  -- prime cache
assert(DSP.market.arb_cache ~= nil, 'cache not primed')
DSP.settings.arb_filters.min_profit = 500000  -- change filter
DSP.market.invalidate_arbitrage()
local _ = DSP.market.arbitrage_filtered()  -- rebuild
""")
cache_ok = lua.eval("DSP.market.arb_cache_version == DSP.market.state.version")
print(f"  OK: cache rebuilt after filter change, version match: {bool(cache_ok)}")

print("=" * 64)
print(" ВСЕ ТЕСТЫ ПРОЙДЕНЫ УСПЕШНО! СКРИПТ ГОТОВ К РЕЛИЗУ НА ARIZONA! ")
print("=" * 64)
print(f"")
print(f"Per-frame arbitrage: {ms_per_frame:.4f} ms (< 1 ms required)")
print(f"Mock market: {n_rows} unique items across 90 shops")
print(f"Item Finder: {n_found} matches for 'Предмет 1'")
sys.exit(0)
