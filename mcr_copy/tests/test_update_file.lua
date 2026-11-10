local replace=assert(loadfile('mcr_copy/src/update_file.lua'))()
local path=os.tmpname()..'.lua'
local function put(p,bytes)local f=assert(io.open(p,'wb'));assert(f:write(bytes));assert(f:close())end
local function read(p)local f=assert(io.open(p,'rb'));local s=f:read('*a');f:close();return s end
put(path,'original')
local ok,why=replace(path,'next')
assert(ok,why);assert(read(path)=='next'and read(path..'.crr-backup')=='original')
local installed,err=replace(path,'broken',{rename=function(from,to)
 if to==path then return nil,'rename denied'end
 return os.rename(from,to)
end})
assert(not installed and err:find('rename denied',1,true))
assert(read(path)=='next'and read(path..'.crr-backup')=='next','original lost on replacement failure')
for _,suffix in ipairs({'','.crr-backup','.crr-new','.crr-backup.tmp'})do os.remove(path..suffix)end
print('Staged file install/backup/failed rename preserves running file: OK')
