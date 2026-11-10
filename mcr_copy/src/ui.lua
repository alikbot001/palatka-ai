-- Render only through the original MCR mimgui instance, styles and child panels.
return function(A)
local input,body_view
local function text(s)A.host.imgui.Text(A.host.utf8(tostring(s)))end
local function wrapped(s)A.host.imgui.TextWrapped(A.host.utf8(tostring(s)))end
local function button(s,size)
    local h=A.host
    local clicked
    if size then clicked=h.imgui.Button(h.utf8(s),size)
    else clicked=h.imgui.Button(h.utf8(s))end
    return clicked and(not h.can_click or h.can_click())
end
local function money(n)
    local value=string.format('%.0f',n or 0)
    local sign,digits=value:match('^(-?)(%d+)$')
    if not digits then return value end
    local grouped=digits:reverse():gsub('(%d%d%d)','%1.'):reverse():gsub('^%.','')
    return sign..grouped
end
local function source(s)
    local labels={['local']='Скан в игре',['va-ta-cache']='Сохранённые цены рынка',
        ['market-helper']='Market Helper',['mcr-cloud']='Импорт MCR',import='Импорт файла'}
    return labels[s.source]or'Внешний снимок'
end
local function ready()
    if input then return end
    local B=A.host.imgui
    input={budget=B.new.char[32]('0'),tax=B.new.float(2)}
end
local function item_title(r)
    wrapped(r.name)
    local label='ID '..tostring(r.id)
    local level,embedded,extra=tostring(r.variant):match('^(%d+):(%d+)(.*)$')
    if level then
        if tonumber(level)>0 then label=label..' | Улучшение +'..level end
        if tonumber(embedded)>0 then label=label..' | Вложение #'..embedded end
        local labels={quality='Качество',strength='Прочность',wear='Износ'}
        label=label..extra:gsub(':([%a_]+)=([^:]+)',function(key,value)
            return' | '..(labels[key]or key)..': '..value
        end)
    elseif r.variant then label=label..' | Модификация: '..r.variant end
    wrapped(label)
end
local function age(at)
    local seconds=math.max(0,A.host.now()-at)
    if seconds<60 then return seconds..' с' end
    return math.floor(seconds/60)..' мин'
end
local function caption(s)
    local h=A.host;local B=h.imgui;local value=h.utf8(tostring(s):gsub('[%c]',' '))
    local width=math.max(1,B.GetContentRegionAvail().x)
    if B.CalcTextSize(value).x>width then
        repeat value=value:gsub('[%z\1-\127\194-\244][\128-\191]*$','')
        until value==''or B.CalcTextSize(value..'..').x<=width
        value=value..'..'
    end
    B.Text(value)
end
local function list(rows,id,draw,extra_lines)
    local B=A.host.imgui;local style=B.GetStyle()
    local padding=style.WindowPadding or{x=8,y=8}
    local width=math.max(1,B.GetContentRegionAvail().x-padding.x*2)
    local function lines(value)return math.max(1,math.ceil(B.CalcTextSize(A.host.utf8(value)).x/width))end
    local quote=lines('Купить в лавке #1000000000: 9.007.199.254.740.991')
    local profit=lines('Прибыль ~9.007.199.254.740.991 SA$')
    local count=lines('Количество: 1.000.000.000 шт.')
    local height=B.GetTextLineHeight()*(2+quote*2+profit+count+(extra_lines or 0))+
        B.GetFrameHeight()+style.ItemSpacing.y*9+padding.y*2
    A.vertical_list.draw(B,id,rows,height,A.body_height,draw,A.reset_body_scroll)
end
local function quote(label,shop,price,currency)
    wrapped(label)
    wrapped('Лавка #'..shop.shop..(shop.owner and shop.owner~=''and' | '..shop.owner or''))
    wrapped(money(price)..' '..currency..' за шт.')
    wrapped(source(shop)..' | Снимку '..age(shop.at))
