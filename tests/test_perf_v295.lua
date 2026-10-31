-- Regression: rendering 240 frames must not rebuild heavy data 240 times.
do
    local evaluations,searches=0,0
    _G.DSP={
        market={state={sid=1,version=1}},
        storage={snapshots={},evaluate=function(snap)
            evaluations=evaluations+1
            return {rows={},known_qty_rows=0,source=snap}
        end,search_library=function(q)
            searches=searches+1
            return {query=q,results={}}
        end}
    }
    dofile('src/47d_storage_render_cache_v295.lua')
    local snap={rows={{name='Box',qty=2}}}
    for i=1,240 do
        DSP.storage.evaluate(snap)
        DSP.storage.search_library('box')
    end
    assert(evaluations<=2 and searches<=2,
        'storage evaluation/search must not run each frame')
    DSP.market.state.version=2
    DSP.storage.evaluate(snap)
    DSP.storage.search_library('box')
    assert(evaluations>=2 and searches>=2,'new market evidence must invalidate cache')
end
do
    local calls=0
    _G.DSP={
        auto={inv={{name='box',count=5}},inv_status='ready',scanning=false},
        craglog={history_revision=0,visibility_revision=0,
            drop_sales_stats=function()
                calls=calls+1
                return {items={},dropped=calls}
            end}
    }
    dofile('src/65b_stats_render_cache_v295.lua')
    for i=1,240 do DSP.craglog.drop_sales_stats('day','')end
    assert(calls<=2,'inventory stats cannot run every frame')
    local before=calls
    DSP.craglog.history_revision=1
    DSP.craglog.drop_sales_stats('day','')
    assert(calls==before+1,'new trade must invalidate stats')
    DSP.auto.inv_status='scanned'
    DSP.craglog.drop_sales_stats('day','')
    assert(calls==before+2,'new inventory scan must invalidate stats')
end
do
    local reads,totals=0,0
    local now=os.time()
    _G.DSP={
        settings={craglog={open=true}},
        craglog={history_revision=0,visibility_revision=0,
            trade_rows=function()
                reads=reads+1
                return {
                    {ts=now,kind='sell',name='Stone',qty=2,amount=300},
                    {ts=now,kind='buy',name='Box',qty=1,amount=100}
                }
            end,
            trade_totals=function(rows)
                totals=totals+1
                return {sells=300,buys=100,sell_qty=2,buy_qty=1,approx=false}
            end},
        ui22={
            button=function()return false end,
            heading=function()end,
            search=function()return '',false end,
            fit=function(s)return s end},
        mobile={},
        theme={col=function()return {} end},
        utf8=function(x)return x end,
        money=function(n)return '$'..tostring(n)end,
    }
    _G.imgui={
        ImVec2=function(x,y)return{x=x,y=y}end,
        GetContentRegionAvail=function()return{x=900,y=650}end,
        BeginPopup=function()return false end,
        BeginChild=function()return false end,
        EndChild=function()end,
        Separator=function()end,
        TextColored=function()end,
        TextDisabled=function()end,
        Text=function()end,
        SameLine=function()end,
    }
    dofile('src/66e_mh_journal_fast_v295.lua')
    assert(DSP.settings.craglog.open==false,'disabled overlay must remain closed')
    for i=1,240 do DSP.ui22.journal()end
    assert(reads<=2 and totals<=2,'journal must only rebuild once per cache window')
    local before=reads
    DSP.craglog.history_revision=1
    DSP.ui22.journal()
    assert(reads==before+1,'journal must refresh after a new trade')
end
print('PASS v2.9.5 per-frame caches with event-driven invalidation')
