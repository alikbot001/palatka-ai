-- The native buy picker needs a name array, not just an ID dictionary.
return function(ids,field,existing)
    local rows,seen={},{}
    for _,row in ipairs(existing or{})do
        local name=row[field]
        if type(name)=='string'and name~=''and not seen[name]then
            rows[#rows+1]=row;seen[name]=true
        end
    end
    for _,name in pairs(ids)do
        if type(name)=='string'and name~=''and not seen[name]then
            seen[name]=true;rows[#rows+1]={[field]=name}
        end
    end
    table.sort(rows,function(a,b)return a[field]<b[field]end)
    return rows
end
