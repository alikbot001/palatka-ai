-- v2.9.3 statistics screen override. Keeps the legacy settings module untouched.
local V,M,C=DSP.ui22,DSP.mobile,DSP.craglog
if V._stats_v293 then return true end
V._stats_v293=true
local old_tools=V.tools
local function b(s,id,w,on)return V.button(s,'stats293_'..id,w,on,false,38)end
local function statistics()
    V.heading('Статистика ларцов / наград')
    V.stats293_period=V.stats293_period or DSP.settings.stats_mode or'day'
    local periods={{'hour','Час'},{'day','День'},{'week','Неделя'},{'month','Месяц'},{'all','Всё'}}
    local pw=math.max(58,(imgui.GetContentRegionAvail().x-24)/5)
    for i,p in ipairs(periods)do
        if b(p[2],'period_'..p[1],pw,V.stats293_period==p[1])then
            V.stats293_period=p[1];DSP.settings.stats_mode=p[1]
            if M.defer_save then M.defer_save()end
        end
        if i<#periods then V.inline(6,pw)end
    end
    local query=V.search('stats293','Поиск ларца / награды',-1)
    local s=C.drop_sales_stats(V.stats293_period,query)
    V.green('Выпало: '..tostring(s.dropped)..' шт. · Продано: '..tostring(s.sold)..' шт.')
    if s.inventory_ready then
        V.text('Фактически в последнем скане инвентаря: '..tostring(s.inventory_total)..' шт.')
    else
        V.muted('Инвентарь ещё не сканирован: фактическое количество не подменяем расчётом.')
    end
    V.muted('Расчётный остаток: '..tostring(s.journal_balance)..' шт. (известные награды минус учтённые продажи)')
    if s.approx then V.muted('~ В части чеков неизвестно количество проданного: остаток может быть завышен.')end
    V.muted('Разница со сканом не означает пропажу: возможны продажи без точного чека и другие операции.')
    if DSP.auto and not DSP.auto.scanning and b('Обновить фактический инвентарь','scan_inventory',260,true)then
        local ok=DSP.auto.scan_inventory()
        if ok==false then V.stats293_error='Сканирование сейчас недоступно'else V.stats293_error=nil end
    elseif DSP.auto and DSP.auto.scanning then
        V.muted('Сканирование инвентаря...')
    end
    if V.stats293_error then V.red(V.stats293_error)end
    V.list_rows('stats293_'..V.stats293_period,s.items,86,function(r,i)
        V.row('row_'..i,86,function(w,x,y)
            local name=r.name..((tonumber(r.ench)or 0)>0 and(' (+'..r.ench..')')or'')
            V.at(x,y+1);V.text(V.fit(name,w-12))
            V.at(x,y+29);V.muted(V.fit('Выпало '..r.dropped..' · Продано '..r.sold..
                (r.sold_exact and''or'~')..' · Остаток журнала '..r.journal_balance,w-12))
            V.at(x,y+56)
            if s.inventory_ready then
                V.green(V.fit('Фактически сейчас: '..r.inventory..' шт. · оценка дропа ~ '..DSP.money(r.estimated or 0),w-12))
            else
                V.muted(V.fit('Факт: нужен скан инвентаря · оценка дропа ~ '..DSP.money(r.estimated or 0),w-12))
            end
        end)
    end,{count=#s.items,footer=function()
        V.muted('Факт берётся только из собственного скана инвентаря; журнал не выдаётся за инвентарь.')
    end})
end
function V.tools(screen)
    if screen=='stats' then return statistics() end
    return old_tools(screen)
end
return true
