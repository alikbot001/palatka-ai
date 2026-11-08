-- Palatka AI 2.9.17: compact workspace and explicit script updates.
-- Additive UI layer. Existing shop, trading, preset and journal logic is untouched.
local V = DSP.ui21 or DSP.ui22
local M = DSP.mobile or {}
if not V or type(V.list_rows) ~= 'function' or type(V.tools) ~= 'function' then return false end
if V._compact_ui_2917_installed then return true end

-- Keep every screen reachable: the advanced navigation is a user preference,
-- not a deletion of the older sections or their saved state.
local PRIMARY = {
    palatka=true, lavki=true, arbitrage=true, promo=true,
    storage=true, logs=true, settings=true
}
local prior_rows = V.list_rows
V.list_rows = function(key, rows, height, draw, options)
    if key == 'navigation' and not DSP.settings.ui_advanced_menu then
        local compact = {}
        for _, item in ipairs(rows or {}) do
            if PRIMARY[item[1]] then compact[#compact+1] = item end
        end
        return prior_rows(key, compact, height, draw, options)
    end
    return prior_rows(key, rows, height, draw, options)
end

local function save_later()
    if M.defer_save then M.defer_save()
    elseif DSP.save_settings then DSP.save_settings() end
end
local function button(text, id, wide, primary)
    return V.button(text, 'ux2917_'..id, wide or -1, false, primary or false)
end
local function toggle(text, key, default)
    local current = DSP.settings[key]
    if current == nil then current = default or false end
    if V.text_button((current and '[x] ' or '[ ] ')..text, 'ux2917_toggle_'..key, -1, false, 44) then
        DSP.settings[key] = not current
        if key == 'dry_run' then
            DSP.settings.trade_mode = DSP.settings[key] and 'preview' or 'real'
        end
        if key == 'ui_advanced_menu' and V.reset_list then V.reset_list('navigation') end
        save_later()
    end
end
local function number(text, key, low, high, w)
    V.muted(text)
    if not M.compact_number then V.red('Числовой ввод недоступен');return end
    if M.compact_number(DSP.settings, key, 'ux2917_'..key, math.min(260, w), low) then
        local value = tonumber(DSP.settings[key]) or low
        DSP.settings[key] = math.max(low, math.min(high, math.floor(value)))
        if key == 'tax_bp' and DSP.market and DSP.market.invalidate_arbitrage then
            DSP.market.invalidate_arbitrage()
        end
        save_later()
    end
end

local updater = DSP.ui_updater or {status='idle'}
DSP.ui_updater = updater
local MANIFEST = 'https://raw.githubusercontent.com/alikbot001/palatka-ai/main/version.json'
local PAYLOAD = 'https://raw.githubusercontent.com/alikbot001/palatka-ai/main/updates/palatka_update.lua'
local function newer(a, b)
    local function parts(s)
        local x,y,z = tostring(s or ''):match('^(%d+)%.(%d+)%.(%d+)$')
        if not x then return nil end
        return {tonumber(x),tonumber(y),tonumber(z)}
    end
    local left,right = parts(a),parts(b)
    if not left or not right then return false end
    for i=1,3 do
        if left[i] ~= right[i] then return left[i] > right[i] end
    end
    return false
end
updater.newer = newer
local function fail(message)
    updater.status = 'error'
    updater.error = tostring(message or 'Неизвестная ошибка')
end
function updater.check()
    if updater.status == 'checking' or updater.status == 'downloading' then return false end
    if type(DSP.http_get) ~= 'function' then fail('Сетевой клиент недоступен');return false end
    updater.status = 'checking';updater.error = nil;updater.info = nil
    DSP.http_get(MANIFEST, function(body, err)
        if not body then fail('Не удалось проверить версию: '..tostring(err));return end
        local ok, data = pcall(decodeJson, body)
        if not ok or type(data) ~= 'table' then fail('GitHub вернул некорректный манифест');return end
        if type(data.version) ~= 'string' or not data.version:match('^%d+%.%d+%.%d+$')
            or data.url ~= PAYLOAD or data.mode ~= 'overlay'
            or type(data.size) ~= 'number' or data.size < 100 or data.size > 2000000 then
            fail('Манифест обновления не прошел проверку');return
        end
        updater.info = data
        updater.status = newer(data.version,DSP.version) and 'available' or 'uptodate'
    end)
    return true
end
local function save_package(data, version)
    if type(DSP.dir) ~= 'string' or DSP.dir == '' then return false,'Нет папки скрипта' end
    local final = DSP.dir..'/palatka_ota_'..version..'.lua'
    local tmp = final..'.tmp'
    local f, err = io.open(tmp,'wb')
    if not f then return false,err or 'Нет доступа к папке' end
    local written, write_error = f:write(data)
    local closed,close_error = f:close()
    if not written or not closed then
        pcall(os.remove,tmp)
        return false,write_error or close_error or 'Ошибка записи'
    end
    local moved,why = os.rename(tmp, final)
    if not moved then pcall(os.remove,tmp);return false,why or 'Ошибка переименования' end
    return true,final
end
function updater.install()
    local queue = DSP.auto or {}
    if queue.running or queue.buy_running or queue.sell_running then
        fail('Останови торговую очередь перед обновлением');return false
    end
    if updater.status ~= 'available' or type(updater.info) ~= 'table' then return false end
    if type(DSP.http_get) ~= 'function' then fail('Сетевой клиент недоступен');return false end
    local info = updater.info
    updater.status = 'downloading';updater.error = nil
    DSP.http_get(PAYLOAD, function(body,err)
        if not body then fail('Не удалось скачать обновление: '..tostring(err));return end
        if #body ~= info.size then fail('Размер обновления не совпадает с манифестом');return end
        if not body:find("PALATKA_UPDATE_VERSION = '"..info.version.."'",1,true) then
            fail('Версия загруженного файла не совпадает с манифестом');return
        end
        local compile,syntax_error = loadstring(body, '@palatka_ota_'..info.version)
        if not compile then fail('Синтаксическая ошибка обновления: '..tostring(syntax_error));return end
        local saved,path_or_error = save_package(body,info.version)
        if not saved then fail('Не удалось сохранить резервную копию: '..tostring(path_or_error));return end
        local ok,installer = pcall(compile)
        if not ok or type(installer) ~= 'function' then
            fail('Установщик не запустился: '..tostring(installer));return
        end
        local applied,result = pcall(installer,DSP)
        if not applied or result == false then
            fail('Установка завершилась ошибкой; файл сохранен: '..tostring(result));return
        end
        updater.status = 'installed'
        updater.installed_version = info.version
        updater.package_path = path_or_error
        if DSP.notify then DSP.notify('Palatka AI обновлена до '..info.version) end
    end)
    return true
end

local legacy_tools = V.tools
local sections = {
    {'Основные', 'general'}, {'Интерфейс','view'}, {'Торговля','trade'},
    {'Сканирование','scan'}, {'Рынок','market'}, {'Обновления','updates'},
    {'Расширенные','legacy'}
}
local function settings_home(w)
    V.muted('Основные функции и параметры. Остальные настройки сохранены в расширенном режиме.')
    for _,entry in ipairs(sections) do
        if button(entry[1], 'settings_'..entry[2], -1, entry[2]=='updates') then
            V.settings_group = entry[2]
            if V.reset_list then V.reset_list('ux2917_settings') end
        end
    end
end
local function settings_view(w)
    toggle('Полное меню (все 16 разделов)','ui_advanced_menu',false)
    toggle('Экономия ресурсов','fps_saver',false)
    toggle('Оценка торговли поверх игры','overlay_trade',true)
    toggle('Оценка лавки поверх игры','overlay_shop',true)
    local crag = DSP.settings.craglog or {}
    local open = crag.open == true
    if V.text_button((open and '[x] ' or '[ ] ')..'Мини-журнал',
        'ux2917_toggle_minijournal',-1,false,44) then
        crag.open = not open;DSP.settings.craglog = crag;save_later()
    end
    V.muted('Темы, прозрачность, размер текста и положение окон находятся в расширенных настройках.')
end
local function settings_trade(w)
    toggle('Проверка без реальной торговли (ТЕСТ)','dry_run',false)
    toggle('Показывать только прибыльные предложения','only_profit',false)
    toggle('Фильтр по ликвидности','liquid',false)
    number('Комиссия: 100 = 1%','tax_bp',0,10000,w)
    number('Маржа скупки, %','margin',0,100,w)
    number('Снижение цены продажи, %','undercut',0,100,w)
    number('Количество для скупки по умолчанию','auto_buy_qty',1,100000,w)
    V.muted('Режим ТЕСТ не отправляет команды торговли. Проверяй пресет перед запуском.')
end
local function settings_scan(w)
    toggle('Автоматический скан открытых лавок','auto_shop_scan',true)
    number('Максимум сохраненных лавок','max_local_shops',20,300,w)
    number('Срок актуальности скана, минут','local_offer_ttl_minutes',5,1440,w)
    number('История цен, дней','price_history_days',1,30,w)
    number('Тишина скана после пакета, мс','scan_quiet_ms',250,2500,w)
    number('Ожидание идентификации лавки, мс','identity_grace_ms',0,5000,w)
    V.muted('Изменения действуют для новых сканов; ранее записанные данные не удаляются.')
end
local function settings_market(w)
    local st = DSP.market and DSP.market.state or {}
    V.muted('Состояние API: '..tostring(st.status or 'неизвестно'))
    V.muted('Сервер: '..tostring(st.sid or DSP.settings.server or '?'))
    number('Обновление рыночных данных, сек (не менее 180)','refresh_seconds',180,86400,w)
    if button('Обновить рыночные цены','refresh_market',-1,true) then
        if DSP.market and DSP.market.pull and st.status ~= 'loading' then
            DSP.market.pull((DSP.detect_server and DSP.detect_server()) or st.sid or DSP.settings.server)
        end
    end
    V.muted('Обновление цен не меняет версию Palatka AI.')
end
local function settings_updates(w)
    V.text('Установлена версия: '..tostring(DSP.version or '?'))
    local state = updater.status
    if state == 'checking' then V.muted('Проверка GitHub...')
    elseif state == 'downloading' then V.muted('Загрузка и проверка файла...')
    elseif state == 'available' and updater.info then V.green('Новая версия: '..updater.info.version)
    elseif state == 'uptodate' then V.green('Установлена актуальная версия')
    elseif state == 'installed' then V.green('Установлено: '..tostring(updater.installed_version))
    elseif state == 'error' then V.red(tostring(updater.error))
    else V.muted('Проверка обновлений еще не выполнялась') end
    if state ~= 'checking' and state ~= 'downloading' then
        if button('Проверить GitHub','check_update',-1,true) then updater.check() end
    end
    if updater.info and type(updater.info.changelog) == 'table' then
        V.muted('Изменения:')
        for i=1,math.min(4,#updater.info.changelog) do
            V.text(V.fit(tostring(updater.info.changelog[i]),math.max(80,w-10)))
        end
    end
    if state == 'available' and updater.info then
        if button('Установить v'..updater.info.version,'install_update',-1,true) then
            V.open_popup('Установить обновление?','ux2917_update_confirm')
        end
    end
    V.muted('Обновление запускается только вручную. Перед установкой файл проверяется и сохраняется отдельно.')
end

local previous_popups = V.popups
V.popups = function()
    if previous_popups then previous_popups() end
    V.popup('Установить обновление?','ux2917_update_confirm',function()
        local v = updater.info and updater.info.version or '?'
        V.text('Установить Palatka AI v'..v..'?')
        V.muted('Настройки и пресеты не сбрасываются. Не обновляй во время активной торговой очереди.')
        if button('Отмена','update_cancel',120) then imgui.CloseCurrentPopup() end
        V.inline(6,160)
        if button('Установить','update_confirm',160,true) then
            imgui.CloseCurrentPopup()
            if DSP.auto and (DSP.auto.running or DSP.auto.buy_running or DSP.auto.sell_running) then
                fail('Останови торговую очередь перед обновлением')
            else updater.install() end
        end
    end,{w=480,h=230})
end

V.tools = function(screen)
    if screen ~= 'settings' then return legacy_tools(screen) end
    local group = V.settings_group or 'home'
    if group == 'legacy' then
        if button('К категориям настроек','legacy_back',-1) then
            V.settings_group = 'home'
            if V.reset_list then V.reset_list('ux2917_settings') end
        end
        return legacy_tools(screen)
    end
    V.heading('Настройки',function()
        if group ~= 'home' and button('Назад','settings_back',90) then
            V.settings_group = 'home'
            if V.reset_list then V.reset_list('ux2917_settings') end
        end
    end,100)
    V.list('ux2917_settings',function(w)
        local current = V.settings_group or 'home'
        if current == 'home' then settings_home(w)
        elseif current == 'general' then
            V.muted('Palatka AI · настройки по категориям')
            toggle('Расширенное меню','ui_advanced_menu',false)
            toggle('Безопасный тестовый режим','dry_run',false)
            if button('Перейти к обновлениям','goto_updates',-1,true) then V.settings_group='updates' end
        elseif current == 'view' then settings_view(w)
        elseif current == 'trade' then settings_trade(w)
        elseif current == 'scan' then settings_scan(w)
        elseif current == 'market' then settings_market(w)
        elseif current == 'updates' then settings_updates(w)
        end
    end,{footer=function()
        if button('Сохранить настройки','save_settings',175,true) then
            local ok,why = DSP.save_settings()
            if ok and DSP.save_ui_state then DSP.save_ui_state() end
            if DSP.notify then DSP.notify(ok and 'Настройки сохранены' or ('Ошибка сохранения: '..tostring(why))) end
        end
    end})
end

-- The home page intentionally prioritizes actions over duplicate dashboards.
V.home = function()
    V.heading('Palatka AI',function()
        if button('Обновления','home_updates',130,true) then
            V.settings_group='updates';V.set_screen('settings')
        end
    end,135)
    V.list('ux2917_home',function(w)
        V.muted('Версия '..tostring(DSP.version)..' · управление торговлей')
        local actions={
            {'Торговля','palatka'}, {'Лавки','lavki'},
            {'Арбитраж','arbitrage'}, {'Автопиар','promo'},
            {'Журнал','logs'}, {'Настройки','settings'}
        }
        local columns = w>=420 and 2 or 1
        local gap=8
        local bw=math.max(90,(w-gap*(columns-1))/columns)
        for i,entry in ipairs(actions) do
            if button(entry[1],'home_'..entry[2],bw,entry[2]=='palatka') then
                V.set_screen(entry[2])
            end
            if i%columns~=0 and i<#actions then V.inline(gap,bw) end
        end
        imgui.Separator()
        local st=DSP.market and DSP.market.state or {}
        V.muted('Рынок: '..tostring(st.status or 'неизвестно')..
            ' · Сервер '..tostring(st.sid or DSP.settings.server or '?'))
        if button('Обновить цены рынка','home_market_refresh',-1) then
            if DSP.market and DSP.market.pull and st.status~='loading' then
                DSP.market.pull((DSP.detect_server and DSP.detect_server()) or st.sid or DSP.settings.server)
            end
        end
        if updater.status == 'available' and updater.info then
            if button('Доступна версия '..updater.info.version,'home_new_version',-1,true) then
                V.settings_group='updates';V.set_screen('settings')
            end
        end
        V.muted('Дополнительные разделы включаются в Настройки / Интерфейс.')
    end,{footer=false})
end
V._compact_ui_2917_installed=true
DSP.version='2.9.17'
return true
