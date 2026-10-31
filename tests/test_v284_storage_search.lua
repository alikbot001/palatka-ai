-- Detailed library-wide search: matched quantities, not whole-trunk totals.
DSP={
 settings={storage_snapshots={}},
 market={state={sid=42,version=1},row_for=function(name)
   if name=='Суперларец' then return{buy={max=100},sell={min=130}}end
   if name=='Супердеталь' then return{buy={max=30},sell={min=50}}end
   return nil
 end},
 items={name=function(id)return 'ID:'..id end},
 lower=function(s)return string.lower(tostring(s or ''))end,
 trim=function(s)return tostring(s or ''):match('^%s*(.-)%s*$')end,
 clean_text=function(s)return tostring(s or '')end,
 item_key=function(s,e)return tostring(s)..':'..tostring(e or 0)end,
 flog=function()end,
 save_settings=function()return true end
}
function decodeJson()return{}end
dofile('src/47_storage.lua')
dofile('src/47c_storage_search.lua')
local S=DSP.storage
local function snapshot(id,title,server,rows)
 return{id=id,title=title,source='packet220_trunk_named',kind='trunk',
        server=server,observed_at=os.time(),rows=rows,slots_count=180}
end
local a=snapshot('a','Ларцы-гараж',42,{
 {id=101,name='Суперларец',ench=0,qty=10},
 {id=101,name='Суперларец',ench=0,qty=2},
 {id=102,name='Камень',qty=900},
 {id=103,name='Супердеталь',qty=nil}
})
local b=snapshot('b','Машина два',42,{
 {id=101,name='Суперларец',ench=0,qty=7},
 {id=102,name='Камень',qty=300}
})
local c=snapshot('c','Другой сервер',99,{
 {id=101,name='Суперларец',ench=0,qty=4}
})
local d=snapshot('d','Гараж с ресурсами',42,{{id=102,name='Камень',qty=400}})
S.snapshots={a,b,c,d}
local r=S.search_library('супер')
assert(r.storage_count==3 and r.match_groups==4)
assert(r.known_qty==23,'12+7+4 only, not unrelated 900+300')
assert(r.unknown_slots==1)
assert(r.priced_value==1900,'12*100 + 7*100, no cross-server value')
assert(r.different_server==1)
assert(r.results[1].snapshot==a and r.results[1].known_qty==12)
assert(r.results[1].matched_items[1].name=='Суперларец')
assert(r.results[1].matched_items[1].qty==12)
assert(r.results[1].matched_items[2].qty==0)
assert(r.results[1].matched_items[2].unknown_slots==1)
assert(r.results[2].snapshot==b and r.results[2].known_qty==7)
assert(r.results[3].snapshot==c and r.results[3].known_qty==4)
assert(r.results[3].matched_items[1].total_buy==nil)
local title=S.search_library('Ларцы-гараж')
assert(#title.results==1 and title.results[1].title_only==true)
assert(title.known_qty==0 and title.priced_value==0)
local none=S.search_library('несуществующее')
assert(#none.results==0 and none.known_qty==0)
assert(#S.search_library('').results==0)
-- No change to saved data; readonly lookup.
assert(a.rows[1].qty==10 and b.rows[1].qty==7)
print('PASS detailed storage search: per-container amounts, exact aggregates, unknown counts and server isolation')
