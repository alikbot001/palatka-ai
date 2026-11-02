-- Halloween protocol regression tests. No real packets or trades are sent.
local function check(name, fn)
    local ok, err = pcall(fn)
    if not ok then error(name..': '..tostring(err)) end
    print('PASS '..name)
end

local active = nil
DSP = {
    add_log=function() end,
    flog=function() end,
    trade_runtime={
        pause=function() end,
        matches=function(haystack, needle)
            return haystack:find(needle, 1, true) ~= nil
        end,
    },
}
sampIsDialogActive=function() return active~=nil end
sampGetCurrentDialogId=function() return active and active.id or -1 end
sampGetDialogText=function() return active and active.body or '' end
sampGetDialogTitle=function() return active and active.title or '' end
assert(loadfile('src/40_auto.lua'))()
local function show(id, style, title, body)
    active={id=id,style=style,title=title,body=body}
    DSP.auto.on_dialog(id,style,title,'','',body)
end

check('fresh previously unknown sell input ID accepted', function()
    DSP.auto.sell_running=true
    DSP.auto.arm_trade_dialog('sell', 'Test item')
    show(28183,1,'Price for Test item','Enter price')
    local id = DSP.auto.helpers.wait_trade_item_dialog({26547}, 'Test item', 200, 'sell')
    assert(id==28183, 'fresh dialogue rejected')
end)
check('unarmed and stale unknown IDs are rejected', function()
    DSP.auto.trade_dialog_pending=nil
    local id=DSP.auto.helpers.wait_trade_item_dialog({26547}, 'Test item', 80, 'sell')
    assert(id==nil, 'unarmed dialog accepted')
    DSP.auto.arm_trade_dialog('sell', 'Test item') -- dialog predates arm
    id=DSP.auto.helpers.wait_trade_item_dialog({26547}, 'Test item', 80, 'sell')
    assert(id==nil, 'stale dialog accepted')
end)
check('unrelated menus and wrong item do not accept unknown ID', function()
    DSP.auto.arm_trade_dialog('sell', 'Test item')
    show(28184,2,'Price for Test item','Enter price')
    local id=DSP.auto.helpers.wait_trade_item_dialog({26547}, 'Test item', 80, 'sell')
    assert(id==nil, 'list dialog accepted')
    DSP.auto.arm_trade_dialog('sell', 'Test item')
    show(28185,1,'Other item','Unrelated input')
    id=DSP.auto.helpers.wait_trade_item_dialog({26547}, 'Test item', 80, 'sell')
    assert(id==nil, 'unrelated input accepted')
end)
check('legacy whitelisted price ID still accepted', function()
    active={id=26547,title='Price',body='Test item'}
    local id=DSP.auto.helpers.wait_trade_item_dialog({26547}, 'Test item', 200, 'sell')
    assert(id==26547)
end)

-- Coalescer is intentionally pure and can be tested without MonetLoader.
DSP={flog=function()end,settings={}}
assert(loadfile('src/45_live.lua'))()
local L=DSP.live
check('multipart JSON is complete before dispatch', function()
    L._json_fragments={}
    local full='{"type":13,"items":[{"item":7,"text":"one } inside text"},{"item":8}]}'
    local first,second=full:sub(1,34),full:sub(35)
    assert(L.coalesce_packet(52,2,first,1000)==nil)
    assert(L.coalesce_packet(52,2,second,1020)==full)
end)
check('independent JSON messages do not get glued', function()
    L._json_fragments={}
    local packet='{"type":13,"items":[]}'
    assert(L.coalesce_packet(52,2,packet,1000)==packet)
    assert(L.coalesce_packet(52,2,packet,1020)==packet)
    assert(L._json_fragments['52:2']==nil)
end)
check('fragment state isolated by interface and subpacket', function()
    L._json_fragments={}
    local partial='{"type":13,"items":['
    assert(L.coalesce_packet(52,2,partial,1000)==nil)
    assert(L.coalesce_packet(60,0,'{"type":28}',1010)=='{"type":28}')
    assert(L.coalesce_packet(52,2,']}',1020)==partial..']}')
end)
check('expired and superseded fragments are dropped', function()
    L._json_fragments={}
    assert(L.coalesce_packet(52,2,'{"type":',1000)==nil)
    local complete='{"type":28}'
    assert(L.coalesce_packet(52,2,complete,1010)==complete)
    assert(L._json_fragments['52:2']==nil)
    assert(L.coalesce_packet(52,2,'{"type":',2000)==nil)
    assert(L.coalesce_packet(52,2,complete,6000)==complete)
end)
check('oversized fragments are rejected and cleared', function()
    L._json_fragments={}
    local old=L.JSON_FRAGMENT_MAX
    L.JSON_FRAGMENT_MAX=24
    assert(L.coalesce_packet(52,2,'{"items":[',1000)==nil)
    assert(L.coalesce_packet(52,2,string.rep('x',30),1010)==nil)
    assert(L._json_fragments['52:2']==nil)
    L.JSON_FRAGMENT_MAX=old
end)
print('Halloween trade regression suite: OK')
