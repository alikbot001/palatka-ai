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
function A.draw_right()
    ready()
    local h=A.host;local B=h.imgui
    local visible=B.BeginChild('RightSidebar',B.ImVec2(h.sidebar_width and h.sidebar_width()or 0,-1))
    if visible then
        if button('Рассчитать')then
            local raw=h.input_string(input.budget)
            local budget=raw:match('^%d+$')and A.engine.integer(raw,0)
            local tax=tonumber(input.tax[0])
            if not budget or not tax or tax~=tax or tax<0 or tax>100 then
                A.error='Неверный бюджет или комиссия'
            else
                A.options.budget=budget;A.options.tax_bp=math.floor(tax*100+0.5);A.calculate()
            end
        end
        if A.busy and button('Отменить')then A.invalidate();A.status='Расчёт отменён'end
        text('Бюджет (0 = без лимита)')
        if B.InputText('##pa_budget',input.budget,32)then A.invalidate()end
        text('Комиссия, %')
        if B.InputFloat('##pa_tax',input.tax,0.1,1,'%.2f')then A.invalidate()end
        B.Separator()
        if button('Импорт JSON')then A.read_import()end
        wrapped('PalatkaMCR/import.json')
        if button('Кэш рынка Palatka')then A.read_market_cache()end
        local rows=A.current_results();local r=rows[A.selected]
        if r then
            B.Separator();wrapped(r.name)
            text('Объём: '..r.qty)
            text('Затраты: '..money(r.cost));text('Выручка: '..money(r.gross))
            text('Комиссия: '..money(r.fee));text('Прибыль ~'..money(r.profit))
            if button('Найти продавца')then h.find(r.seller.shop,r.seller.server)end
            if button('Найти скупщика')then h.find(r.buyer.shop,r.buyer.server)end
        end
        B.ScrollMouse('RightSidebar',true)
    end
    B.EndChild()
end
return A
end
