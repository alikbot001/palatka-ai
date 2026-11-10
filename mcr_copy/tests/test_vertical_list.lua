local V=assert(loadfile('mcr_copy/src/vertical_list.lua'))()
local y,scroll,drawn,total=0,0,{},0
local B={ImVec2=function(x,h)return{x=x,y=h}end,GetCursorPosY=function()return y end,
 GetScrollY=function()return scroll end,GetStyle=function()return{ItemSpacing={y=4}}end,
 Dummy=function(v)y=y+v.y+4;total=y end,
 BeginChild=function(_,v)y=y+v.y+4;total=y;return true end,EndChild=function()end}
local rows={};for n=1,5000 do rows[n]={n=n}end
V.draw(B,'test',rows,100,300,function(r,index)assert(r.n==index);drawn[#drawn+1]=index end)
assert(#drawn<=6 and drawn[1]==1 and total==500000,'list is not bounded by the viewport')
y=0;scroll=499700;drawn={}
V.draw(B,'test',rows,100,300,function(_,n)drawn[#drawn+1]=n end)
assert(#drawn<=6 and drawn[#drawn]==5000,'bottom rows inaccessible by scrolling')
y=0;drawn={}
V.draw(B,'test',rows,100,300,function(_,n)drawn[#drawn+1]=n end,true)
assert(drawn[1]==1,'new view inherited old scroll for one frame')
print('Vertical MCR list: 5000 rows, bounded draw count and reachable tail OK')
