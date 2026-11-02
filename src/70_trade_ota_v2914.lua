-- 2.9.14 OTA migration for clients installed before the Halloween protocol fix.
-- New standalone builds already contain the equivalent source implementations.
-- This module runs once after the 2.9.13 UI/stock overlays are installed.
local A, L = DSP.auto, DSP.live
if not (A and A.helpers and L and type(A.on_dialog)=='function'
    and type(A.start_sell)=='function' and type(L.handle)=='function') then
    error('trade runtime unavailable for 2.9.14 migration')
end

local h = A.helpers
if type(A.arm_trade_dialog) ~= 'function' then
    A.dialog_seq=A.dialog_seq or 0
    A.arm_trade_dialog=function(kind,item_name)
        A.trade_dialog_pending={kind=kind,item=h.base_name(item_name),seq=A.dialog_seq or 0}
    end
    local old_on_dialog=A.on_dialog
    A.on_dialog=function(id,style,title,b1,b2,body)
        A.dialog_seq=(A.dialog_seq or 0)+1
        local seq=A.dialog_seq
        local answer=old_on_dialog(id,style,title,b1,b2,body)
        local meta=A.dialog_meta
        if meta and meta.id==id then meta.seq=seq end
        if (A.sell_running or A.buy_running) and DSP.flog then
            local label=tostring((meta and meta.title)or title or ''):gsub('[\r\n]',' '):sub(1,80)
            DSP.flog(('TRADE incoming dialog id=%s style=%s title=%s bytes=%d'):format(
                tostring(id),tostring(style),label,#tostring(body or '')))
        end
        return answer
    end
    h.wait_trade_item_dialog=function(ids,item_name,timeout,kind)
        local elapsed,observed=0,''
        while elapsed<(timeout or 3200) do
            DSP.trade_runtime.pause(40)
            elapsed=elapsed+40
            if sampIsDialogActive() then
                local id=sampGetCurrentDialogId()
                local allowed=false
                for _,old_id in ipairs(ids or {}) do
                    if id==old_id then allowed=true;break end
                end
                local pending=A.trade_dialog_pending
                local meta=A.dialog_meta
                local fresh=kind=='sell' and pending and pending.kind==kind
                    and pending.item==h.base_name(item_name) and meta and meta.id==id
                    and (meta.seq or 0)>pending.seq
                    and (tonumber(meta.style)==1 or tonumber(meta.style)==3)
                if allowed or fresh then
                    local ok,body,title=h.trade_dialog_matches(id,item_name,kind)
                    observed=(title or '')..'\n'..(body or '')
                    if ok then
                        local stable=h.wait_text(id,360)
                        if sampIsDialogActive() and sampGetCurrentDialogId()==id then
                            local matched,final_body,final_title=h.trade_dialog_matches(id,item_name,kind,stable)
                            if matched then return id,final_body,final_title end
                        end
                    end
                end
            end
        end
        return nil,observed,''
    end
    -- The old listing closure captured the OLD wait helper. The OTA build
    -- reloads only the listing function and restores stock protection after it.
    A._trade_2914_replace_listing=true
end

if type(L.coalesce_packet) ~= 'function' then
    local function time_ms()
        if getGameTimer then
            local ok,value=pcall(getGameTimer)
            if ok and type(value)=='number' then return value end
        end
        return os.time()*1000
    end
    local function envelope(raw)
        local first=raw:find('%S')
        if not first then return 'other' end
        local opener=raw:sub(first,first)
        if opener~='{' and opener~='[' then return 'other' end
        local depth,quoted,escaped=0,false,false
        for i=first,#raw do
            local ch=raw:sub(i,i)
            if quoted then
                if escaped then escaped=false
                elseif ch=='\\' then escaped=true
                elseif ch=='"' then quoted=false end
            elseif ch=='"' then quoted=true
            elseif ch=='{' or ch=='[' then depth=depth+1
            elseif ch=='}' or ch==']' then
                depth=depth-1
                if depth<0 then return 'invalid' end
                if depth==0 and raw:sub(i+1):find('%S') then return 'invalid' end
            end
        end
        if depth>0 or quoted then return 'partial' end
        return depth==0 and 'complete' or 'invalid'
    end
    L._json_fragments=L._json_fragments or {}
    L.JSON_FRAGMENT_MAX=1048576
    L.JSON_FRAGMENT_TTL_MS=3500
    L.coalesce_packet=function(iface,sub,raw,ms)
        if type(raw)~='string' then return raw end
        if not (iface==52 and sub==2 or iface==60 and (sub==0 or sub==1)) then
            return raw
        end
        ms=ms or time_ms()
        local key=tostring(iface)..':'..tostring(sub)
        local pending=L._json_fragments[key]
        if pending and (ms-pending.at<0 or ms-pending.at>L.JSON_FRAGMENT_TTL_MS) then
            L._json_fragments[key]=nil
            pending=nil
            if DSP.flog then DSP.flog('LIVE JSON partial expired '..key)end
        end
        if pending and envelope(raw)=='complete' then
            L._json_fragments[key]=nil
            pending=nil
            if DSP.flog then DSP.flog('LIVE JSON partial superseded '..key)end
        end
        local merged=pending and (pending.data..raw) or raw
        if #merged>L.JSON_FRAGMENT_MAX then
            L._json_fragments[key]=nil
            if DSP.flog then DSP.flog('LIVE JSON partial limit exceeded '..key..' bytes='..#merged)end
            return nil
        end
        local state=envelope(merged)
        if state=='partial' then
            L._json_fragments[key]={data=merged,at=ms}
            return nil
        end
        L._json_fragments[key]=nil
        if state=='invalid' then
            if DSP.flog then DSP.flog('LIVE JSON invalid envelope '..key..' bytes='..#merged)end
            return nil
        end
        return merged
    end
    -- The original Samp packet callback retains its L table reference and
    -- dynamically invokes L.handle. Wrap that entry point rather than
    -- registering a second onReceivePacket handler.
    local old_handle=L.handle
    L.handle=function(iface,sub,raw)
        local complete=L.coalesce_packet(iface,sub,raw)
        if complete~=nil then return old_handle(iface,sub,complete)end
    end
end
return true
