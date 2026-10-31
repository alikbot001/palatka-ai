-- Observed current-stall prices stay separate from the world market snapshot.
local S={};DSP.shop_scan=S
local max_integer=9007199254740991
local learned_shop,learned=nil,{}
local cached_shop,cached_revision,cached_view=nil,nil,nil
local function fail(message)return{ok=false,error=tostring(message)}end
local function integer(value,min)
    local n=tonumber(value)
    if n and n==n and n>=(min or 0) and n<=max_integer and n%1==0 then return n end
end
local function side_ok(side)return side=='sell' or side=='buy'end
local function current_server()
    return tonumber(DSP.settings and DSP.settings.server) or tonumber(DSP.market and DSP.market.state and DSP.market.state.sid) or 0
end
local function busy()return DSP.auto and (DSP.auto.buy_running or DSP.auto.sell_running)end
local function item_key(it)
    return DSP.item_key(tostring(it.name or ''):gsub('%s*%(%+%d+%)%s*$',''),it.ench or 0)
end
function S.snapshot()
    local s=DSP.live and DSP.live.shop or {}
    local revision=s.revision or 0
    if cached_view and cached_shop==s and cached_revision==revision then
        cached_view.updated=s.updated or 0
        return cached_view
    end
    local out={owner=s.owner or '',num=s.num or '',updated=s.updated or 0,revision=s.revision or 0,
        opened=s.opened or 0,generation=s.generation or 0,server=s.server or 0,closed=(s.updated or 0)==0 or (s.menu_closed or 0)>0,sell={},buy={}}
    for _,side in ipairs({'sell','buy'}) do
        for _,entry in ipairs(s[side] or {}) do
            local row={};for key,value in pairs(entry) do row[key]=value end
            out[side][#out[side]+1]=row
        end
        table.sort(out[side],function(a,b)
            if (a.slot or math.huge)~=(b.slot or math.huge) then return (a.slot or math.huge)<(b.slot or math.huge) end
            return tostring(a.key)<tostring(b.key)
        end)
    end
    cached_shop,cached_revision,cached_view=s,revision,out
    return out
end
function S.learn(options)
    options=options or {}
    local snap=S.snapshot()
    if snap.closed then return fail('Лавка закрыта') end
    if snap.server~=current_server() then return fail('Снимок лавки другого сервера') end
    local current=DSP.live.shop
    if current~=learned_shop then learned_shop,learned=current,{} end
    local count=0
    local db=DSP.db
    local previous_batch=db._batch_learning
    db._batch_learning=true
    local ok,err=pcall(function()
        for _,side in ipairs({'sell','buy'}) do
            for _,row in ipairs(snap[side]) do
                local signature=table.concat({row.id or row.item_id,row.ench or 0,row.price},':')
                local key=side..':'..tostring(row.key)
                if learned[key]~=signature then
                    local result=db.learn(row.id or row.item_id,row.ench or 0,row.price,side)
                    if result==false then error('price database refused an item') end
                    learned[key]=signature;count=count+1
                end
            end
        end
    end)
    db._batch_learning=previous_batch
    if count>0 and not previous_batch and not options.defer_save
        and type(db.save)=='function' then db.save(false) end
    if not ok then return{ok=false,count=count,error=tostring(err)} end
    return{ok=true,count=count}
end
local function offers(side,options)
    if not side_ok(side) then return nil,'Укажите сторону лавки' end
    local snap=S.snapshot()
    if snap.server~=current_server() then return nil,'Снимок лавки другого сервера' end
    for _,field in ipairs({'revision','generation','server'}) do
        local expected=options['expected_'..field]
        if expected~=nil and expected~=snap[field] then return nil,'Снимок лавки изменился; откройте выбор заново' end
    end
    if options.selected~=nil and type(options.selected)~='table' then return nil,'Неверный выбор позиций' end
    local rows,seen,conflicts={},{},0
    for _,row in ipairs(snap[side]) do
        if not options.selected or options.selected[row.key]==true then
            if not integer(row.price,1) then return nil,'Неверная наблюдаемая цена' end
            local key=item_key(row)
            if not seen[key] then seen[key]=row;rows[#rows+1]=row
            elseif seen[key].price~=row.price then conflicts=conflicts+1 end
        end
    end
    if #rows==0 then return nil,'Нет выбранных позиций' end
    return rows,nil,conflicts
end
local function library_keys(kind)
    return kind..'_presets','active_'..kind..'_preset',kind..'_preset'
end
function S.copy_to_preset(side,options)
    options=options or {}
    if type(options)~='table' then return fail('Неверные параметры копирования') end
    if busy() then return fail('Остановите выставление') end
    local kind=options.target_side or side
    if not side_ok(kind) then return fail('Неверная сторона пресета') end
    local rows,err,conflicts=offers(side,options)
    if not rows then return fail(err) end
    local markup=tonumber(options.markup or 0)
    if not markup or markup~=markup or markup%1~=0 or math.abs(markup)>max_integer then return fail('Неверная надбавка в долларах') end
    if options.name~=nil and type(options.name)~='string' then return fail('Неверное имя набора') end
    local name=options.name and DSP.text_cp(options.name):match('^%s*(.-)%s*$')
    local index=options.index and integer(options.index,1)
    if (options.index and not index) or (name and name=='') or (name and index) or (not name and not index) then return fail('Выберите набор или задайте новое имя') end
    local pending={}
    for _,row in ipairs(rows) do
        if markup>max_integer-row.price or markup<1-row.price then return fail('Надбавка даёт неверную цену') end
        local price=row.price+markup;local qty=row.qty_known and integer(row.qty,1) or 1
        if not qty or price>max_integer/qty then return fail('Сумма превышает точный диапазон') end
        pending[#pending+1]={name=DSP.item_name(row.name,row.ench or 0),key=item_key(row),ench=row.ench or 0,
            item_id=row.item_id or row.id,price=price,qty=qty,enabled=kind=='buy',source_qty_unknown=not row.qty_known or nil}
    end
    local result={ok=true,count=0,index=index,unknown_qty=0,conflicts=conflicts,skipped_duplicates=0,target_side=kind}
    local ok,why=DSP.presets._transaction(function()
        local list=DSP.presets.list(kind)
        if name then
            for _,p in ipairs(list) do if p.name==name then return false,'Набор с таким именем уже существует' end end
            list[#list+1]={name=name,items={}};index=#list;result.index=index
        end
        local target=list[index]
        if not target then return false,'Набор не найден' end
        local existing={};for _,it in ipairs(target.items or {}) do existing[item_key(it)]=true end
        target.items=target.items or {}
        for _,it in ipairs(pending) do
            if existing[it.key] then result.skipped_duplicates=result.skipped_duplicates+1
            else
                target.items[#target.items+1]=it;existing[it.key]=true;result.count=result.count+1
                if it.source_qty_unknown then result.unknown_qty=result.unknown_qty+1 end
            end
        end
        local _,active,legacy=library_keys(kind)
        DSP.settings[active],DSP.settings[legacy]=index,target
        return true
    end)
    if not ok then return fail(why) end
    return result
end
function S.apply_prices(side,index,options)
    if busy() then return fail('Остановите выставление') end
    options=options or {}
    if type(options)~='table' then return fail('Неверные параметры коррекции') end
    local kind=options.target_side or side;index=integer(index,1)
    if not side_ok(kind) or not index then return fail('Выберите набор') end
    local rows,err,conflicts=offers(side,options)
    if not rows then return fail(err) end
    local prices={};for _,row in ipairs(rows) do prices[item_key(row)]=row.price end
    local result={ok=true,count=0,index=index,conflicts=conflicts,target_side=kind};local touched={}
    local ok,why=DSP.presets._transaction(function()
        local target=DSP.presets.list(kind)[index]
        if not target then return false,'Набор не найден' end
        local matches=0
        for _,it in ipairs(target.items or {}) do
            local price=prices[item_key(it)]
            if price then
                matches=matches+1
                local invalid=DSP.mobile and DSP.mobile.invalid_edits and DSP.mobile.invalid_edits[it]
                if it.price~=price or (invalid and invalid.price) then
                    it.price=price;result.count=result.count+1;touched[#touched+1]=it
                end
            end
        end
        if matches==0 then return false,'В наборе нет совпадающих предметов' end
        return true
    end)
    if not ok then return fail(why) end
    for _,it in ipairs(touched) do
        if DSP.mobile and DSP.mobile.refresh_buffer then DSP.mobile.refresh_buffer(it,'price') end
    end
    return result
end
return true
