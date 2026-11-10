-- Elapsed seconds for deadlines. CLOCK_MONOTONIC keeps suspend/low CPU and
-- system-clock corrections from changing the duration of a request.
return function(ffi)
    ffi.cdef[[
        int clock_gettime(int clock_id, void *time_value);
    ]]
    -- POSIX timespec on the supported Linux/Android ABI: time_t and long.
    -- An anonymous buffer also survives repeated initialization in one Lua VM.
    local value=ffi.new('long[2]')
    -- Another mod may already have declared clock_gettime with timespec*.
    -- A void pointer accepts either declaration without changing libc's ABI.
    local pointer=ffi.cast('void *',value)
    return function()
        if ffi.C.clock_gettime(1,pointer)~=0 then
            error('Palatka: CLOCK_MONOTONIC failed')
        end
        return tonumber(value[0])+tonumber(value[1])/1000000000
    end
end
