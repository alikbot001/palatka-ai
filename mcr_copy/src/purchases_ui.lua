-- Manual notes only; saving these forms never executes or confirms a game trade.
return function(A)
local purchase,sale
local function scope(f)
    local h=A.host
    return f.server==h.server()and f.currency==h.currency()
end
local function number(raw,minimum)
    raw=tostring(raw or ''):match('^%s*(.-)%s*$')
    if not raw:match('^%d+$')then
        local first,separator,rest=raw:match('^(%d%d?%d?)([. ])(.+)$')
        if not first then return end
        while rest~=''do
            if not rest:sub(1,3):match('^%d%d%d$')then return end
            rest=rest:sub(4)
            if rest~=''then
                if rest:sub(1,1)~=separator or #rest==1 then return end
                rest=rest:sub(2)
            end
        end
        raw=raw:gsub('[. ]','')
    end
    return A.engine.integer(raw,minimum)
end
local function buffer(value,capacity)
    if type(value)=='number'then value=string.format('%.0f',value)end
    return A.host.imgui.new.char[capacity](A.host.utf8(tostring(value or '')))
end
local function raw(value)return A.host.input_string(value)end
local function cp(value)
    local h=A.host
    return h.to_cp and h.to_cp(raw(value))or raw(value)
end
local function form(row)
    local h=A.host
    local exact=row and row.id~=nil and row.variant~=nil
    return {server=row and row.seller and row.seller.server or h.server(),
        server_label=A.server_label(),
        currency=row and row.currency or h.currency(),
        name=not exact and buffer(row and row.name,1024)or nil,note=buffer('',4096),
        qty=buffer(row and row.qty or '',32),cost=buffer(row and row.buy_price or '',32),
        item_id=row and row.id,variant=row and row.variant,
        title=row and row.name,exact=exact}
end
function A.open_purchase(row)
    purchase=form(row);A.pending_purchase_popup='Записать покупку'
end
function A.purchases_header()
    local g,B=A.ui,A.host.imgui
    if g.button('Записать покупку',B.ImVec2(-1,0))and A.book_loaded and not A.book_busy then
        A.open_purchase()
    end
    if not A.book_loaded then g.wrapped(A.book_error or 'Закупки загружаются...')end
end
local function open_sale(lot)
    sale={server=lot.server,server_label=A.server_label(),currency=lot.currency,id=lot.id,title=lot.name,
        remaining=lot.remaining,qty=buffer('',32),net=buffer('',32),note=buffer('',4096)}
    A.pending_purchase_popup='Записать продажу'
end
function A.draw_purchases(rows,view)
    local g,B=A.ui,A.host.imgui
    if view.error then g.wrapped(view.error);return end
    if view.loading then g.wrapped('Закупки загружаются...');return end
    if #rows==0 then g.wrapped('Пока нет записей о покупках');return end
    g.list(rows,'pa_purchase_list',function(lot)
        g.caption(lot.name)
        g.wrapped('Цена: '..g.money(lot.unit_cost)..' '..lot.currency..' / шт.')
        g.wrapped('Остаток: '..g.money(lot.remaining)..' / '..g.money(lot.qty)..' шт.')
        g.caption(lot.note and lot.note~=''and lot.note or 'Без заметки')
        if lot.remaining>0 then
            if g.button('Записать продажу##pa_sell_'..lot.id,B.ImVec2(-1,0))then open_sale(lot)end
        else g.text('Партия закрыта')end
    end)
end
function A.purchase_footer(view)
    if view.error or view.loading then return end
    local g=A.ui;local currency=A.host.currency()
    g.wrapped('Вложено: '..g.money(view.invested)..' '..currency)
    g.wrapped('Прибыль по ручным записям: '..g.money(view.realized_profit)..' '..currency)
end
local function input(label,id,value,capacity,f)
    local h=A.host
    A.ui.wrapped(label)
    if f.pending or f.saved then A.ui.wrapped(cp(value))
    else h.imgui.InputText(h.utf8(id),value,capacity)end
