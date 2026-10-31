-- v2.9.5: avoid re-evaluating every stored trunk on every ImGui frame.
-- No data is discarded; a short expiry and market/snapshot changes invalidate.
local S=DSP.storage
if not S or S._render_cache_v295 then return true end
S._render_cache_v295=true
local base_evaluate=S.evaluate
local base_search=S.search_library
local values=setmetatable({},{__mode='k'})
local searches={}
local last_bucket=-1
local function generation()
    local state=DSP.market and DSP.market.state or{}
    local clock=os.time()
    local bucket=math.floor(clock/2)
    if last_bucket~=bucket then
        values=setmetatable({},{__mode='k'})
        searches={}
        last_bucket=bucket
    end
    return tostring(bucket)..':'..tostring(state.sid or 0)..':'..
        tostring(state.version or 0)..':'..tostring(S.snapshots)
end
function S.evaluate(snapshot,lookup)
    if lookup~=nil or type(snapshot)~='table' then return base_evaluate(snapshot,lookup)end
    local key=generation()..':'..tostring(snapshot.rows)..':'..
        tostring(snapshot.manual_prices)..':'..tostring(#(snapshot.rows or{}))
    local c=values[snapshot]
    if c and c.key==key then return c.result end
    local result=base_evaluate(snapshot)
    values[snapshot]={key=key,result=result}
    return result
end
if type(base_search)=='function' then
    function S.search_library(query,lookup)
        if lookup~=nil then return base_search(query,lookup)end
        local key=generation()..':'..tostring(query or'')
        local item=searches[key]
        if item then return item end
        local result=base_search(query)
        searches[key]=result
        return result
    end
end
return true
