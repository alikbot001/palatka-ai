-- Observed Lua regression checks; no game or Android runtime is simulated here.
local dir=os.tmpname(); os.remove(dir); assert(os.execute('mkdir -p '..dir..'/logs')==0)
local function encode(v)
    if type(v)=='string' then return string.format('%q',v) end
    if type(v)~='table' then return tostring(v) end
    local out={}; for k,x in pairs(v) do out[#out+1]='['..encode(k)..']='..encode(x) end
    return '{'..table.concat(out,',')..'}'
end
encodeJson=encode; decodeJson=function(s) return assert(loadstring('return '..s))() end
local stamp=os.time({year=2026,month=10,day=26,hour=12,min=0,sec=0})
local real_time=os.time; os.time=function(t) if t then return real_time(t) end return stamp end
local noop=function() end
DSP={dir=dir,settings={server=102,chat_logs={},tg_notify=false,tg_payday_enabled=false,tg_payday_last=stamp},
    db={get=function() end},logs={},ui={},clean_text=function(s) return tostring(s or '') end,
    lower=function(s) return s:lower():gsub('Налог','налог') end,money=tostring,money_val=function(s) return tonumber((s:gsub('[^%d]',''))) or 0 end,
    add_log=noop,flog=noop,notify=noop,mkdir_p=noop,save_settings=function() return true end,
    trades_log_path=dir..'/logs/trades.log',crates_log_path=dir..'/logs/crates.log',events_log_path=dir..'/logs/events.jsonl'}
for _,file in ipairs({'05_trades','06_rewards','55_craglog','45_live'}) do assert(loadfile('src/'..file..'.lua'))() end
local extension=loadfile('src/58_journal_delete.lua');if extension then extension() end
DSP.rewards.load()
local failed={}
local function check(label,fn)
    local ok,err=pcall(fn); if not ok then failed[#failed+1]=label..': '..tostring(err) end
end
check('day and session periods',function()
    DSP.settings.trades={old={type='trade',ts=stamp-86400,profit=100,total_get=100,total_give=0},
        today={type='trade',ts=stamp-60,profit=30,total_get=30,total_give=0},
        current={type='trade',ts=stamp,profit=7,total_get=7,total_give=0}}
    assert(DSP.logs.profit_summary('day').profit==37,'day includes previous date')
    assert(DSP.logs.profit_summary('session').profit==7,'session includes pre-launch records')
    assert(DSP.logs.profit_summary('all').profit==137,'all history retained')
end)
check('PayDay capture independent of saved Telegram throttle',function()
    assert(DSP.live.check_payday_message('PayDay'),'saved Telegram timestamp suppressed event')
    local pay=DSP.craglog.filtered('payday'); assert(#pay==1 and pay[1].raw=='PayDay','original marker preserved')
    assert(not DSP.live.check_payday_message('PayDay'),'duplicate marker not throttled')
end)
check('PayDay details and financial periods',function()
    DSP.logs.log_chat('Вам выплачена зарплата: $15.000')
    DSP.logs.log_chat('Налог: $750')
    DSP.logs.log_chat('Вам выплачена зарплата: $15.000')
    local e=DSP.craglog.filtered('payday')[1]
    assert(e and e.amount==14250 and e.income==15000 and e.expense==750,'salary and tax retained on one event')
    assert(#e.details==2 and e.details[2].raw=='Налог: $750','detail evidence')
    assert(#DSP.craglog.filtered('income')==0,'PayDay salary duplicated as general income')
    local s=DSP.craglog.summary('day')
    assert(s.payday_income==15000 and s.payday_expense==750,'PayDay finance summary')
end)
check('unknown reward remains unknown',function()
    local r=DSP.rewards.ingest('Вы получили особую награду: новый бонус',stamp)
    assert(r and r.kind=='unknown' and r.source=='неизвестный источник','unknown reward lost or falsely classified')
    assert(r.raw=='Вы получили особую награду: новый бонус','original reward text missing')
    assert(DSP.craglog.describe(r):find('неизвест',1,true),'unknown reward description invents trade')
    local d=DSP.rewards.parse('Вам выпало: Item')
    assert(d.association=='unknown','unknown drop source labelled explicit')
end)
check('non-item reward interrupts inferred source adjacency',function()
    DSP.rewards.ingest('Вы открыли Known!',stamp)
    DSP.rewards.ingest('Вы получили особую награду: бонус',stamp)
    local row=DSP.rewards.ingest("Вам был добавлен предмет 'After gap'",stamp)
    assert(row.association=='unknown' and row.source=='неизвестный источник','opening inferred across unrelated reward')
end)
check('cash totals exclude estimated item prices',function()
    DSP.settings.trades={estimated={type='trade',ts=stamp,total_get=900,total_give=300,profit=600,money_get=50,money_give=20}}
    DSP.logs.revision=(DSP.logs.revision or 0)+1
    local summary=DSP.craglog.summary('day')
    assert(summary.income==15050 and summary.expense==770 and summary.net==14280,'item estimates treated as cash')
    assert(summary.trade_profit==600,'trade valuation still available separately')
    assert(not DSP.rewards.parse('Вы получили зарплату $100'),'salary classified as unknown reward')
end)
check('page and summary share unchanged history scan',function()
    for i=1,30 do assert(DSP.rewards.record({kind='item',item_name='Item'..i,qty=1,ts=stamp,source='test'})) end
    local real_open=io.open; local reads=0
    io.open=function(file,mode) if file==dir..'/rewards.jsonl' and mode=='r' then reads=reads+1 end return real_open(file,mode) end
    DSP.rewards.query({source='test',page=1,page_size=5}); DSP.rewards.query({source='test',page=2,page_size=5}); DSP.rewards.summary({source='test'})
    io.open=real_open
    assert(reads==1,'history scanned '..reads..' times for unchanged filter')
end)
check('PayDay details survive restart',function()
    local old=DSP.craglog
    stamp=stamp+10;assert(old.log_income('Later',1,'later event'));stamp=stamp-10
    imgui={OnFrame=noop}
    assert(loadfile('src/55_craglog.lua'))(); DSP.craglog.install()
    local pay=DSP.craglog.filtered('payday')
    assert(#pay==1 and pay[1].amount==14250 and #pay[1].details==2,'details not restored')
    assert(DSP.craglog.ring_recent(1)[1].label=='Later','reward restore moved older items above newer events')
    DSP.craglog=old
end)
check('journal deletion is durable and recalculates visible finance',function()
    local C=DSP.craglog
    assert(type(C.delete_event)=='function','delete API missing')
    local row=assert(DSP.rewards.record({kind='cash',cash=17,source='delete probe',ts=stamp,raw='delete reward'}))
    assert(DSP.rewards.query({source='delete probe'}).total==1)
    local before=C.summary('day')
    assert(C.delete_event(row));assert(not C.event_visible(row))
    assert(DSP.rewards.query({source='delete probe'}).total==0,'cached reward remains visible')
    local after=C.summary('day');assert(after.net==before.net-17 and after.count==before.count-1,'visible finance not recalculated')
    local raw=assert(io.open(dir..'/rewards.jsonl','r'));local evidence=raw:read('*a');raw:close()
    assert(evidence:find('delete reward',1,true),'source reward removed')
    C.event_visible=function()return true end;DSP.rewards.invalidate()
    assert(DSP.rewards.query({source='delete probe'}).total==1)
    assert(loadfile('src/58_journal_delete.lua'))()
    assert(not C.event_visible(row) and DSP.rewards.query({source='delete probe'}).total==0,'tombstone lost after restart')
end)
check('legacy crate mirror shares durable reward identity',function()
    DSP.logs.crate_opened('Crate fixture',100,2,'Delete crate',0)
    local row=DSP.craglog.ring_recent(1)[1]
    assert(DSP.rewards.query({source='Delete crate'}).total==1)
    assert(DSP.craglog.delete_event(row))
    assert(DSP.rewards.query({source='Delete crate'}).total==0,'crate deletion left mirror reward visible')
    assert(next(DSP.settings.crates),'original crate accounting removed')
end)
check('delete one same-second trade without rewriting accounting',function()
    DSP.logs.record_trade('Same',{}, {},0,5,'accepted')
    DSP.logs.record_trade('Same',{}, {},0,5,'accepted')
    local row=DSP.craglog.ring_recent(1)[1]
    local before=DSP.craglog.summary('day')
    local accounting=DSP.logs.profit_summary('all').profit
    assert(DSP.craglog.delete_event(row))
    local after=DSP.craglog.summary('day')
    assert(after.net==before.net-5 and after.count==before.count-1,'same-second trades hidden together')
    assert(DSP.logs.profit_summary('all').profit==accounting,'source accounting was rewritten')
end)
check('failed deletion leaves event visible',function()
    local C=DSP.craglog;assert(type(C.delete_event)=='function','delete API missing')
    local row=assert(DSP.rewards.record({kind='cash',cash=3,source='keep probe',ts=stamp}))
    local real_open=io.open
    io.open=function(file,mode)if file==DSP.events_log_path and mode=='a' then return nil,'fixture denied' end return real_open(file,mode)end
    local ok,err=C.delete_event(row);io.open=real_open
    assert(not ok and err and C.event_visible(row),'failed delete hid event')
    assert(DSP.rewards.query({source='keep probe'}).total==1,'failed delete removed reward')
end)
check('mini uses fixed list and persistent filter scroll key',function()
    local noop=function() end
    local calls={};local buttons={}
    local flags=setmetatable({},{__index=function() return 0 end})
    imgui={WindowFlags=flags,StyleVar=flags,Col=flags,Cond=flags,ImVec2=function(x,y)return{x=x,y=y}end,
        GetCursorPosX=function()return 0 end,GetCursorPosY=function()return 0 end,GetTextLineHeight=function()return 16 end,GetIO=function()return{DisplaySize={x=2340,y=1080},MouseDelta={x=0,y=0}}end,
        Begin=function()return true end,Button=function(label,size) buttons[#buttons+1]={label=label,size=size};return false end,
        IsItemActive=function()return false end,IsMouseDragging=function()return false end,IsMouseDown=function()return false end}
    for _,name in ipairs({'PushStyleColor','PopStyleColor','SetNextWindowPos','SetNextWindowSize','SetNextWindowBgAlpha',
        'PushStyleVarFloat','PushStyleVarVec2','SameLine','TextWrapped','End','PopStyleVar'}) do imgui[name]=noop end
    DSP.theme={col=noop,push_overlay=function()return 0 end};DSP.utf8=function(s)return s end
    DSP.ui22={fit=function(s)return s end,at=noop,muted=noop,red=noop,green=noop,list=function()error('unexpected detail')end,
        list_rows=function(key,rows,height,draw,options)
            calls[#calls+1]={key=key,options=options}
            if rows[1] then draw(rows[1],1,370) end
        end}
    assert(loadfile('src/57_journal_v16.lua'))()
    DSP.settings.craglog={open=true,mini_mode='events',summary_period='all'};DSP.craglog.draw();DSP.craglog.draw()
    assert(#calls==2 and calls[1].key=='mini_all_all' and calls[2].key=='mini_all_all','scroll key changed during redraw')
    local geometry=DSP.craglog.geometry(2340,1080)
    assert(calls[1].options.height+DSP.craglog.mini_reserved()==geometry.h,'list intrudes into fixed controls')
    for _,button in ipairs(buttons) do assert(button.size.y>=42,'small touch target') end
    assert(#DSP.craglog.detail_lines({kind='payday',type='payday',ts=stamp,details={}})>=5,'unknown payday detail lost')
end)
os.time=real_time
for _,err in ipairs(failed) do io.stderr:write(err..'\n') end
assert(#failed==0,tostring(#failed)..' v2.2 event regressions')
print('v2.2 event regressions: OK')