end
local function details(r)
    local B=A.host.imgui
    item_title(r);A.host.imgui.Separator()
    quote('1. Купить у продавца',r.seller,r.buy_price,r.currency)
    wrapped('Есть у продавца: '..(r.seller_qty and money(r.seller_qty)..' шт.'or'неизвестно'))
    if button('Найти продавца #'..r.seller.shop..'##pa_find_buy',B.ImVec2(-1,0))then A.track_selected('buy')end
    A.host.imgui.Separator()
    quote('2. Сдать в скупку',r.buyer,r.sell_price,r.currency)
    wrapped('Скупщик принимает: '..(r.buyer_qty and money(r.buyer_qty)..' шт.'or'неизвестно'))
    if button('Найти скупку #'..r.buyer.shop..'##pa_find_sell',B.ImVec2(-1,0))then A.track_selected('sell')end
    A.host.imgui.Separator()
    wrapped('3. Расчёт на '..money(r.qty)..' шт.')
    wrapped('Затраты: '..money(r.cost)..' '..r.currency)
    wrapped('Выручка: '..money(r.gross)..' '..r.currency)
    wrapped('Комиссия: '..money(r.fee)..' '..r.currency)
    wrapped('После комиссии: '..money(r.net or(r.gross-r.fee))..' '..r.currency)
    B.Separator()
    wrapped('Расчёт по снимкам. Проверьте цену и остаток в игре. Кнопки отмечают лавки этого товара; сделки выполняются вручную.')
end
local function entry(r,index)
    local B=A.host.imgui
    caption(r.name);caption('ID '..r.id..' | '..r.currency..' за шт.')
    wrapped('Купить в лавке #'..r.seller.shop..': '..money(r.buy_price))
    wrapped('Сдать в лавку #'..r.buyer.shop..': '..money(r.sell_price))
    wrapped('Прибыль: ~'..money(r.profit)..' '..r.currency)
    wrapped('Объём: '..money(r.qty)..' шт.')
    if button('Посмотреть расчёт##pa_route_'..index,B.ImVec2(-1,0))then A.select_route(index)end
end
local function tabs()
    local B=A.host.imgui;local keys={'routes','resale','purchases'}
    local labels={'Лавки','Рынок','Покупки'}
    local width=math.max(1,(B.GetContentRegionAvail().x-B.GetStyle().ItemSpacing.x*2)/3)
    for i,key in ipairs(keys)do
        if i>1 then B.SameLine()end
        if B.ButtonClickable((A.workspace_tab or'routes')~=key,A.host.utf8(labels[i]..'##pa_tab_'..key),B.ImVec2(width,0))
            and(not A.host.can_click or A.host.can_click())then A.workspace_tab=key end
    end
