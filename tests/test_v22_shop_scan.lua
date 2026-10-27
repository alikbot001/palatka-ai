-- Current-stall observations must survive replay without inventing quantities.
local failures={}
local function check(name,fn)local ok,err=pcall(fn);if not ok then failures[#failures+1]=name..': '..tostring(err)end end
local real_time=os.time;local stamp=1800000000
os.time=function()return stamp end
local function fixture()
    local calls,saves={},0
    DSP={settings={server=102,sell_preset={name='Sell',items={}},buy_preset={name='Buy',items={}}},
        auto={},db={world={untouched=123}},market={},items={},
        clean_text=function(s)return tostring(s or '')end,lower=string.lower,text_cp=function(s)return s end,
        item_key=function(s,e)return s:lower()..'|'..tostring(e or 0)end,
        item_name=function(s,e)return(e or 0)>0 and s..' (+'..e..')'or s end,
        flog=function()end,add_log=function()end,notify=function()end}
    DSP.parse_item_id=function(raw,ench)
        local id,e=tostring(raw):match('^(%d+)%((%d+)%)$')
        return tonumber(id or raw) or 0,tonumber(e or ench) or 0
    end
    DSP.items.name=function(id)return({[22]='Bandana',[23]='Glasses',[24]='Skin'})[id]or('ID:'..id)end
    DSP.db.learn=function(id,ench,price,side)calls[#calls+1]={id=id,ench=ench,price=price,side=side}end
    DSP.save_settings=function()saves=saves+1;return true end
    decodeJson=function()end
    dofile('src/20_presets.lua');dofile('src/21_preset_library.lua');dofile('src/45_live.lua')
    local extension=loadfile('src/46_shop_scan.lua');if extension then extension()end
    return DSP.live,DSP.shop_scan,calls,function()return saves end
end
local function packet(L,tp,slot,item,price,tail)
    L.handle(60,0,string.format('{"type":%d,"slot":%d,"item":%d,"amount":%d%s}',tp,slot,item,price,tail or ''))
end
check('sell and buy slots remain separate and repeated packets replace',function()
    local L,S,calls=fixture()
    L.handle_shop_owner('{"name":"Owner","shopNum":75}')
    packet(L,13,0,22,1000);packet(L,28,0,22,1000);packet(L,13,0,22,1000)
    assert(#L.shop.sell==1 and #L.shop.buy==1,'side-less seen index mixed buy and sell')
    assert(L.shop.sell[1].qty==nil and not L.shop.sell[1].qty_known,'amount price or replay became stock')
    assert(#calls==2,'identical replay learned the same price again')
    packet(L,13,0,23,700,',"count":4')
    assert(#L.shop.sell==1 and L.shop.sell[1].id==23 and L.shop.sell[1].qty==4,'slot update appended stale row')
end)
check('quantity only comes from explicit declared evidence',function()
    local L,S=fixture();assert(S,'shop_scan API missing')
    packet(L,13,0,22,1000,',"qty":5');packet(L,28,0,22,800)
    local s=S.snapshot();assert(s.sell[1].qty==5 and s.sell[1].qty_known)
    assert(s.buy[1].qty==nil and not s.buy[1].qty_known,'legacy amount is price, not qty')
    packet(L,13,0,22,1000,',"count":2');assert(S.snapshot().sell[1].qty==2,'declared quantity not replaced')
    packet(L,13,1,23,1,',"text":"Цена $500 (7 шт.)"')
    assert(S.snapshot().sell[2].qty==7 and S.snapshot().sell[2].price==500,'explicit text amount lost')
    local copy=S.snapshot();copy.sell[1].price=9;assert(S.snapshot().sell[1].price==1000,'snapshot leaked mutable source')
end)
check('legacy amount remains price when a smaller text number is present',function()
    local L,S=fixture();assert(S,'shop_scan API missing')
    packet(L,13,0,22,1000,',"text":"$500"')
    assert(S.snapshot().sell[1].price==1000,'text replaced confirmed legacy amount price')
    packet(L,13,0,22,1,',"text":"$500 (7 шт.)"')
    assert(S.snapshot().sell[1].price==500 and S.snapshot().sell[1].qty==7,'explicit text price/quantity evidence lost')
end)
check('slot clearing and slot-less item identity never accumulate replay',function()
    local L,S=fixture();assert(S,'shop_scan API missing')
    packet(L,13,0,22,1000,',"qty":5');packet(L,13,0,22,1000,',"qty":0')
    assert(#S.snapshot().sell==0,'zero remaining count kept stale offer')
    L.handle(60,0,'{"type":13,"item":"22(4)","amount":1000}')
    L.handle(60,0,'{"type":13,"item":22,"enchant":4,"amount":1100}')
    assert(#S.snapshot().sell==1 and S.snapshot().sell[1].price==1100,'equivalent item forms became different unknown slots')
end)
check('late owner preserves pending rows and close/new number resets',function()
    local L,S=fixture();assert(S,'shop_scan API missing')
    packet(L,28,0,22,800)
    L.handle_shop_owner('{"name":"Owner","shopNum":75}')
    assert(#S.snapshot().buy==1 and S.snapshot().owner=='Owner','late owner discarded received items')
    L.handle_shop_owner('{"name":"Owner","shopNum":76}')
    assert(#S.snapshot().buy==0,'same owner other stall reused old rows')
    packet(L,28,0,22,900);L.handle(255,0,'')
    assert(S.snapshot().closed,'close state missing')
    L.handle_shop_owner('{"name":"Owner","shopNum":76}')
    assert(#S.snapshot().buy==0 and not S.snapshot().closed,'reopening retained old rows')
end)
check('items before new owner never inherit previous shop identity',function()
    local L,S=fixture()
    L.handle_shop_owner('{"name":"Old_Owner","shopNum":75}')
    packet(L,13,0,22,1000)
    L.handle(255,0,'') -- menu closes before new owner metadata arrives
    packet(L,13,0,23,700)
    local pending=S.snapshot()
    assert(pending.owner=='' and pending.num=='','new stall items leaked old owner metadata')
    assert(#pending.sell==1 and pending.sell[1].id==23,'old inventory kept after boundary')
    L.handle_shop_owner('{"name":"New_Owner","shopNum":76}')
    assert(S.snapshot().owner=='New_Owner' and #S.snapshot().sell==1,
      'late new owner discarded new-gen rows')
    -- An owner packet can precede the first slot-0 packet of the next stall.
    L.handle(255,0,'')
    L.handle_shop_owner('{"name":"Third_Owner","shopNum":77}')
    packet(L,13,0,24,900)
    assert(S.snapshot().owner=='Third_Owner' and #S.snapshot().sell==1
        and S.snapshot().sell[1].id==24,'owner-first packet reset incorrectly')
    -- Also cover stale data without an explicit closing packet.
    stamp=stamp+11
    packet(L,13,0,22,1200)
    assert(S.snapshot().owner=='' and #S.snapshot().sell==1
        and S.snapshot().sell[1].id==22,'stale new generation reused recent metadata')
    L.handle_shop_owner('{"name":"Fourth_Owner","shopNum":78}')
    assert(S.snapshot().owner=='Fourth_Owner' and #S.snapshot().sell==1,
        'late metadata after stale boundary removed pending items')
end)
check('copy selected buy offers into a new named preset once',function()
    local L,S,calls,saves=fixture();assert(S,'shop_scan API missing')
    packet(L,28,0,22,800);packet(L,28,1,22,900,',"qty":50');packet(L,28,2,23,600,',"qty":3')
    local source=S.snapshot();local selected={[source.buy[2].key]=true,[source.buy[3].key]=true}
    local result=S.copy_to_preset('buy',{name='Observed buy',selected=selected,markup=-10})
    assert(result.ok and result.count==2 and result.index==2 and saves()==1,'copy did not create atomically')
    local p=DSP.settings.buy_preset
    assert(p.name=='Observed buy' and p.items[1].price==890 and p.items[1].qty==50)
    assert(p.items[2].price==590 and p.items[2].qty==3 and p.items[1].enabled,'copied values wrong')
    assert(#DSP.presets.list('buy')==2 and #DSP.presets.list('sell')==1,'another library overwritten')
    assert(S.snapshot().buy[2].price==900,'copy markup mutated source')
    local exported=DSP.presets.export_data('buy');assert(exported.items[1].max_price==890 and exported.items[1].target_qty==50)
end)
check('unknown stock is a user limit and conflicting prices never add quantity',function()
    local L,S=fixture();assert(S,'shop_scan API missing')
    packet(L,28,0,22,800);packet(L,28,1,22,900,',"qty":500')
    local result=S.copy_to_preset('buy',{name='Unknown'})
    assert(result.ok and result.count==1 and result.unknown_qty==1 and result.conflicts==1)
    assert(DSP.settings.buy_preset.items[1].price==800 and DSP.settings.buy_preset.items[1].qty==1,'duplicate stock or arbitrary price copied')
    packet(L,13,0,23,1000,',"qty":20')
    result=S.copy_to_preset('sell',{name='For sale'})
    assert(result.ok and DSP.settings.sell_preset.items[1].enabled==false,'copied sale enabled before inventory validation')
end)
check('existing preset keeps own values until explicit price correction',function()
    local L,S,calls,saves=fixture();assert(S,'shop_scan API missing')
    local p=DSP.settings.buy_preset;p.items={{name='Bandana',ench=0,key=DSP.item_key('Bandana',0),price=55,qty=8,cost_price=25,enabled=false}}
    packet(L,28,0,22,800,',"qty":900');packet(L,28,1,23,600)
    local r=S.copy_to_preset('buy',{index=1})
    assert(r.ok and r.count==1 and r.skipped_duplicates==1 and p.items[1].price==55 and p.items[1].qty==8)
    r=S.apply_prices('buy',1)
    assert(r.ok and r.count==1 and p.items[1].price==800 and p.items[1].qty==8 and p.items[1].cost_price==25 and not p.items[1].enabled,'price correction changed user fields')
end)
check('failed save rolls back new library and existing prices in place',function()
    local L,S,calls,saves=fixture();assert(S,'shop_scan API missing')
    local p=DSP.settings.buy_preset;local it={name='Bandana',ench=0,price=50,qty=8};p.items={it}
    packet(L,28,0,22,800)
    DSP.save_settings=function()return false,'disk full'end
    local r=S.copy_to_preset('buy',{name='Must rollback'})
    assert(not r.ok and r.error and DSP.settings.buy_preset==p and p.items[1]==it,'copy save failure broke active aliases')
    assert(not DSP.settings.buy_presets or #DSP.settings.buy_presets==1,'failed copy left a created preset')
    r=S.apply_prices('buy',1);assert(not r.ok and it.price==50 and it.qty==8,'price save failure retained changes')
end)
check('explicit price correction clears only its stale visible edit after save',function()
    local L,S=fixture();assert(S,'shop_scan API missing')
    local it={name='Bandana',ench=0,price=800,qty=8,cost_price=25}
    DSP.settings.buy_preset.items={it};local refreshes=0
    DSP.mobile={invalid_edits={[it]={price=true,qty=true}},refresh_buffer=function(row,key)
        refreshes=refreshes+1;DSP.mobile.invalid_edits[row][key]=nil
    end}
    packet(L,28,0,22,800)
    local result=S.apply_prices('buy','1')
    assert(result.ok and result.count==1 and refreshes==1,'explicit correction did not clear stale price buffer')
    assert(DSP.mobile.invalid_edits[it].qty and not DSP.mobile.invalid_edits[it].price,'correction cleared another field')
    DSP.mobile.invalid_edits[it].price=true;it.price=50;DSP.save_settings=function()return false,'disk full'end
    result=S.apply_prices('buy',1)
    assert(not result.ok and it.price==50 and DSP.mobile.invalid_edits[it].price and refreshes==1,'failed save discarded visible edit')
end)
check('snapshot expectations and server mismatch reject without mutation',function()
    local L,S,calls,saves=fixture();assert(S,'shop_scan API missing')
    packet(L,28,0,22,800);local snap=S.snapshot()
    packet(L,28,0,22,850)
    local result=S.copy_to_preset('buy',{name='Stale',expected_revision=snap.revision})
    assert(not result.ok and saves()==0,'changed revision accepted')
    snap=S.snapshot();DSP.settings.server=103
    result=S.copy_to_preset('buy',{name='Wrong server'})
    assert(not result.ok and saves()==0,'other server snapshot accepted')
    DSP.settings.server=102;L.reset_shop('New owner',76);packet(L,28,0,22,800)
    result=S.copy_to_preset('buy',{name='Old generation',expected_generation=snap.generation})
    assert(not result.ok and saves()==0,'other stall generation accepted')
end)
check('closed and busy actions never mutate presets or learn API offers',function()
    local L,S,calls,saves=fixture();assert(S,'shop_scan API missing')
    packet(L,28,0,22,800);local n=#calls
    assert(S.learn().ok and #calls==n,'learn replay was not idempotent')
    assert(DSP.db.world.untouched==123,'observed price replaced world API state')
    DSP.auto.buy_running=true
    assert(not S.copy_to_preset('buy',{name='Busy'}).ok and not S.apply_prices('buy',1).ok and saves()==0,'busy preset mutated')
    DSP.auto.buy_running=false;L.handle(255,0,'')
    assert(S.snapshot().closed and #S.snapshot().buy==1,'closing erased observed source')
    assert(S.copy_to_preset('buy',{name='Closed'}).ok,'closed snapshot cannot be used for explicit planning')
    assert(S.apply_prices('buy',2).ok,'closed snapshot cannot correct explicit preset prices')
end)
os.time=real_time
for _,err in ipairs(failures)do io.stderr:write(err..'\n')end
assert(#failures==0,tostring(#failures)..' shop scan regressions')
print('v22 current stall scan: slots, quantity evidence, learn, named copy, price-only correction, rollback: OK')
