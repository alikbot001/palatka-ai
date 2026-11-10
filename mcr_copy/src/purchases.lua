-- Manual purchase/sale records. These entries are never server confirmations.
return function(E)
    local P={}
    local MAX=E.MAX
    local function integer(v,minimum,maximum)
        return type(v)=='number' and v==v and v%1==0 and v>=minimum and v<=(maximum or MAX)
    end
    local function text(v,limit)
        return type(v)=='string' and #v<=limit and v:find('%S') and not v:find('[%z\031]')
    end
    local function fields(v,allowed)
        if type(v)~='table' or getmetatable(v)~=nil then return false end
        for k in pairs(v)do if not allowed[k]then return false end end
        return true
    end
    local function fieldset(names)
        local t={};for name in names:gmatch('%S+')do t[name]=true end;return t
    end
    local state_fields=fieldset('schema next_id lots sales')
    local lot_fields=fieldset('id server currency name item_id variant unit_cost qty remaining at note')
    local sale_fields=fieldset('id lot_id qty net_total cost profit at note')
    local buy_fields=fieldset('server currency name item_id variant unit_cost qty at note')
    local sell_fields=fieldset('qty net_total at note')
    local function clone(row)
        local out={};for k,v in pairs(row)do out[k]=v end;return out
    end
    local function dense(rows,limit)
        if type(rows)~='table' or getmetatable(rows)~=nil or #rows>limit then return false end
        local count=0
        for k in pairs(rows)do
            if not integer(k,1,#rows)then return false end
            count=count+1
        end
        return count==#rows
    end
    local function product(a,b)
        if b==0 or a<=math.floor(MAX/b)then return a*b end
    end
    local function add(a,b)
        if b>=0 and a<=MAX-b or b<0 and a>=-MAX-b then return a+b end
    end
    local function note(v)return v==nil or type(v)=='string' and #v<=4096 and not v:find('%z')end
    local function lot_valid(l)
        return fields(l,lot_fields) and integer(l.id,1) and text(l.server,128) and text(l.currency,64)
            and text(l.name,1024) and (l.item_id==nil or text(l.item_id,128))
            and (l.variant==nil or text(l.variant,128)) and integer(l.unit_cost,0)
            and integer(l.qty,1) and integer(l.remaining,0,l.qty) and integer(l.at,1) and note(l.note)
            and product(l.unit_cost,l.qty)~=nil
    end
    function P.new()return{schema=1,next_id=1,lots={},sales={}}end
    function P.validate(pack)
        if not fields(pack,state_fields) or pack.schema~=1 or not integer(pack.next_id,1,2501)
            or not dense(pack.lots,500) or not dense(pack.sales,2000)then return nil,'invalid purchase ledger schema'end
        local out=P.new();out.next_id=pack.next_id
        local ids,lots,sold={},{},{}
        local previous=0
        for _,l in ipairs(pack.lots)do
            if not lot_valid(l) or l.id<=previous or l.id>=pack.next_id then return nil,'invalid purchase lot'end
            ids[l.id]=true;lots[l.id]=l;sold[l.id]=0;previous=l.id
            out.lots[#out.lots+1]=clone(l)
        end
        previous=0
        for _,s in ipairs(pack.sales)do
            if not fields(s,sale_fields) or not integer(s.id,1) or s.id<=previous or ids[s.id]
                or s.id>=pack.next_id or not integer(s.lot_id,1) or not integer(s.qty,1)
                or not integer(s.net_total,0) or not integer(s.cost,0) or not integer(s.profit,-MAX)
                or not integer(s.at,1) or not note(s.note)then return nil,'invalid recorded sale'end
            local l=lots[s.lot_id]
            if not l or s.id<=l.id or s.at<l.at or s.qty>l.qty-sold[l.id]then return nil,'invalid sale allocation'end
            local cost=product(l.unit_cost,s.qty)
            if cost==nil or cost~=s.cost or s.net_total-cost~=s.profit then return nil,'conflicting sale totals'end
            ids[s.id]=true;sold[l.id]=sold[l.id]+s.qty;previous=s.id
            out.sales[#out.sales+1]=clone(s)
        end
        if #pack.lots+#pack.sales~=pack.next_id-1 then return nil,'missing ledger IDs'end
        for id=1,pack.next_id-1 do if not ids[id]then return nil,'missing ledger ID'end end
        for _,l in ipairs(pack.lots)do
            if l.remaining~=l.qty-sold[l.id]then return nil,'conflicting remaining quantity'end
        end
        return out
    end
    local function identity(v)
        if type(v)=='number' and integer(v,0)then return string.format('%.0f',v)end
        return v
    end
    function P.buy(state,input)
        local out,err=P.validate(state);if not out then return nil,err end
        if #out.lots>=500 then return nil,'purchase lot capacity reached'end
        if not fields(input,buy_fields)then return nil,'invalid purchase input'end
        local l=clone(input);l.id=out.next_id;l.remaining=l.qty
        l.item_id=identity(l.item_id);l.variant=identity(l.variant)
        if not lot_valid(l)then return nil,'invalid purchase values'end
        out.lots[#out.lots+1]=l;out.next_id=out.next_id+1
        return out,clone(l)
    end
    function P.sell(state,lot_id,input)
        local out,err=P.validate(state);if not out then return nil,err end
        if #out.sales>=2000 then return nil,'recorded sale capacity reached'end
        if not integer(lot_id,1) or not fields(input,sell_fields) or not integer(input.qty,1)
            or not integer(input.net_total,0) or not integer(input.at,1) or not note(input.note)then
            return nil,'invalid sale input'
        end
        local lot
        for _,l in ipairs(out.lots)do if l.id==lot_id then lot=l;break end end
        if not lot or input.qty>lot.remaining or input.at<lot.at then return nil,'sale exceeds available lot or time'end
        local cost=product(lot.unit_cost,input.qty)
        if cost==nil then return nil,'sale cost overflow'end
        local s={id=out.next_id,lot_id=lot_id,qty=input.qty,net_total=input.net_total,
            cost=cost,profit=input.net_total-cost,at=input.at,note=input.note}
        lot.remaining=lot.remaining-s.qty
        out.sales[#out.sales+1]=s;out.next_id=out.next_id+1
        return out,clone(s)
    end
    local function view_error(message)return{lots={},error=message},message end
    function P.view(state,server,currency)
        local pack,err=P.validate(state);if not pack then return view_error(err)end
        if not text(server,128) or not text(currency,64)then return view_error('invalid ledger scope')end
        local out={lots={},invested=0,realized_profit=0,sold_qty=0};local selected={}
        for _,l in ipairs(pack.lots)do
            if l.server==server and l.currency==currency then
                out.invested=add(out.invested,product(l.unit_cost,l.remaining))
                if out.invested==nil then return view_error('invested total overflow')end
                out.lots[#out.lots+1]=l;selected[l.id]=true
            end
        end
        for _,s in ipairs(pack.sales)do
            if selected[s.lot_id]then
                out.realized_profit=add(out.realized_profit,s.profit);out.sold_qty=add(out.sold_qty,s.qty)
                if out.realized_profit==nil or out.sold_qty==nil then return view_error('recorded sale total overflow')end
            end
        end
        table.sort(out.lots,function(a,b)
            if (a.remaining>0)~=(b.remaining>0)then return a.remaining>0 end
            if a.at~=b.at then return a.at>b.at end
            return a.id>b.id
        end)
        return out
    end
    function P.evidence(state,server,currency,now)
        local pack,err=P.validate(state);if not pack then return{},err end
        if not text(server,128) or not text(currency,64) or not integer(now,1)then return{},'invalid evidence scope/time'end
        local lots,out={},{}
        for _,l in ipairs(pack.lots)do
            if l.server==server and l.currency==currency and l.item_id and l.variant then lots[l.id]=l end
        end
        for _,s in ipairs(pack.sales)do
            local l=lots[s.lot_id]
            if l and s.net_total>0 and s.at<=now and now-s.at<=604800 then
                local key=l.item_id..'\031'..l.variant..'\031'..l.currency
                local row=out[key] or {events=0,qty=0,last_at=0,valid_until=MAX}
                local qty=add(row.qty,s.qty)
                if not qty then return{},'own sale quantity overflow'end
                local expiry=s.at<=MAX-604800 and s.at+604800 or MAX
                row.events=row.events+1;row.qty=qty;row.last_at=math.max(row.last_at,s.at)
                row.valid_until=math.min(row.valid_until,expiry);out[key]=row
            end
        end
        return out
    end
    return P
end
