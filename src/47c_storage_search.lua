-- Search saved containers by item name; all totals are scoped to the
-- user's query, never the entire trunk. Works only with user-saved snapshots.
local S=DSP.storage

function S.search_library(query,lookup)
    local needle=DSP.lower(DSP.trim(query or ''))
    local report={
        query=needle, results={},storage_count=0,match_groups=0,
        known_qty=0,unknown_slots=0,priced_value=0,unpriced_groups=0,
        different_server=0
    }
    if needle=='' then return report end
    for _,entry in ipairs(S.library())do
        local snap=entry.snapshot
        local info=S.evaluate(snap,lookup)
        local hits={}
        local qty,unknown,value,unpriced=0,0,0,0
        for _,item in ipairs(info.rows or {})do
            if DSP.lower(tostring(item.name or '')):find(needle,1,true) then
                local known=tonumber(item.qty) or 0
                local missing=tonumber(item.unknown_slots) or 0
                local bid=not info.cross_server and tonumber(item.bid) or nil
                local estimated=bid and known*bid or nil
                hits[#hits+1]={
                    name=item.name, key=item.key,id=item.id,ench=item.ench,
                    qty=known,unknown_slots=missing,
                    unit_buy=bid,total_buy=estimated,
                    market_unavailable=info.cross_server
                }
                qty=qty+known
                unknown=unknown+missing
                if estimated then value=value+estimated
                elseif known>0 then unpriced=unpriced+1 end
            end
        end
        table.sort(hits,function(a,b)
            if a.qty~=b.qty then return a.qty>b.qty end
            return tostring(a.name)<tostring(b.name)
        end)
        local title_hit=DSP.lower(tostring(snap.title or '')):find(needle,1,true)~=nil
        if #hits>0 or title_hit then
            local line={
                index=entry.index,snapshot=snap,matched_items=hits,title_only=title_hit and #hits==0,
                known_qty=qty,unknown_slots=unknown,
                priced_value=value,unpriced_groups=unpriced,
                cross_server=info.cross_server
            }
            report.results[#report.results+1]=line
            report.storage_count=report.storage_count+1
            report.match_groups=report.match_groups+#hits
            report.known_qty=report.known_qty+qty
            report.unknown_slots=report.unknown_slots+unknown
            report.priced_value=report.priced_value+value
            report.unpriced_groups=report.unpriced_groups+unpriced
            if info.cross_server and #hits>0 then
                report.different_server=report.different_server+1
            end
        end
    end
    table.sort(report.results,function(a,b)
        if a.title_only~=b.title_only then return not a.title_only end
        if a.known_qty~=b.known_qty then return a.known_qty>b.known_qty end
        return tostring(a.snapshot.title)<tostring(b.snapshot.title)
    end)
    return report
end
