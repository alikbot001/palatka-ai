-- Presentation tombstones preserve the original accounting and reward evidence.
local C=DSP.craglog
local hidden,serial={},0
local function part(value)
    value=tostring(value or '')
    return tostring(#value)..':'..value
end
function C.event_key(e)
    if type(e)~='table' then return nil end
    if e.id then return 'id:'..tostring(e.id) end
    local fields={'type','kind','ts','raw','partner','direction','item_name','item','qty','count','ench',
        'label','source','price','amount','cash','money_get','money_give','total_get','total_give','profit','owner','shop_num'}
    local out={'legacy'}
    for _,key in ipairs(fields) do out[#out+1]=part(e[key]) end
    for _,side in ipairs({'items_get','items_give'}) do
        out[#out+1]=side
        for _,item in ipairs(e[side] or {}) do
            out[#out+1]=part(item.name)..part(item.qty)..part(item.ench)
        end
    end
    return table.concat(out,'|')
end
function C.new_event_id(ts)
    serial=serial+1
    return 'journal-'..tostring(ts or os.time())..'-'..serial
end
function C.event_visible(e)
    if type(e)~='table' or e.type=='journal_deleted' then return false end
    local key=e.type=='payday_detail' and ('id:'..tostring(e.payday_id)) or C.event_key(e)
    return not hidden[key]
end
local function invalidate()
    C.visibility_revision=(C.visibility_revision or 0)+1
    if DSP.rewards and DSP.rewards.invalidate then DSP.rewards.invalidate() end
end
function C.delete_event(e)
    local key=C.event_key(e)
    if not key then return false,'нет записи' end
    if hidden[key] then return true end
    local ok,raw=pcall(encodeJson,{type='journal_deleted',event_key=key,ts=os.time()})
    if not ok or type(raw)~='string' then C.last_error='JSON encoding error';return false,C.last_error end
    local f,err=io.open(DSP.events_log_path,'a')
    if not f then C.last_error=err;return false,err end
    local wrote,why=f:write('\n',raw,'\n');local closed,close_err=f:close()
    if not wrote or not closed then C.last_error=why or close_err;return false,C.last_error end
    hidden[key]=true;invalidate();C.last_error=nil
    return true
end
function C.visible_trades(period,from)
    local out={count=0,profit=0,cash_get=0,cash_give=0}
    for _,e in pairs(DSP.settings.trades or {}) do
        if e.type=='trade' and (tonumber(e.ts) or 0)>=from and C.event_visible(e) then
            out.count=out.count+1;out.profit=out.profit+(tonumber(e.profit) or 0)
            out.cash_get=out.cash_get+(tonumber(e.money_get) or 0)
            out.cash_give=out.cash_give+(tonumber(e.money_give) or 0)
        end
    end
    return out
end
local f=io.open(DSP.events_log_path,'r')
if f then
    for line in f:lines() do
        local ok,row=pcall(decodeJson,line)
        if ok and type(row)=='table' and row.type=='journal_deleted' and row.event_key then hidden[row.event_key]=true end
    end
    serial=f:seek('end') or 0;f:close()
end
invalidate()
return true