end
function A.draw_center()
    local h=A.host;local B=h.imgui
    local space=B.GetContentRegionAvail()
    local rail=h.sidebar_width and h.sidebar_width()or 0
    local gap=B.GetStyle().ItemSpacing.x
    local width=math.max(1,math.min(h.center_width and h.center_width()or space.x,space.x-rail-gap))
    local visible=B.BeginChild('Central',B.ImVec2(width,-1),true)
    if visible then
        tabs()
        local tab=A.workspace_tab or'routes'
        local rows=tab=='routes'and A.current_results()or A.workspace_rows and A.workspace_rows(tab)or{}
        local selected=tab=='routes'and rows[A.selected]or tab=='resale'and rows[A.resale_selected]
        local show_details=selected and(tab=='routes'and A.route_details or tab=='resale'and A.resale_details)
        B.CenterText(h.utf8(tab=='resale'and'Перепродажа'or tab=='purchases'and'Мои закупки'or'Арбитраж'))
        wrapped(A.server_label())
        if show_details and button('< Все варианты##pa_back',B.ImVec2(-1,0))then
            A.route_details=false;A.resale_details=false;show_details=false
        end
        if tab=='purchases'and A.purchases_header then A.purchases_header()end
        B.Separator()
        local line=B.GetTextLineHeight()
        local gap_y=B.GetStyle().ItemSpacing.y
        local footer=line*(tab=='purchases'and 4 or 2)+gap_y*4
        if show_details then
            local available_width=math.max(1,B.GetContentRegionAvail().x)
            local function lines(s)return math.ceil(B.CalcTextSize(h.utf8(s)).x/available_width)+1 end
            footer=line*(lines('План: '..money(selected.qty)..' шт.')+
                lines('Прибыль: ~'..money(selected.profit)..' '..selected.currency))+gap_y*4
        end
        local body_height=math.max(1,B.GetContentRegionAvail().y-footer)
        A.body_height=body_height
        if B.BeginChild('pa_arb_body',B.ImVec2(0,body_height),false)then
            local view=h.server()..'/'..A.generation..'/'..tab..'/'..(tab=='purchases'and(A.book_revision or 0)or 0)..'/'..
                (show_details and'details/'..tostring(tab=='routes'and A.selected or A.resale_selected)or'list')
            A.reset_body_scroll=body_view~=view
            if A.reset_body_scroll then B.SetScrollY(0);body_view=view end
            if tab~='routes'and A.workspace_body then A.workspace_body(tab,rows,selected,show_details)
            elseif show_details then details(selected)
            elseif #rows==0 then
                if A.busy then wrapped('Обновляю цены и рассчитываю варианты...')
                else
                    wrapped('Вариантов пока нет')
                    wrapped('Нажмите «Расчёт», чтобы получить цены и найти варианты. Откройте лавки для сохранения своих снимков. Дополнительные источники — справа.')
                end
            else
                list(rows,'pa_route_row',entry)
            end
            if A.error then wrapped('Ошибка: '..A.error)end
            if A.notice then wrapped(A.notice)end
            B.ScrollMouse('pa_arb_body',true)
        end
        B.EndChild()
        if show_details then
            wrapped('План: '..money(selected.qty)..' шт.')
            wrapped('Прибыль: ~'..money(selected.profit)..' '..selected.currency)
        else
            if tab=='purchases'and A.purchase_footer then A.purchase_footer(A.current_book_view or{})
            else wrapped('Вариантов: '..#rows..'. Листайте вниз.')end
        end
    end
    B.EndChild()
end
local function calculate()
    local h=A.host
    local raw=h.input_string(input.budget)
    local budget=raw:match('^%d+$')and A.engine.integer(raw,0)
    local tax=tonumber(input.tax[0])
    if not budget or not tax or tax~=tax or tax<0 or tax>100 then
        A.error='Неверный бюджет или комиссия'
    else
        if A.apply_resale_settings then
            local valid,why=A.apply_resale_settings()
            if not valid then A.error=why;return end
        end
        A.options.budget=budget;A.options.tax_bp=math.floor(tax*100+0.5);A.calculate()
    end
end
local function tile(id,label,icon,action,height)
    local h=A.host;local B=h.imgui
    if B.Button(icon..'##pa_rail_'..id,B.ImVec2(-1,height))and(not h.can_click or h.can_click())then action()end
    local width=math.max(1,B.GetContentRegionAvail().x-2)
    local caption=h.utf8(label)
    if B.CalcTextSize(caption).x>width then
        repeat caption=caption:gsub('[%z\1-\127\194-\244][\128-\191]*$','')
        until caption==''or B.CalcTextSize(caption..'..').x<=width
        caption=caption..'..'
    end
    B.CenterText(caption);B.Spacing()
end
local function settings()
    local B=A.host.imgui
    local height=math.min(B.GetIO().DisplaySize.y*.45,B.GetTextLineHeight()*10)
    if B.BeginChild('pa_arb_settings',B.ImVec2(0,height),false)then
    text('Бюджет (0 = без лимита)')
    if B.InputText('##pa_budget',input.budget,32)then A.follow_market=false;A.invalidate()end
    text('Комиссия, %')
    if B.InputFloat('##pa_tax',input.tax,0.1,1,'%.2f')then A.follow_market=false;A.invalidate()end
    B.Separator()
    if A.resale_settings then A.resale_settings()end
    B.ScrollMouse('pa_arb_settings',true)
    end
    B.EndChild()
end
local function sources()
    wrapped('Market Helper: получить лавки текущего мобильного сервера без ключа MCR. Это внешний источник; снимки могут отставать от игры.')
    if button('Обновить лавки и цены')then
        if A.follow_market then A.calculate(true)else A.refresh_market(function()end,true)end
    end
    A.host.imgui.Separator()
    wrapped('Скан в игре: откройте лавку, чтобы сохранить её товары и время наблюдения.')
    A.host.imgui.Separator()
    wrapped('Сохранённые цены: загрузить снимки из базы Palatka для текущего сервера. Эта кнопка не обновляет цены в интернете.')
    if button('Загрузить сохранённые цены')then A.read_market_cache()end
    A.host.imgui.Separator()
    wrapped('Импорт: прочитать подготовленный файл PalatkaMCR/import.json. Данные других серверов не участвуют в текущем расчёте.')
    if button('Импортировать файл')then A.read_import()end
end
local function popup(title,draw)
    local B=A.host.imgui
    local screen=B.GetIO().DisplaySize
    B.SetNextWindowPos(B.ImVec2(screen.x/2,screen.y/2),B.Cond.Appearing,B.ImVec2(0.5,0.5))
    A.host.draw_popup(title,draw)
end
function A.draw_right()
    ready()
    local h=A.host;local B=h.imgui
    local space=B.GetContentRegionAvail()
    local width=math.max(1,math.min(h.sidebar_width and h.sidebar_width()or space.x,space.x))
    local visible=B.BeginChild('RightSidebar',B.ImVec2(width,-1))
    if visible then
        local icons=h.icons or{}
        local actions={}
        local function add(id,label,icon,action)actions[#actions+1]={id,label,icon,action}end
        if A.busy or A.resale_busy then
            add('stop','Стоп',icons.STOP or'X',function()A.follow_market=false;A.invalidate();A.status='Расчёт отменён'end)
        else add('calculate','Расчёт',icons.CALCULATOR or'=',calculate)end
        add('settings','Параметры',icons.GEAR or'*',function()h.open_popup('Параметры арбитража')end)
        add('sources','Источники',icons.DATABASE or'B',function()h.open_popup('Источники цен')end)
        if (A.workspace_tab==nil or A.workspace_tab=='routes')and A.selected_route()then
            add('route','Маршрут',icons.LOCATION_DOT or'>',function()A.route_details=true end)
        end
        local area=B.GetContentRegionAvail()
        local spacing=B.GetStyle().ItemSpacing.y
        local overhead=B.GetTextLineHeight()+3*spacing
        local native=h.sidebar_button_height and h.sidebar_button_height()or 60
        local minimum=math.min(native,math.max(24,math.floor(native*0.6)))
        local per=#actions
        local pager=B.GetTextLineHeight()+2*spacing
        if (minimum+overhead)*per>area.y then
            per=math.max(1,math.floor((area.y-pager)/(minimum+overhead)))
        else pager=0 end
        local pages=math.ceil(#actions/per)
        A.rail_page=math.max(1,math.min(A.rail_page or 1,pages))
        local first=(A.rail_page-1)*per+1
        local count=math.min(per,#actions-first+1)
        local height=math.max(1,math.min(native,math.floor((area.y-pager)/count-overhead)))
        for i=first,first+count-1 do
            local v=actions[i];tile(v[1],v[2],v[3],v[4],height)
        end
        if pages>1 then
            local half=math.max(1,(area.x-B.GetStyle().ItemSpacing.x)/2)
            if B.Button('<##pa_rail_prev',B.ImVec2(half,0))and(not h.can_click or h.can_click())then A.rail_page=math.max(1,A.rail_page-1)end
            B.SameLine()
            if B.Button('>##pa_rail_next',B.ImVec2(half,0))and(not h.can_click or h.can_click())then A.rail_page=math.min(pages,A.rail_page+1)end
        end
        popup('Параметры арбитража',settings)
        popup('Источники цен',sources)
        if A.workspace_popups then A.workspace_popups()end
        if A.purchase_popups then A.purchase_popups()end
        B.ScrollMouse('RightSidebar',true)
    end
    B.EndChild()
end
A.ui={text=text,wrapped=wrapped,button=button,money=money,item_title=item_title,
    caption=caption,age=age,list=list,popup=popup,quote=quote}
return A
end
