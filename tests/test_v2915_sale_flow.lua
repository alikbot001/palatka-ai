-- Full sale-flow regression for the Arizona Mobile II iface60/sub1 acknowledgement.
local failures=0
local function check(name,fn)
    local ok,err=pcall(fn)
    if not ok then failures=failures+1;print('FAIL '..name..': '..tostring(err))
    else print('PASS '..name)end
end
local function scenario(ack, options)
    options=options or {}
    local threads,requests,packets,dialog={},{},{},nil
    DSP={
        settings={sell_preset={items=options.preset or {{name='Item',price=130,qty=2,ench=0,enabled=true}}},
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
    DSP.auto.inv=options.inventory or {{name='Item',count=2,stacks={{slot=3,count=2}}}}
    if options.refreshed then
        DSP.auto.scan_inventory=function(internal)
            assert(internal==true and DSP.auto.sell_running,'internal refresh only')
            DSP.auto.inv=options.refreshed()
            DSP.auto.scanning=false
            DSP.auto.inv_status='fresh'
            return true
        end
    end
    return threads,requests,packets
end

check('full sale: native iface60/sub1 ack, new price dialog and server confirmation',function()
    local threads,requests,packets=scenario(true)
    assert(DSP.auto.start_sell())
    assert(#threads==1)
    threads[1]()
    assert(#requests==1,'expected one submitted sale, packets='..#packets..' status='..tostring(DSP.auto.status)..' phase='..tostring(DSP.trade_runtime.state.phase))
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
check('second listing rescans and uses shifted slot after first sale', function()
    local refreshes=0
    local threads,requests,packets=scenario(true,{
        preset={{name='Item',price=130,qty=2,enabled=true},
                {name='Other',price=200,qty=1,enabled=true}},
        inventory={{name='Item',count=2,stacks={{slot=3,count=2}}},
                   {name='Other',count=1,stacks={{slot=4,count=1}}}},
        refreshed=function()
            refreshes=refreshes+1
            return {{name='Other',count=1,stacks={{slot=0,count=1}}}}
        end,
    })
    assert(DSP.auto.start_sell())
    threads[1]()
    assert(#requests==2 and #packets==4,'only some items listed')
    assert(packets[2].payload:find('"slot":3',1,true),'original slot incorrect')
    assert(packets[4].payload:find('"slot":0',1,true),'stale slot used for second item')
    assert(refreshes==1,'expected one fresh scan')
    assert(DSP.auto.progress.done==2 and DSP.auto.progress.failed==0)
end)
check('when fresh inventory no longer contains item, no stale slot packet is sent',function()
    local threads,requests,packets=scenario(true,{
        preset={{name='Item',price=130,qty=2,enabled=true},
                {name='Other',price=200,qty=1,enabled=true}},
        inventory={{name='Item',count=2,stacks={{slot=3,count=2}}},
                   {name='Other',count=1,stacks={{slot=4,count=1}}}},
        refreshed=function() return {} end,
    })
    assert(DSP.auto.start_sell())
    threads[1]()
    assert(#requests==1 and #packets==2,'stale stock was sold')
    assert(DSP.auto.progress.failed==1 and DSP.auto.status:find('PARTIAL',1,true))
end)
assert(failures==0,'sale-flow regression failures: '..failures)
print('2.9.15 sale-flow tests: OK')
