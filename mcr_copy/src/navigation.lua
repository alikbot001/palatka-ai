-- Refresh the snapshot before sending a route; the feed cannot prove live stock.
return function(A)
local pending
local function owner(value)
    return tostring(value or''):lower():match('^%s*(.-)%s*$')
end
local function fresh(shop,h)
    local now=h.now()
    return shop and type(shop.at)=='number'and shop.at>0 and shop.at<=now
        and now-shop.at<=(A.options.ttl or 3600)
end
function A.navigate(number,expected_owner,server)
    if type(number)=='table'then
        local shop=number
        number,expected_owner,server=shop.shop,shop.owner,shop.server
    end
    local h=A.host
    number=A.engine.integer(number,1,1000000000)
    server=tostring(server or'')
    local function reject(message)
        A.error=message
        if h.notify then h.notify(message)end
        return false
    end
    if pending then return reject('Проверка лавки уже выполняется')end
    if not number or server==''or server~=h.server()then return reject('Сервер или номер лавки изменился')end
    local key=server..'/'..number
    local before=A.state.shops[key]
    expected_owner=owner(expected_owner)
    if expected_owner==''then return reject('Неизвестен владелец выбранной лавки')end
    if not fresh(before,h)then return reject('Нет свежего снимка выбранной лавки')end
    if before.owner_conflict or owner(before.owner)~=expected_owner then
        return reject('Изменился владелец лавки; выберите её заново')
    end
    if type(A.refresh_market)~='function'then return reject('Не удалось обновить базу лавок')end
    local request={}
    pending=request;A.error=nil;A.status='Проверяю владельца лавки...'
    if h.notify then h.notify(A.status)end
    A.refresh_market(function(ok,err,receipt)
        if pending~=request then return end
        pending=nil
        if server~=h.server()then reject('Сервер изменился');return end
        if not ok then reject('Не удалось проверить лавку: '..tostring(err or'нет ответа'));return end
        local verified=false
        if type(receipt)=='table'and receipt.schema==1 and type(receipt.shops)=='table'then
            for _,shop in ipairs(receipt.shops)do
                if type(shop)=='table'and shop.server==server and shop.shop==number then
                    if shop.owner_conflict or owner(shop.owner)~=expected_owner then
                        reject('Изменился владелец лавки; выберите её заново');return
                    end
                    if not fresh(shop,h)then reject('Нет свежего снимка выбранной лавки');return end
                    verified=true
                end
            end
        end
        if not verified then reject('Ответ базы не подтвердил выбранную лавку');return end
        local after=A.state.shops[key]
        if not fresh(after,h)then reject('Нет свежего снимка выбранной лавки');return end
        if after.owner_conflict or owner(after.owner)~=expected_owner then
            reject('Изменился владелец лавки; выберите её заново');return
        end
        h.find(number,server)
        A.status='Маршрут по снимку лавки; наличие товара проверьте на месте'
    end,true)
    return true
end
end
