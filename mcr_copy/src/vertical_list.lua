-- Fixed-height native rows: full scroll extent, only viewport rows are drawn.
local V={}
function V.draw(B,id,rows,stride,height,draw,reset)
    if #rows==0 then return end
    local top=B.GetCursorPosY()
    local scroll=reset and 0 or B.GetScrollY()
    local first=math.max(1,math.min(#rows,math.floor(math.max(0,scroll-top)/stride)+1))
    local last=math.min(#rows,first+math.ceil(height/stride)+1)
    local gap=B.GetStyle().ItemSpacing.y
    if first>1 then B.Dummy(B.ImVec2(1,(first-1)*stride-gap))end
    for index=first,last do
        if B.BeginChild(id..'_'..index,B.ImVec2(0,stride-gap),true)then draw(rows[index],index)end
        B.EndChild()
    end
    if last<#rows then B.Dummy(B.ImVec2(1,(#rows-last)*stride-gap))end
end
return V
