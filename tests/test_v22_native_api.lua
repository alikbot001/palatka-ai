-- Export names read from the target's mimgui (MonetLoader >=2.6.0 wrapper).
local api={}
for name in io.lines('tests/support/monet_mimgui_api.txt')do api[name]=true end
for _,name in ipairs({'ImVec2','ImVec4','new','WindowFlags','Col','StyleVar','Cond','InputTextFlags'})do api[name]=true end
for _,name in ipairs({'57_journal_v16','60_ui21_shell','61_ui21_trade','62_ui21_shops','63_ui21_arbitrage','64_ui21_journal_calc','65_ui22_tools','66_ui22_journal'})do
 local f=assert(io.open('src/'..name..'.lua'));local s=f:read('*a');f:close()
 for symbol in s:gmatch('imgui%.([%w_]+)')do assert(api[symbol],name..' uses unsupported imgui.'..symbol)end
end
print('v22 target MonetLoader mimgui exports: OK')
