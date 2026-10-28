-- Isolated SAMP/eFFIL network simulation; zero real HTTP calls.
package.path = './?.lua;./src/?.lua;' .. package.path
local simulated = {status=200, body='{ "shops": [] }', error=nil}
local pending = {}
local threads = {}
local created = 0
package.preload['encoding'] = function()
    return {default='CP1251',CP1251={encode=function(_, s)return s end},UTF8={
        decode=function(_,s)return s end,encode=function(_,s)return s end}}
end
package.preload['requests'] = function()
    return {request=function(method, url)
        assert(method=='GET')
        assert(type(url)=='string')
        if simulated.error then error(simulated.error) end
        return {status_code=simulated.status,text=simulated.body}
    end}
end
package.preload['effil'] = function()
    return {thread=function(worker)
        return function(url)
            created = created + 1
            local code, body, err = worker(url)
            local thread = {code=code,body=body,err=err,url=url}
            function thread:status()return 'completed' end
            function thread:get()return self.code,self.body,self.err end
            function thread:cancel()self.canceled=true end
            threads[#threads+1]=thread
            return thread
        end
    end}
end
wait=function()end
lua_thread={create=function(fn) pending[#pending+1]=fn end}
local function drain()
    local running=pending
    pending={}
    for _,fn in ipairs(running) do fn() end
end
local current_nick='Name_A'
sampGetPlayerIdByCharHandle=function()return true,1 end
sampGetPlayerNickname=function()return current_nick end
sampGetCurrentPlayerName=function()return current_nick end
PLAYER_PED=1
getWorkingDirectory=function()return '/tmp' end
doesDirectoryExist=function()return true end
createDirectory=function()end
encodeJson=function()return '{}' end
-- Tiny deterministic JSON decoder: purposefully only accepts the fixture payload.
decodeJson=function(s)
    if s == '{ "shops": [] }' then return {shops={}} end
    if s == '{"ok":false,"error":"denied"}' then return {ok=false,error='denied'} end
    if s == '{"not_shops":1}' then return {not_shops=1} end
    if s == 'corrupt' then error('invalid JSON') end
    return nil
end
local function mod(file) local f=assert(loadfile('src/'..file));f()end
mod('00_core.lua');mod('05_items.lua');mod('10_market.lua')
DSP.save_settings=function()end
DSP.market.save_cache=function()end
DSP.market.rebuild=function(payload,sid)
    assert(type(payload.shops)=='table')
    DSP.market.state.rows={}
    DSP.market.state.by_key={}
    DSP.market.state.version=(DSP.market.state.version or 0)+1
    DSP.market.state.status='live'
    DSP.market.state.sid=sid
end
local errors={}
DSP.add_log=function(...) end
DSP.flog=function(s)errors[#errors+1]=s end
assert(DSP.market.url(102):find('nick=Name_A',1,true))
current_nick='Name&A +Б'
local url=DSP.market.url(102)
assert(url:find('nick=Name%26A%20%2B',1,true), 'nickname URL encoded')
current_nick=''
assert(not DSP.market.url(102):find('&nick=',1,true),'no invented nickname')
current_nick='Name_A'
local ok,err
assert(DSP.market.pull(102,function(a,b)ok=a;err=b end))
drain()
assert(ok==true and err==nil and DSP.market.state.status=='live')
assert(DSP.market.state.last_http_code==200)
-- HTTP 403 must not be labeled a network timeout; preserve valid market snapshot.
DSP.market.state.rows={{name='stale'}}
simulated.status=403
ok=nil
DSP.market.pull(102,function(a,b)ok=a;err=b end)
drain()
assert(ok==false and err:find('HTTP 403',1,true),'raw status surfaces to user')
assert(DSP.market.state.status=='cache' and #DSP.market.state.rows==1)
assert(DSP.market.state.next_auto_retry>os.time()+800)
assert(DSP.market.state.last_http_code==403)
-- Manual retries must work even during automatic backoff.
simulated.status=200
DSP.market.pull(102);drain()
assert(DSP.market.state.status=='live' and DSP.market.state.failures==0)
-- 429 must back off, and not clobber same-server state.
simulated.status=429
DSP.market.state.rows={{name='kept'}}
DSP.market.pull(102);drain()
assert(DSP.market.state.next_auto_retry>=os.time()+290)
assert(DSP.market.state.rows[1].name=='kept')
-- The response from an old server cannot overwrite the current server.
simulated.status=200
local stale_ok=nil
DSP.market.pull(102,function(v)stale_ok=v end)
DSP.market.pull(103)
drain()
assert(DSP.market.state.sid==103 and DSP.market.state.status=='live')
assert(stale_ok==nil,'old request callback must be discarded')
-- Even HTTP 200 can carry a failure or an incompatible body.
for _,body in ipairs({'{"ok":false,"error":"denied"}', '{"not_shops":1}', 'corrupt'}) do
    simulated.body=body
    DSP.market.pull(103);drain()
    assert(DSP.market.state.status=='error', 'invalid payload is not live')
    assert(DSP.market.state.error and #DSP.market.state.error>0)
end
simulated.body='{ "shops": [] }'
simulated.status=200
DSP.market.pull(103);drain()
assert(DSP.market.state.status=='live')
-- Transport failure is distinct from server JSON error.
simulated.error='TLS handshake failed'
DSP.market.pull(103);drain()
assert(DSP.market.state.status=='error' and DSP.market.state.error:find('TLS',1,true))
print('v226 network response, fallback, errors, backoff and isolation: PASS')
