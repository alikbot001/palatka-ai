-- Focused v2.9.3 regression for drag/swipe list scrolling.
local scroll,max_scroll=100,500
local io={DisplaySize={x=800,y=600},MouseDown={[0]=true},MouseDelta={x=0,y=-20},WantTextInput=false,DeltaTime=1/60}
local separator_count,arrow_count=0,child_open=false
imgui={
    HoveredFlags={ChildWindows=1},
    WindowFlags={NoScrollbar=1},
    ImVec2=function(x,y)return{x=x,y=y}end,
    IsWindowHovered=function()return true end,
    IsAnyItemActive=function()return false end,
    GetScrollY=function()return scroll end,
    GetScrollMaxY=function()return max_scroll end,
    SetScrollY=function(y)scroll=y end,
    GetIO=function()return io end,
    GetContentRegionAvail=function()return{x=500,y=300}end,
    BeginChild=function()child_open=true;return true end,
    EndChild=function()child_open=false end,
    Separator=function()separator_count=separator_count+1 end,
}
_G.DSP={
    clamp=function(v,a,b)return math.max(a,math.min(b,v))end,
    mobile={},
    ui22={
        scrolls={},
        track_touch=function()end,
        apply_font=function()end,
        scroll_buttons=function()arrow_count=arrow_count+1 end,
        inline=function()end,
        muted=function()end,
    }
}
assert(dofile('src/60aa_touch_scroll.lua'))

-- Dragging content changes list scroll directly.
DSP.mobile.touch_scroll(io,'drag')
assert(scroll==120,'finger drag must move content, got '..tostring(scroll))

-- Releasing continues with decaying inertial velocity.
io.MouseDown[0]=false;io.MouseDelta.y=0
local released=scroll
DSP.mobile.touch_scroll(io,'drag')
assert(scroll>released,'released swipe must retain positive inertia')

-- Ordinary lists do not render fixed up/down controls.
scroll=0;arrow_count=0
DSP.ui22.list('plain',function(w,h,y)
    assert(child_open and w==500 and h==258 and y==0)
end,{count=12})
assert(arrow_count==0,'fixed scroll arrows must be absent by default')

-- Legacy callers can explicitly opt in without changing the default UX.
DSP.ui22.list('legacy',function()end,{count=12,scroll_buttons=true})
assert(arrow_count==1,'explicit scroll_buttons=true must remain compatible')
print('PASS v2.9.3 touch drag, inertia and arrowless lists')
