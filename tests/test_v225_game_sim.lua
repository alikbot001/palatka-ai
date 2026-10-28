-- Deterministic SAMP dialog/RPC simulator. Never sends a real game command.
DSP={settings={dry_run=true,
    sell_preset={items={{name='Дрова',price=500,qty=2,enabled=true}}},
    buy_preset={items={{name='Дрова',price=300,qty=3,enabled=true}}}},
    auto={},add_log=function()end, notify=function()end,
    lower=function(s)return tostring(s):lower()end,
    dialog_clean=function(s)return s end, money=tostring}
local active=false
local dlg=0
local content=''
local rpc={}
local responses={}
local function show(id,s) active=true;dlg=id;content=s end
local phase='sell'
wait=function(ms)end
lua_thread={create=function(fn)fn()end}
sampIsDialogActive=function()return active end
sampGetCurrentDialogId=function()return dlg end
sampGetDialogText=function()return content end
sampSendDialogResponse=function(id,btn,idx,val)
    responses[#responses+1]={id,btn,idx,val}
    if btn==0 then active=false;return end
    if phase=='buy' then
        if id==3040 and idx==2 then show(25663,'Введите название')
        elseif id==25663 then show(25664,'Дрова\t[ресурс]')
        elseif id==25664 then show(26563,'Дрова\nКоличество и цена через запятую')
        else error('Unexpected simulated purchase path '..id) end
    else error('Dry run must not submit actual sale!') end
end
raknetNewBitStream=function()return {} end
raknetBitStreamWriteInt8=function()end
raknetBitStreamWriteInt16=function()end
raknetBitStreamWriteInt32=function()end
raknetBitStreamWriteString=function()end
raknetDeleteBitStream=function()end
raknetSendBitStreamEx=function()end
dofile('src/39_trade_runtime.lua')
dofile('src/40_auto.lua')
-- override parser: outside MonetLoader, the encoding module is not present.
DSP.dialog_clean=function(s)return tostring(s or '')end
dofile('src/41_trade_listing.lua')
dofile('src/42_trade_buy.lua')
DSP.auto.inv={{name='Дрова',stacks={{slot=12,count=5}},count=5}}
_G.dsp_click_slot=function(iface,id,sub,json)
    rpc[#rpc+1]={iface,id,sub,json}
    if iface==60 then show(26547,(phase=='wrong' and 'Камень' or 'Дрова')..'\nКоличество и цена через запятую')
    elseif iface==8 then show(3040,'Лавка\nПродажа\nСкупка')
    else error('Unexpected simulated RPC '..tostring(iface))end
end
assert(DSP.auto.start_sell()==true,'sell must launch')
assert(#rpc==1 and rpc[1][4]:find('"slot":12',1,true),'correct inv slot')
assert(DSP.auto.progress.dry==1 and DSP.auto.progress.failed==0,'sale dry-run completes')
assert(#responses>=1 and responses[#responses][2]==0,'only cancel in dry mode')
-- A same-ID popup for another item must be rejected, never submitted.
phase='wrong';rpc={};responses={};active=false
DSP.auto.inv={{name='Дрова',stacks={{slot=12,count=5}},count=5}}
assert(DSP.auto.start_sell()==true)
assert(DSP.auto.progress.failed==1 and DSP.auto.progress.dry==0,'wrong item dialog rejected')
for _,resp in ipairs(responses) do assert(resp[2]==0,'foreign item must not be listed')end
phase='buy';rpc={};responses={};active=false
assert(DSP.auto.start_buy()==true,'buy must launch')
assert(#rpc>=1 and rpc[1][1]==8,'correct stall click')
assert(DSP.auto.progress.dry==1 and DSP.auto.progress.failed==0,'buy dry-run completes')
for _,resp in ipairs(responses) do
    assert(not(resp[1]==26563 and resp[2]==1),'no purchasing in simulator dry-run')
end
print('v225 SAMP fake RPC/dialog sell+buy: dry-run, correct slots, no real listing PASS')
