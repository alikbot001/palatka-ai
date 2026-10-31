-- Cooperative waits use elapsed scheduler time, not CPU time (os.clock).
DSP.trade_runtime = {}
local R = DSP.trade_runtime
local owners = setmetatable({}, {__mode = 'k'})
R.generation = 0
R.state = R.state or {kind='idle',phase='idle',detail='',at=0,generation=0}
function R.transition(kind,phase,detail)
    R.state={kind=tostring(kind or R.state.kind or 'idle'),phase=tostring(phase or 'idle'),
        detail=tostring(detail or ''),at=os.time(),generation=R.generation}
    if DSP.auto then DSP.auto.trade_state=R.state end
    if DSP.flog then DSP.flog('TRADE STATE '..R.state.kind..'/'..R.state.phase..(R.state.detail~='' and (' '..R.state.detail) or '')) end
    return R.state
end
function R.snapshot() return R.state end
local main = {}
local function owner() return coroutine.running() or main end
function R.pause(ms)
    local generation = owners[owner()]
    wait(ms)
    if generation and generation ~= R.generation then error('trade_cancelled', 0) end
end
function R.cancel() R.generation = R.generation + 1;R.transition(R.state.kind,'cancelled','user/runtime cancel') end
function R.spawn(kind, fn)
    R.generation = R.generation + 1
    local generation = R.generation
    DSP.auto.progress = {kind = kind, done = 0, total = 0, failed = 0, dry = 0}
    R.transition(kind,'start','generation='..tostring(generation))
    lua_thread.create(function()
        if generation ~= R.generation then return end
        owners[owner()] = generation
        local ok, err = pcall(fn)
        owners[owner()] = nil
        if generation == R.generation then
            DSP.auto[kind .. '_running'] = false
            if not ok then
                R.transition(kind,'failed',tostring(err))
                DSP.auto.progress.failed = DSP.auto.progress.failed + 1
                DSP.auto.status = 'ошибка: ' .. tostring(err)
                if sampIsDialogActive() then
                    local closed, close_err = pcall(sampSendDialogResponse, sampGetCurrentDialogId(), 0, 0, '')
                    if not closed then DSP.add_log(tostring(close_err), 'error') end
                end
                DSP.add_log(DSP.auto.status, 'error')
            else
                R.transition(kind,'done','completed')
            end
        end
    end)
end
function R.positive(n)
    n = tonumber(n)
    return n and n == n and n > 0 and n % 1 == 0 and n <= 9007199254740991
end
function R.matches(text, name)
    -- Require the entire item name; matching just the first word can list another item.
    local want = tostring(name)
    local start = 1
    while true do
        local a, b = tostring(text):find(want, start, true)
        if not a then return false end
        local before, after = text:sub(a - 1, a - 1), text:sub(b + 1, b + 1)
        local tail = text:sub(b + 1):match('^%s*(.-)%s*$')
        local field = tail == '' or tail:find('^Количество') or tail:find('^количество')
            or tail:find('^Цена') or tail:find('^цена') or tail:find('^quantity') or tail:find('^price')
        local suffix = after == '' or after:match('[:»".,\t\r\n]') or (after:match('%s') and field)
        if (a == 1 or before:match('[%s:«"\t]')) and
            suffix then return true end
        start = b + 1
    end
end
