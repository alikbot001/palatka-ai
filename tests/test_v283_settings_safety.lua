-- Users' settings survive updates, unknown fields, and failed writes.
local path=os.tmpname()
os.remove(path)
local function serialize(data)
 return string.format('v=%d;name=%s;switch=%s;unknown=%s',
   tonumber(data.version) or 0,tostring(data.name or ''),
   tostring(data.auto_shop_scan),tostring(data.future_setting or ''))
end
function encodeJson(data)return serialize(data)end
function decodeJson(raw)
 local v,name,sw,extra=raw:match('^v=(%d+);name=([^;]*);switch=(%a+);unknown=(.*)$')
 if not v then error('not valid')end
 return {version=tonumber(v),name=name,auto_shop_scan=(sw=='true'),future_setting=extra}
end
local function read(file)
 local f=io.open(file,'rb')
 if not f then return nil end
 local data=f:read('*a');f:close();return data
end
local function write(file,data)
 local f=assert(io.open(file,'wb'));assert(f:write(data));assert(f:close())
end
local initial={version=1,name='LRC',auto_shop_scan=false,future_setting='KEEP'}
local original_bytes=serialize(initial)
write(path,encodeJson(initial))
DSP={settings_path=path,settings=initial,save_settings=function()error('old writer used')end,flog=function()end}
dofile('src/00a_settings_safety.lua')
local G=DSP.settings_safety
assert(G.installed)
assert(read(path..'.checkpoint_v283')==original_bytes)
-- User changes a preference. Only the old copy goes to .bak.
DSP.settings.version=2
DSP.settings.name='LRC New'
assert(DSP.save_settings())
assert(read(path)==serialize(DSP.settings))
assert(read(path..'.bak')==original_bytes)
assert(DSP.settings.auto_shop_scan==false and DSP.settings.future_setting=='KEEP')
-- User changes another preference; rotate backups.
DSP.settings.version=3
DSP.settings.auto_shop_scan=true
assert(DSP.save_settings())
assert(read(path..'.bak.previous')==original_bytes)
assert(read(path..'.bak'):find('v=2;',1,true))
-- Even corrupt main settings must never be silently overwritten by defaults.
write(path,'{ broken JSON')
DSP.settings.version=4
local ok,err=DSP.save_settings()
assert(not ok and tostring(err):find('preserved'))
assert(read(path)=='{ broken JSON')
assert(read(path..'.bak'):find('v=2;',1,true))
assert(read(path..'.checkpoint_v283')==original_bytes)
for _,suffix in ipairs({'','.bak','.bak.previous','.checkpoint_v283','.safe_new','.old'}) do
 os.remove(path..suffix)
end
print('PASS settings safety: checkpoints, preserved fields, backups and corruption guard')
