-- v2.9.5: skip full inventory signature/loot reconciliation on every stats frame.
local C=DSP.craglog
if not C or C._stats_render_cache_v295 then return true end
C._stats_render_cache_v295=true
local original=C.drop_sales_stats
if type(original)~='function' then return true end
local cache={}
function C.drop_sales_stats(period,query)
    local a=DSP.auto or{}
    local inv=a.inv or{}
    local key=table.concat({
        tostring(period or'day'),tostring(query or''),
        tostring(C.history_revision or 0),tostring(C.visibility_revision or 0),
        tostring(DSP.logs and DSP.logs.revision or 0),
        tostring(DSP.rewards and DSP.rewards.sequence or 0),
        tostring(inv),tostring(#inv),tostring(a.inv_status or''),
        tostring(a.scanning),tostring(math.floor(os.time()/2))
    },'|')
    if cache.key==key then return cache.result end
    local result=original(period,query)
    cache={key=key,result=result}
    return result
end
return true
