-- v2.9.15: own-stall inventory can be acknowledged by iface60/sub1.
-- Market Helper's mobile packet observer uses this native event as a shop-ready
-- signal; older Arizona clients also send iface52/sub2/type1 (handled in 45_live).
-- Accept only while waiting for the explicitly requested own-stall inventory.
local A,L,R=DSP.auto,DSP.live,DSP.trade_runtime
if not (A and L and R and type(L.handle)=='function') then
    error('2.9.15 stall observer dependencies unavailable')
end
if L._stall_ack_2915 then return true end
local previous=L.handle
L.handle=function(iface,sub,raw)
    if tonumber(iface)==60 and tonumber(sub)==1
        and A.sell_running==true and R.state and R.state.kind=='sell'
        and R.state.phase=='wait_inventory'
        and type(raw)=='string' and #raw>2
        and (raw:find('"name"',1,true) or raw:find('"owner"',1,true)
             or raw:find('"nick"',1,true)) then
        A.stall_inventory_ready=true
        A.stall_inventory_seen_at=os.time()
        if DSP.flog then DSP.flog('TRADE stall inventory ready (iface60/sub1)')end
    end
    return previous(iface,sub,raw)
end
L._stall_ack_2915=true
return true
