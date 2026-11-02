-- Restore the 2.9.12 stock limit around a reloaded 2.9.14 sale worker.
-- Existing validate/totals wrappers remain installed; do not wrap them twice.
local A,S=DSP.auto,DSP.sell_stock_guard
if not A then error('missing auto engine') end
if not A._trade_2914_replace_listing then return true end
if not S or type(S.plan)~='function' then
    error('sell stock guard missing; refusing to enable unguarded sell')
end
local underlying=A.start_sell
A.start_sell=function(...)
    local preset=DSP.settings and DSP.settings.sell_preset
    local changes,summary=S.plan(type(preset)=='table' and preset.items or nil,A.inv)
    local restore={}
    for i,change in ipairs(changes or {}) do
        local row=change.row
        restore[i]={row=row,qty=row.qty,enabled=row.enabled}
        if change.qty>0 then row.qty=change.qty else row.enabled=false end
    end
    local ok,result=pcall(underlying,...)
    for i=#restore,1,-1 do
        local prior=restore[i]
        prior.row.qty=prior.qty
        prior.row.enabled=prior.enabled
    end
    if not ok then
        if DSP.flog then DSP.flog('SELL 2.9.14 launch: '..tostring(result))end
        if DSP.notify then DSP.notify('Sale launch failed; check log')end
        return false
    end
    if result and summary and (summary.adjusted>0 or summary.skipped>0) and DSP.add_log then
        DSP.add_log('Sale adapted to stock: '..summary.planned..' / '..summary.requested..
            '; reduced '..summary.adjusted..', absent '..summary.skipped)
    end
    return result
end
A._trade_2914_replace_listing=nil
return true