end
local function can_save(f)
    if f.pending or f.saved then return false end
    if not scope(f)then f.error='Сервер или валюта изменились. Откройте форму заново.';return false end
    if not A.book_loaded then f.error=A.book_error or 'Журнал ещё загружается';return false end
    if A.book_busy then f.error='Сохранение уже идёт';return false end
    return true
end
local function submit(f,action)
    f.pending=true;f.error=nil
    local accepted,why=action(function(ok,result)
        f.pending=false;f.saved=ok==true
        if not ok then f.error=tostring(result or 'Не удалось сохранить запись')end
    end)
    if not accepted then f.pending=false;f.error=tostring(why or 'Не удалось сохранить запись')end
end
local function save_purchase()
    local f=purchase
    if not can_save(f)then return end
    local qty,cost=number(raw(f.qty),1),number(raw(f.cost),0)
    local name=f.exact and f.title or cp(f.name)
    if not qty or cost==nil or not name:find('%S')then
        f.error='Введите название, целое количество и цену. Цена 0 допустима.';return
    end
    local p={name=name,qty=qty,unit_cost=cost,note=cp(f.note)}
    if f.exact then p.item_id=f.item_id;p.variant=f.variant end
    submit(f,function(done)return A.record_purchase(p,done)end)
end
local function save_sale()
    local f=sale
    if not can_save(f)then return end
    local qty,net=number(raw(f.qty),1),number(raw(f.net),0)
    if not qty or qty>f.remaining or net==nil then
        f.error='Введите целое количество в пределах остатка и фактически полученную сумму.';return
    end
    submit(f,function(done)return A.record_sale(f.id,{qty=qty,net_total=net,note=cp(f.note)},done)end)
end
local function body(id,f,draw)
    local B=A.host.imgui;local g=A.ui
    g.wrapped(f.server_label..' | '..f.currency)
    local height=math.max(1,math.min(B.GetIO().DisplaySize.y*.4,B.GetTextLineHeight()*8))
    if B.BeginChild(id,B.ImVec2(0,height),false)then
        draw()
        if not scope(f)then g.wrapped('Сервер или валюта изменились. Откройте форму заново.')end
        if f.error then g.wrapped(f.error)end
        B.ScrollMouse(id,true)
    end
    B.EndChild()
end
local function save_button(f,label,id,action)
    if f.saved then A.ui.text('Записано')
    elseif f.pending then A.ui.text('Сохраняю...')
    elseif A.ui.button(label..id,A.host.imgui.ImVec2(-1,0))then action()end
end
function A.purchase_popups()
    local g=A.ui
    if A.pending_purchase_popup then
        A.host.open_popup(A.pending_purchase_popup);A.pending_purchase_popup=nil
    end
    g.popup('Записать покупку',function()
        if not purchase then return end
        local f=purchase
        body('pa_purchase_form',f,function()
            if f.exact then g.item_title({id=f.item_id,variant=f.variant,name=f.title})
            else input('Название','##pa_purchase_name',f.name,1024,f)end
            input('Количество, шт.','##pa_purchase_qty',f.qty,32,f)
            input('Цена за штуку (0 допустим)','##pa_purchase_cost',f.cost,32,f)
            input('Заметка','##pa_purchase_note',f.note,4096,f)
        end)
        save_button(f,'Сохранить покупку','##pa_purchase_save',save_purchase)
    end)
    g.popup('Записать продажу',function()
        if not sale then return end
        local f=sale
        body('pa_sale_form',f,function()
            g.wrapped(f.title)
            g.wrapped('Остаток: '..g.money(f.remaining)..' шт.')
            input('Продано, шт.','##pa_sale_qty',f.qty,32,f)
            input('Фактически получено всего (после комиссии)','##pa_sale_net',f.net,32,f)
            input('Заметка','##pa_sale_note',f.note,4096,f)
        end)
        save_button(f,'Сохранить продажу','##pa_sale_save',save_sale)
    end)
end
return A
end
