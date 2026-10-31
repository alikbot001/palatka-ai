-- Native mimgui pawnshop panel. No WebView and no item transfer actions.
local V=DSP.ui21
local L=DSP.lombard
if not (V and L) then return false end
local function button(label,id,w,active)
    return V.button(label,'lombard_'..id,w,active)
end
function V.lombard_screen()
    V.heading('LOMBARD')
    local P=L.packet_probe
    local stats=L.stats and L.stats() or {items=0,pages=0}
    V.text('Saved pawnshop quotes: '..tostring(stats.items or 0))
    V.muted('Read-only: approach the pawnshop and choose the item hand-in menu.')
    V.muted('Classic dialogs are captured automatically; native packets need validation.')
    V.muted('No item hand-in, clicks or purchases are sent by Palatka.')
    if not P then V.red('Native scanner unavailable');return end
    local st=P.state()
    if not st.active then
        if button('Listen for native menu (35 sec)','start',280,false)then P.arm(35) end
    else
        V.green('Observing native menu, seconds left: '..math.max(0,st.until_ts-os.time()))
        if button('Stop and review','stop',280,true)then P.stop()end
    end
    V.muted('Packets: '..st.packets..' · candidate packets: '..#st.candidates..
        ' · labelled: '..st.tagged)
    local rows=P.preview()
    V.text('Observed priced items: '..#rows)
    if not st.verified_label and #rows>0 then
        V.red('UNVERIFIED: menu identity and complete item list not confirmed.')
    end
    if #rows>0 then
        V.list_rows('lombard_preview',rows,60,function(item,i)
            V.row('lombard_item_'..i,60,function(w,x,y)
                V.at(x,y);V.text(V.fit(tostring(item.name or '?'),w-8))
                V.at(x,y+27);V.muted('Pawnshop quote: '..DSP.money(item.price or 0))
            end)
        end,{height=math.min(330,math.max(120,imgui.GetContentRegionAvail().y*.55)),footer=false})
        if not st.active and button('Save observed quotes (unverified)','save',280)then
            local ok,err=P.save()
            if ok then V.lombard_error=nil else V.lombard_error=tostring(err) end
        end
    end
    if V.lombard_error then V.red(V.lombard_error) end
    if stats.items>0 then
        V.text('Previously captured quotes')
        local old=L.search and L.search('') or {}
        for i=1,math.min(5,#old)do
            local item=old[i]
            V.muted(V.fit(item.name..' / '..DSP.money(item.price),280))
        end
    end
end
-- Compatibility route for older OTA shells which do not have a Lombard nav entry.
local previous_tools=V.tools
V.tools=function(screen)
    if screen=='lombard' then return V.lombard_screen() end
    if previous_tools then return previous_tools(screen) end
end
return true
