-- v2.9.16 OTA compatibility: allow only the active internal sell worker to
-- request a fresh /mm inventory snapshot; never reset preferences or UI state.
-- Standalone 2.9.16 implements this directly in src/40_auto.lua.
local A=DSP.auto
if not (A and type(A.scan_inventory)=='function') then
    error('inventory scanner not available')
end
if not A._scan_refresh_2916 then
    local old_scan=A.scan_inventory
    A.scan_inventory=function(internal)
        if internal~=true or not A.sell_running then return old_scan(internal) end
        -- 2.9.15 scans blocked whenever sell_running was true. Temporarily
        -- release that gate ONLY to start a scan; restore before yielding.
        A.sell_running=false
        local ok,result=pcall(old_scan)
        A.sell_running=true
        if not ok then error(result) end
        return result~=false
    end
    A._scan_refresh_2916=true
end
-- Reload src/41_trade_listing.lua after this shim, then reapply the
-- existing v2.9.12 stock-aware wrapper around the refreshed sale worker.
A._trade_2914_replace_listing=true
return true
