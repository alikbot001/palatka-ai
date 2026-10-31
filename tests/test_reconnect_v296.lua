-- v2.9.6 deterministic reconnect/state-machine/observed-spawn tests.
local sent,connects,saves,registered={},0,0,{}
local online=false
local game_dialog=true
local dialog_id=101
local events={}
package.loaded['samp.events']=events
_G.DSP={
    settings={},
    save_settings=function()saves=saves+1;return true end,
    flog=function()end,
    lower=string.lower,
}
sampGetCurrentServerAddress=function()return 'game.example.test',7777 end
sampProcessChatInput=function(command)
    assert(command=='/reconnect')
    connects=connects+1
    return true
end
sampConnectToServer=function(host,port)
    assert(host=='game.example.test' and port==7777)
    return true
end
sampIsLocalPlayerSpawned=function()return online end
sampIsDialogActive=function()return game_dialog end
sampGetCurrentDialogId=function()return dialog_id end
sampSendDialogResponse=function(id,response,idx,text)
    sent[#sent+1]={id,response,idx,text}
    return true
end
sampRegisterChatCommand=function(cmd,fn)registered[cmd]=fn end
sampAddChatMessage=function()end
dofile('src/70_reconnect_v296.lua')
local R=DSP.reconnect
assert(R.installed and R.config().enabled==false,'must default off')
assert(R.server_key()=='game.example.test:7777','recognize current server')
assert(type(registered.prc)=='function','manual /prc command')
assert(R.disconnected('lost','Connection lost',100)==false,'auto reconnect disabled by default')
assert(R.manual(100),'manual reconnect is available')
online=true
assert(R.tick(100)==true and connects==1,'manual reconnect must work while spawned')
online=false
assert(R.state=='connecting')
R.connected(102)
assert(R.state=='idle' and R.attempts==0)
-- Configured lost connection with finite retries and exponential backoff.
assert(R.set('enabled',true))
assert(R.set('min_delay',12))
assert(R.set('max_delay',60))
assert(R.set('jitter',0))
assert(R.set('max_attempts',2))
assert(R.set('connect_timeout',30))
assert(R.disconnected('lost','Connection lost',200))
assert(R.next_at==208,'expected 208, got '..tostring(R.next_at)..' (delay '..tostring(R.config().initial_delay)..', attempts '..tostring(R.attempts)..')')
assert(not R.tick(207)and connects==1)
assert(R.tick(208) and connects==2 and R.attempts==1)
assert(not R.tick(237))
assert(not R.tick(238) and R.state=='scheduled')
assert(R.next_at==250,'first retry backoff')
assert(R.tick(250) and connects==3)
assert(not R.tick(280) and R.state=='idle','must stop after attempt cap')
assert(R.status=='Attempt limit reached')
-- Suppress automatic reconnect after a kick/ban/password issue.
assert(R.disconnected('lost','Connection lost',301))
R.on_message('Your account is banned')
assert(R.blocked and R.state=='idle')
assert(not R.disconnected('lost','Connection lost',302))
-- Do not choose any unobserved or guessed spawn ID.
R.blocked=false
assert(not R.select_spawn('Invisible'),'must observe spawn first')
local title='Выбор спавна'
local list='Дом\nКвартира\nСемейный дом'
assert(R.observe_dialog(101,2,title,list,400))
assert(#R.options==3)
assert(R.options[2].index==1 and R.options[2].label=='Квартира')
assert(R.select_spawn('Квартира'))
assert(R.set('spawn_enabled',true))
assert(R.set('spawn_delay',2))
assert(R.observe_dialog(101,2,title,list,500))
assert(#sent==0 and R.spawn_pending,'response must be delayed')
R.tick(501)
assert(#sent==0,'do not send prematurely')
R.tick(502)
assert(#sent==1 and sent[1][1]==101 and sent[1][3]==1,'match exact option by name')
-- A changed menu must fail closed, not click an arbitrary position.
assert(R.observe_dialog(101,2,title,'Дом\nВокзал',600))
assert(R.spawn_pending==nil and R.status:find('not found'))
R.tick(610)
assert(#sent==1)
-- Recognize style 5 (tablist with header) without off-by-one errors.
assert(R.observe_dialog(101,5,title,'Выбор\tОписание\nДом\t1\nКвартира\t2',700))
assert(R.spawn_pending and R.spawn_pending.index==1)
-- Prevent click after dialog was dismissed or user answered manually.
R.spawn_pending=nil
R.observe_dialog(101,5,title,'Выбор\tОписание\nДом\t1\nКвартира\t2',720)
game_dialog=false
R.tick(722)
assert(#sent==1,'dismissed dialog must not receive automatic response')
game_dialog=true
-- Password dialog and generic dialogs must never be answered.
local before=#sent
assert(not R.observe_dialog(133,1,'Введите пароль','********',800))
R.tick(810)
assert(#sent==before)
-- Per-server profile may not bleed over after switching servers.
sampGetCurrentServerAddress=function()return'other.example.test',7788 end
assert(R.remember_address())
assert(R.server_key()=='other.example.test:7788' and #R.options==0)
assert(not R.profile().spawn_label,'spawn must be server-specific')
assert(saves>0)
print('PASS v2.9.6 bounded reconnect, manual command, backoff and exact dialog spawn')
