local P=assert(loadfile('mcr_copy/src/external.lua'))()
local E=assert(loadfile('mcr_copy/src/engine.lua'))()
local failures=0
local function test(name,fn)
    local ok,err=pcall(fn)
    if ok then print('OK: '..name)else failures=failures+1;print('FAIL: '..name..': '..tostring(err))end
end
local function external(owner,scan,updated,side,price)
    local row={server_id=102,shop_num=75,owner=owner,scanned_at=scan,updated_at=updated}
    row[(side or'sell')..'_slots']={{item_id=5,name='Item',price=price or 100,qty=3}}
    return row
end
local function pack(rows)return P.vata({shops=rows},102,'mobile2','SA$')end
local function snapshot(owner,at,source,price)
    return{server='mobile2',shop=75,owner=owner,at=at,source=source or'market-helper',
        sell={{id='5',variant='0',currency='SA$',price=price or 100,qty=3}},buy={}}
end
local function permutations(rows,fn)
    for _,order in ipairs({{1,2,3},{1,3,2},{2,1,3},{2,3,1},{3,1,2},{3,2,1}})do
        fn({rows[order[1]],rows[order[2]],rows[order[3]]})
    end
end
test('scan time ages quotes instead of cache update time',function()
    local p=pack({external('Richard',1000,10000)})
    assert(p.shops[1].at==1000,'original scan time was discarded')
    local state=E.new();assert(E.observe(state,p.shops[1]))
    local buyer={server='mobile2',shop=76,owner='Buyer',at=10000,
        buy={{id='5',variant='0:0',currency='SA$',price=200,qty=3}}}
    assert(E.observe(state,buyer))
    assert(#E.routes(state,'mobile2',10000,{ttl=3600})==0,'old scan revived by cache refresh')
end)
test('invalid present scan time is never replaced by update time',function()
    for _,at in ipairs({false,'invalid',0,-1,1.5,0/0,math.huge})do
        assert(#pack({external('Richard',at,10000)}).shops==0,'invalid scan accepted: '..tostring(at))
    end
    assert(pack({external('Richard',nil,10000)}).shops[1].at==10000,'legacy update time rejected')
    assert(pack({external('Richard','1000',10000)}).shops[1].at==1000,'numeric scan text rejected')
end)
test('same owner split sides merge at the same original scan time',function()
    local p=pack({external('Eva',1000,10000,'sell'),external('Eva',1000,10001,'buy')})
    assert(#p.shops==1 and #p.shops[1].sell==1 and #p.shops[1].buy==1,'split side lost')
end)
test('different owners at equal scan time stay unavailable in every row order',function()
    permutations({external('Richard',1000,10000,'sell'),external('Eva',1000,10000,'buy'),
        external('Richard',1000,10000,'sell')},function(rows)
        local p=pack(rows)
        assert(#p.shops==1 and #p.shops[1].sell==0 and #p.shops[1].buy==0,
            'ambiguous shop offers survived or tombstone missing')
        assert(p.shops[1].owner=='','ambiguous owner attributed')
    end)
end)
test('newer original scan replaces older owner without mixing sides',function()
    for _,older_owner in ipairs({'Richard','Other'})do
        permutations({external('Richard',1000,10050,'sell'),external(older_owner,1000,10060,'buy'),
            external('Eva',1001,10001,'buy',200)},function(rows)
            local s=pack(rows).shops[1]
            assert(s.owner=='Eva'and s.at==1001 and #s.sell==0 and #s.buy==1,'new scan did not replace identity')
        end)
    end
end)
test('external conflict clears existing cached offers',function()
    local state=E.new();assert(E.observe(state,snapshot('Richard',999)))
    local p=pack({external('Richard',1000,10000),external('Eva',1000,10000,'buy')})
    for _,row in ipairs(p.shops)do assert(E.observe(state,row))end
    assert(#state.shops['mobile2/75'].sell==0 and #state.shops['mobile2/75'].buy==0,
        'previous cached offers survived the conflict')
end)
test('engine same-time owner conflict cannot resurrect on a third row',function()
    permutations({snapshot('Richard',1000),snapshot('Eva',1000),snapshot('Richard',1000)},function(rows)
        local state=E.new()
        for _,row in ipairs(rows)do assert(E.observe(state,row))end
        local s=state.shops['mobile2/75']
        assert(s.owner==''and #s.sell==0 and #s.buy==0,'engine retained arbitrary owner offers')
        local saved=E.new();assert(E.observe(saved,s))
        assert(E.observe(saved,snapshot('Richard',1000)))
        assert(#saved.shops['mobile2/75'].sell==0,'reload lost owner conflict')
        assert(E.observe(saved,snapshot('Eva',1001)))
        assert(saved.shops['mobile2/75'].owner=='Eva'and #saved.shops['mobile2/75'].sell==1,
            'newer scan did not recover from conflict')
    end)
end)
test('local observation wins equal-time external conflict in either order',function()
    for _,reverse in ipairs({false,true})do
        local state=E.new()
        local local_row=snapshot('Eva',1000,'local')
        local external_row=snapshot('Richard',1000)
        assert(E.observe(state,reverse and external_row or local_row))
        assert(E.observe(state,reverse and local_row or external_row))
        assert(state.shops['mobile2/75'].owner=='Eva'and #state.shops['mobile2/75'].sell==1,
            'external ambiguity superseded local observation')
    end
end)
assert(failures==0,tostring(failures)..' shop identity regressions failed')
print('MCR shop identity: OK')
