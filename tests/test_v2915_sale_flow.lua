-- Full sale-flow regression for the Arizona Mobile II iface60/sub1 acknowledgement.
local failures=0
local function check(name,fn)
    local ok,err=pcall(fn)
    if not ok then failures=failures+1;print('FAIL '..name..': '..tostring(err))
    else print('PASS '..name)end
end
local function scenario(ack)
    local threads,requests,packets,dialog={},{},{},nil
    DSP={
        settings={sell_preset={items={{name='Item',price=130,qty=2,ench=0,enabled=true}}},
            dry_run=false},
        market={},auto={},
        live={handle=function()end},
        add_log=function()end,flog=function()end,notify=function()end,
        money=tostring,
    }
    wait=function()end
    lua_thread={create=function(fn)threads[#threads+1]=fn end}
    sampIsDialogActive=function()return dialog~=nil end
    sampGetCurrentDialogId=function()return dialog and dialog.id or -1 end
    sampGetDialogText=function()return dialog and dialog.text or '' end
    sampGetDialogTitle=function()return dialog and dialog.title or '' end
    sampSendDialogResponse=function(id,button,row,text)
        if button==0 then dialog=nil;return end
        if id==3040 and row==0 then
            dialog=nil
            if ack then DSP.live.handle(60,1,'{"name":"Owner"}')end
        elseif id==28183 and button==1 then
            requests[#requests+1]={id=id,value=text}
            DSP.auto.sell_confirmed=true
            dialog=nil
        end
    end
    for _,name in ipairs({'39_trade_runtime','40_auto','41_trade_listing'}) do
        assert(loadfile('src/'..name..'.lua'))()
    end
    assert(loadfile('src/70c_stall_ready_v2915.lua'))()
    _G.dsp_click_slot=function(iface,id,sub,payload)
        packets[#packets+1]={iface=iface,sub=sub,payload=payload}
        if iface==8 then
            dialog={id=3040,style=2,title='Shop',text='Open inventory'}
        elseif iface==60 then
            dialog={id=28183,style=1,title='Price',text='Item quantity price'}
            DSP.auto.on_dialog(dialog.id,dialog.style,dialog.title,'','',dialog.text)
        else error('unexpected iface '..tostring(iface)) end
    end
    DSP.auto.inv={{name='Item',count=2,stacks={{slot=3,count=2}}}}
    return threads,requests,packets
end

check('full sale: native iface60/sub1 ack, new price dialog and server confirmation',function()
    local threads,requests,packets=scenario(true)
    assert(DSP.auto.start_sell())
    assert(#threads==1)
    threads[1]()
    assert(#requests==1,'expected one submitted sale')
    assert(requests[1].id==28183 and requests[1].value=='2,130','unexpected dialog response')
    assert(#packets==2 and packets[1].iface==8 and packets[2].iface==60)
    assert(DSP.auto.progress.done==1 and DSP.auto.progress.failed==0)
end)
check('no inventory acknowledgement: do not send a slot sale packet',function()
    local threads,requests,packets=scenario(false)
    assert(DSP.auto.start_sell())
    threads[1]()
    assert(#packets==1 and packets[1].iface==8,'unsafe attempt after missing ack')
    assert(#requests==0 and DSP.auto.sell_running==false)
end)
check('iface60/sub1 outside own-stall wait is not accepted',function()
    local threads,requests,packets=scenario(false)
    DSP.auto.sell_running=true
    DSP.trade_runtime.transition('sell','open_shop')
    DSP.live.handle(60,1,'{"name":"Owner"}')
    assert(DSP.auto.stall_inventory_ready==false)
end)
assert(failures==0,'sale-flow regression failures: '..failures)
print('2.9.15 sale-flow tests: OK')
