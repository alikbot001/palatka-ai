-- Carbon Trade lightweight skin primitives; existing ImGui handles input and clipping.
-- Geometry only for visible rows, no bitmap allocations or HTTP.
DSP.carbon_draw = DSP.carbon_draw or {}
local D=DSP.carbon_draw
D.frame_shapes=0
D.max_shapes=240
function D.begin_frame()
    D.frame_shapes=0
end
function D.row(x,y,w,h)
    if DSP.settings and DSP.settings.carbon_draw_enabled==false then return false end
    if D.frame_shapes+3>D.max_shapes then return true end
    if not imgui or not imgui.GetWindowDrawList or not imgui.GetColorU32 then return false end
    local draw=imgui.GetWindowDrawList()
    if not draw then return false end
    local p1=imgui.ImVec2(x,y)
    local p2=imgui.ImVec2(x+w,y+h)
    draw:AddRectFilled(p1,p2,imgui.GetColorU32(imgui.Col.FrameBg),5)
    if draw.AddRect then draw:AddRect(p1,p2,imgui.GetColorU32(imgui.Col.Border),5) end
    if draw.AddLine then
        draw:AddLine(imgui.ImVec2(x+5,y+1),imgui.ImVec2(x+w-5,y+1),imgui.GetColorU32(imgui.Col.CheckMark),1)
    end
    D.frame_shapes=D.frame_shapes+3
    return true
end
