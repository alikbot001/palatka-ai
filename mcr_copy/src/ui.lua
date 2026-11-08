-- Render only through the original MCR mimgui instance, styles and child panels.
return function(A)
local input
local function text(s)A.host.imgui.Text(A.host.utf8(tostring(s)))end
local function wrapped(s)A.host.imgui.TextWrapped(A.host.utf8(tostring(s)))end
local function button(s)
    local h=A.host
    return h.imgui.Button(h.utf8(s)) and (not h.can_click or h.can_click())
end
local function money(n)
    local value=string.format('%.0f',n or 0)
    local sign,digits=value:match('^(-?)(%d+)$')
    if not digits then return value end
    local grouped=digits:reverse():gsub('(%d%d%d)','%1.'):reverse():gsub('^%.','')
    return sign..grouped
end
local function source(s)
    return s.source=='local'and'скан' or s.source
end
local function ready()
    if input then return end
    local B=A.host.imgui
    input={budget=B.new.char[32]('0'),tax=B.new.float(2)}
end
function A.draw_center()
    local h=A.host;local B=h.imgui
    local width=h.center_width and h.center_width() or 0
    local visible=B.BeginChild('Central',B.ImVec2(width,-1),true)
    if visible then
        B.CenterText(h.utf8('Арбитраж'));B.Separator()
        text('Сервер: '..h.server()..' | '..A.status)
        wrapped('Оценка по объявлениям. Наличие товара и цену проверяйте в игре.')
        local rows=A.current_results()
        if #rows==0 then
            if A.busy then text('Расчёт...')
            else wrapped('Откройте лавки, чтобы сохранить их товары. Затем нажмите «Рассчитать». Внешние снимки можно добавить кнопкой «Импорт JSON».')end
        else
            local pages=math.max(1,math.ceil(#rows/8))
            A.page=math.min(A.page,pages)
            if button('<##pa_page')then A.page=math.max(1,A.page-1)end
            B.SameLine();text(A.page..' / '..pages);B.SameLine()
            if button('>##pa_page')then A.page=math.min(pages,A.page+1)end
            for index=(A.page-1)*8+1,math.min(#rows,A.page*8)do
                local r=rows[index]
                if button(r.name..' | '..r.qty..' шт.##pa_route_'..index)then A.selected=index end
                text('Купить #'..r.seller.shop..': '..money(r.buy_price)..' -> продать #'..r.buyer.shop..': '..money(r.sell_price))
                text('Затраты '..money(r.cost)..' | прибыль ~'..money(r.profit)..' '..r.currency)
                if index==A.selected then
                    text('Выручка: '..money(r.gross)..' | Комиссия: '..money(r.fee))
                end
                text(source(r.seller)..' / '..source(r.buyer)..' | возраст '..
                    math.max(0,h.now()-r.seller.at)..' / '..math.max(0,h.now()-r.buyer.at)..' с')
                B.Separator()
            end
        end
        if A.error then wrapped('Ошибка: '..A.error)end
        B.ScrollMouse('Central',true)
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
        A.options.budget=budget;A.options.tax_bp=math.floor(tax*100+0.5);A.calculate()
    end
end
local function tile(id,label,icon,action)
    local h=A.host;local B=h.imgui
    local height=h.sidebar_button_height and h.sidebar_button_height()or 60
    if B.Button(icon..'##pa_rail_'..id,B.ImVec2(-1,height))and(not h.can_click or h.can_click())then action()end
    B.CenterText(h.utf8(label));B.Spacing()
end
local function settings()
    local B=A.host.imgui
    text('Бюджет (0 = без лимита)')
    if B.InputText('##pa_budget',input.budget,32)then A.invalidate()end
    text('Комиссия, %')
    if B.InputFloat('##pa_tax',input.tax,0.1,1,'%.2f')then A.invalidate()end
    B.Separator()
    wrapped('Импорт внешних снимков: PalatkaMCR/import.json')
    wrapped('База: сохранённые цены Palatka. Чтение кэша не обновляет данные в сети.')
end
function A.draw_right()
    ready()
    local h=A.host;local B=h.imgui
    local visible=B.BeginChild('RightSidebar',B.ImVec2(h.sidebar_width and h.sidebar_width()or 0,-1))
    if visible then
        local icons=h.icons or{}
        if A.busy then
            tile('stop','Стоп',icons.STOP or'X',function()A.invalidate();A.status='Расчёт отменён'end)
        else tile('calculate','Расчёт',icons.CALCULATOR or'=',calculate)end
        tile('settings','Параметры',icons.GEAR or'*',h.open_settings)
        tile('cache','База',icons.DATABASE or'B',A.read_market_cache)
        tile('import','Импорт',icons.FILE_IMPORT or'+',A.read_import)
        local rows=A.current_results();local r=rows[A.selected]
        if r then
            tile('seller','Продавец',icons.LOCATION_DOT or'>',function()h.find(r.seller.shop,r.seller.server)end)
            tile('buyer','Скупщик',icons.LOCATION_CROSSHAIRS or'>',function()h.find(r.buyer.shop,r.buyer.server)end)
        end
        h.draw_settings_popup(settings)
        B.ScrollMouse('RightSidebar',true)
    end
    B.EndChild()
end
return A
end
