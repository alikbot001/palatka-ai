-- Deterministic ImGui layout/interaction model. This is not an Android renderer.
local ffi=require('ffi')
local bit=require('bit')
local H={}
local function strict(t,name)return setmetatable(t,{__index=function(_,k)error('unsupported '..name..'.'..tostring(k),2)end})end
local function enum(names)
    local out={};for i,n in ipairs(names)do out[n]=2^(i-1)end
    return strict(out,'enum')
end
function H.new(sw,sh)
    local h={width=sw or 1120,height=sh or 650,contexts={},persistent={},rects={},violations={},
        clicks={},edits={},opened={},ids={},colors=0,color_stack={},palette_events={},windows={},vars={},repeats=0,frame=0,
        style={padding={x=10,y=8},spacing={x=6,y=4},frame={x=8,y=10}},font=1}
    local im={}
    im.WindowFlags=enum({'NoTitleBar','NoResize','NoMove','NoSavedSettings','NoScrollbar','NoScrollWithMouse','AlwaysAutoResize','NoCollapse'})
    local color_names={'Text','TextDisabled','WindowBg','ChildBg','PopupBg','Border','BorderShadow',
        'FrameBg','FrameBgHovered','FrameBgActive','TitleBg','TitleBgActive','TitleBgCollapsed','MenuBarBg',
        'ScrollbarBg','ScrollbarGrab','ScrollbarGrabHovered','ScrollbarGrabActive','CheckMark','SliderGrab',
        'SliderGrabActive','Button','ButtonHovered','ButtonActive','Header','HeaderHovered','HeaderActive',
        'Separator','SeparatorHovered','SeparatorActive','ResizeGrip','ResizeGripHovered','ResizeGripActive'}
    local color_enum={};for i,name in ipairs(color_names)do color_enum[name]=i-1 end
    im.Col=strict(color_enum,'Col')
    im.StyleVar=enum({'WindowPadding','ItemSpacing','FramePadding','WindowRounding','FrameRounding','ButtonTextAlign'})
    im.Cond=enum({'Always','Appearing'});im.InputTextFlags=enum({'Password'})
    im.new={char=setmetatable({},{__index=function(_,n)return function()return ffi.new('char[?]',n)end end}),
        bool=function(v)return ffi.new('bool[1]',v or false)end,int=function(v)return ffi.new('int[1]',v or 0)end,
        float=function(v)return ffi.new('float[1]',v or 0)end}
    im.ImVec2=function(x,y)return{x=x,y=y}end
    im.ImVec4=function(x,y,z,w)return{x=x,y=y,z=z,w=w}end
    local function rgba(value)
        if type(value)=='number'then
            return{x=bit.band(value,255)/255,y=bit.band(bit.rshift(value,8),255)/255,
                z=bit.band(bit.rshift(value,16),255)/255,w=bit.band(bit.rshift(value,24),255)/255}
        end
        assert(value and type(value.x)=='number'and type(value.y)=='number'and type(value.z)=='number'and type(value.w)=='number','invalid ImVec4 color')
        return{x=value.x,y=value.y,z=value.z,w=value.w}
    end
    local style_colors={}
    local defaults={Text={1,1,1,1},TextDisabled={.5,.5,.5,1},WindowBg={.06,.06,.06,.94},
        ChildBg={0,0,0,0},PopupBg={.08,.08,.08,.94},Border={.43,.43,.5,.5},
        Button={.26,.59,.98,.4},ButtonHovered={.26,.59,.98,1},ButtonActive={.06,.53,.98,1}}
    for i,name in ipairs(color_names)do
        local v=defaults[name]or{.16,.29,.48,1};style_colors[i-1]={x=v[1],y=v[2],z=v[3],w=v[4]}
    end
    local native_style=strict({Colors=strict(style_colors,'Style.Colors'),Alpha=1},'Style')
    im.GetStyle=function()return native_style end
    local function ctx()assert(#h.contexts>0,'widget outside window');return h.contexts[#h.contexts]end
    local function scope()local c=ctx();return c.key..'/'..table.concat(c.ids,'/')end
    local function label_id(label)return tostring(label):match('##(.+)$')or tostring(label)end
    local function chars(s)return #(tostring(s):gsub('[\128-\191]',''))end
    local function textsize(s)
        local max,lines=0,0
        for line in (tostring(s)..'\n'):gmatch('(.-)\n')do max=math.max(max,chars(line));lines=lines+1 end
        return{x=max*7*h.font,y=math.max(1,lines)*16*h.font}
    end
    local function region(c)return c.w-c.pad.x,c.h-c.pad.y end
    local function intersects(a,b)return a.x+a.w>b.x and a.x<b.x+b.w and a.y+a.h>b.y and a.y<b.y+b.h end
    local function add(kind,label,w,height,control)
        local c=ctx();local xmax=region(c)
        if w==0 then w=xmax-c.x elseif w<0 then w=math.max(1,xmax-c.x+w+1)end
        assert(w==w and height==height and w>=0 and height>=0,'invalid widget size '..tostring(label))
        local r={kind=kind,label=tostring(label),id=label_id(label),key=scope()..'/'..label_id(label),
            x=c.px+c.x,y=c.py+c.y-c.scroll,w=w,h=height,logical_y=c.y,container=c.key,control=control}
        r.visible=intersects(r,c.clip);r.clip=c.clip
        h.rects[#h.rects+1]=r
        if control and not c.clip_x then
            if r.x<c.clip.x-.1 or r.x+r.w>c.clip.x+c.clip.w+.1 then
                h.violations[#h.violations+1]='horizontal '..r.key..' ['..r.x..','..(r.x+r.w)..'] clip '..c.clip.x..'..'..(c.clip.x+c.clip.w)
            end
        end
        if control and not c.scrollable and(r.y<c.clip.y-.1 or r.y+r.h>c.clip.y+c.clip.h+.1)then
            h.violations[#h.violations+1]='vertical '..r.key..' ['..r.y..','..(r.y+r.h)..'] clip '..c.clip.y..'..'..(c.clip.y+c.clip.h)
        end
        c.maxy=math.max(c.maxy,c.y+height)
        local bottom=c.y+height
        if c.line_y==c.y then bottom=math.max(bottom,c.line_bottom or bottom)end
        c.last={x=c.x,y=c.y,w=w,h=height,bottom=bottom};c.line_y=c.y;c.line_bottom=bottom
        c.x=c.pad.x;c.y=bottom+h.style.spacing.y
        h.last=r
        return r
    end
    local function consume(queue,r)
        if not r.visible then return nil end
        local top
        for key in pairs(h.opened)do if not top or #key>#top then top=key end end
        if top and not r.key:find(top,1,true)then return nil end
        local key=queue[r.key]~=nil and r.key or r.id
        local value=queue[key]
        if value~=nil then queue[key]=nil;return value end
    end
    local function create(key,x,y,w,height,pad,scrollable,clip)
        local prior=h.persistent[key]or{scroll=0,maxscroll=0};h.persistent[key]=prior
        return{key=key,px=x,py=y,w=w,h=height,pad=pad,x=pad.x,y=pad.y,ids={},
            scroll=prior.scroll,maxy=pad.y,scrollable=scrollable,prior=prior,
            clip=clip or{x=x+pad.x,y=y+pad.y,w=w-2*pad.x,h=height-2*pad.y}}
    end
    local function window(label,popup)
        local size=h.next_size or{x=sw,y=sh};local pos=h.next_pos or{x=0,y=0}
        local pivot=h.next_pivot or{x=0,y=0};h.next_size=nil;h.next_pos=nil;h.next_pivot=nil
        local c=create(popup or label,pos.x-size.x*pivot.x,pos.y-size.y*pivot.y,size.x,size.y,h.style.padding,false)
        c.popup=popup
        c.background=rgba(style_colors[popup and im.Col.PopupBg or im.Col.WindowBg])
        if h.next_bg_alpha then c.background.w=h.next_bg_alpha end;h.next_bg_alpha=nil
        h.windows[#h.windows+1]={key=c.key,background=rgba(c.background),kind=popup and 'popup'or 'window'}
        h.contexts[#h.contexts+1]=c;return true
    end
    im.GetContentRegionAvail=function()local c=ctx();local x,y=region(c);return{x=x-c.x,y=y-c.y+c.scroll}end
    im.GetCursorPosX=function()return ctx().x end;im.GetCursorPosY=function()return ctx().y end
    im.GetCursorPos=function()return{x=ctx().x,y=ctx().y}end
    im.GetCursorScreenPos=function()local c=ctx();return{x=c.px+c.x,y=c.py+c.y-c.scroll}end
    im.SetCursorPos=function(p)local c=ctx();c.x=p.x;c.y=p.y;c.line_y=nil end
    im.SetCursorPosY=function(y)local c=ctx();c.y=y;c.line_y=nil end
    im.SetCursorPosX=function(x)ctx().x=x end
    im.SameLine=function(offset,gap)
        local c=ctx();assert(c.last,'SameLine without previous item');c.x=offset and offset>0 and offset or c.last.x+c.last.w+(gap or h.style.spacing.x)
        c.y=c.last.y;c.line_y=c.last.y;c.line_bottom=c.last.bottom
    end
    im.NewLine=function()local c=ctx();c.x=c.pad.x;c.y=math.max(c.y,(c.last and c.last.bottom or c.y)+h.style.spacing.y)end
    im.Separator=function()add('separator','',im.GetContentRegionAvail().x,0,false)end
    im.Spacing=function()add('space','',0,4,false)end
    im.Dummy=function(sz)add('dummy','',sz.x,sz.y,false)end
    im.CalcTextSize=textsize
    im.GetFontSize=function()return 16*h.font end
    im.Text=function(s)local sz=textsize(s);add('text',s,sz.x,sz.y,false)end
    im.TextDisabled=im.Text;im.TextColored=function(_,s)im.Text(s)end
    im.TextWrapped=function(s)local sz=textsize(s);local w=math.max(1,im.GetContentRegionAvail().x);add('wrapped',s,math.min(w,sz.x),math.ceil(sz.x/w)*sz.y,false)end
    im.Button=function(label,sz)local ts=textsize(label:gsub('##.*',''));sz=sz or{x=0,y=0}
        local w=sz.x==0 and ts.x+h.style.frame.x*2 or sz.x
        local r=add('button',label,w,sz.y==0 and ts.y+h.style.frame.y*2 or sz.y,true)
        return consume(h.clicks,r)==true
    end
    im.SmallButton=function(s)return im.Button(s,{x=0,y=24})end
    im.SetNextItemWidth=function(w)h.next_item_width=w end
    local function input(label,buf,size,sz)
        local w=sz and sz.x or h.next_item_width or 160;h.next_item_width=nil
        local r=add('input',label,w,sz and sz.y or(16*h.font+h.style.frame.y*2),true)
        local edit=consume(h.edits,r)
        if edit~=nil then assert(#edit<size,'input exceeds buffer');ffi.fill(buf,size,0);ffi.copy(buf,edit,#edit);return true end
        return false
    end
    im.InputText=function(label,buf,n)return input(label,buf,n)end
    im.InputTextWithHint=function(label,_,buf,n)return input(label,buf,n)end
    im.InputTextMultiline=function(label,buf,n,sz)return input(label,buf,n,sz)end
    im.Checkbox=function(label,buffer)local r=add('checkbox',label,textsize(label).x+24,22,true);if consume(h.clicks,r)then buffer[0]=not buffer[0];return true end;return false end
    im.SetNextWindowSize=function(sz)h.next_size=sz end
    im.SetNextWindowPos=function(p,_,pivot)h.next_pos=p;h.next_pivot=pivot end
    im.SetNextWindowBgAlpha=function(alpha)h.next_bg_alpha=alpha end
    im.Begin=function(label)return window(label)end
    im.End=function()local c=ctx();assert(not c.child and not c.popup,'wrong End');assert(#c.ids==0,'window ID stack leaked');table.remove(h.contexts)end
    im.BeginChild=function(label,sz,border)
        local p=ctx();local avail=im.GetContentRegionAvail();local w=sz.x<=0 and avail.x+sz.x or sz.x
        local height=sz.y<=0 and avail.y+sz.y or sz.y
        assert(w>0 and height>0,'nonpositive child size '..label..' '..w..'x'..height)
        local x,y=p.px+p.x,p.py+p.y-p.scroll
        local clip={x=math.max(x,p.clip.x),y=math.max(y,p.clip.y),w=math.min(x+w,p.clip.x+p.clip.w)-math.max(x,p.clip.x),h=math.min(y+height,p.clip.y+p.clip.h)-math.max(y,p.clip.y)}
        local c=create(p.key..'/'..label,x,y,w,height,border and h.style.padding or{x=0,y=0},label:find('v22_list_',1,true)~=nil,clip)
        c.child={label=label,w=w,h=height};c.background=rgba(style_colors[im.Col.ChildBg])
        h.windows[#h.windows+1]={key=c.key,background=rgba(c.background),kind='child'}
        h.contexts[#h.contexts+1]=c
        return true
    end
    im.EndChild=function()
        local c=ctx();assert(c.child,'EndChild without child');assert(#c.ids==0,'child ID stack leaked');c.prior.maxscroll=math.max(0,c.maxy+c.pad.y-c.h)
        table.remove(h.contexts);add('child',c.child.label,c.child.w,c.child.h,false)
    end
    im.GetScrollY=function()return ctx().scroll end
    im.GetScrollMaxY=function()return ctx().prior.maxscroll end
    im.SetScrollY=function(y)local c=ctx();c.scroll=math.max(0,math.min(y,c.prior.maxscroll));c.prior.scroll=c.scroll end
    im.PushIDStr=function(id)local ids=ctx().ids;ids[#ids+1]=tostring(id)end
    im.PopID=function()local ids=ctx().ids;assert(#ids>0,'ID underflow');table.remove(ids)end
    im.OpenPopup=function(label)h.opened[scope()..'/'..label]=true end
    im.BeginPopupModal=function(label)
        local key=scope()..'/'..label
        if not h.opened[key]then h.next_size=nil;h.next_pos=nil;h.next_pivot=nil;h.next_bg_alpha=nil;return false end
        return window(label,key)
    end
    im.CloseCurrentPopup=function()local c=ctx();assert(c.popup,'CloseCurrentPopup outside popup');for key in pairs(h.opened)do if key:sub(1,#c.popup)==c.popup then h.opened[key]=nil end end end
    im.EndPopup=function()assert(ctx().popup,'EndPopup outside popup');assert(#ctx().ids==0,'popup ID stack leaked');table.remove(h.contexts)end
    im.PushStyleColor=function(index,value)
        assert(style_colors[index]~=nil,'unsupported color index '..tostring(index))
        h.color_stack[#h.color_stack+1]={index=index,previous=rgba(style_colors[index])}
        style_colors[index]=rgba(value);h.colors=#h.color_stack
        h.palette_events[#h.palette_events+1]={kind='push',index=index,value=rgba(style_colors[index])}
    end
    im.PopStyleColor=function(n)
        for _=1,n or 1 do
            local entry=table.remove(h.color_stack);assert(entry,'color stack underflow')
            style_colors[entry.index]=entry.previous
            h.palette_events[#h.palette_events+1]={kind='pop',index=entry.index,value=rgba(entry.previous)}
        end
        h.colors=#h.color_stack
    end
    local function pushvar(key,value)
        local map={[im.StyleVar.WindowPadding]='padding',[im.StyleVar.ItemSpacing]='spacing',[im.StyleVar.FramePadding]='frame'}
        local name=map[key];h.vars[#h.vars+1]={name=name,old=name and h.style[name]};if name then h.style[name]=value end
    end
    im.PushStyleVarVec2=pushvar;im.PushStyleVarFloat=pushvar
    im.PopStyleVar=function(n)for _=1,n or 1 do local item=table.remove(h.vars);assert(item,'style stack underflow');if item.name then h.style[item.name]=item.old end end end
    im.PushButtonRepeat=function()h.repeats=h.repeats+1 end
    im.PopButtonRepeat=function()h.repeats=h.repeats-1;assert(h.repeats>=0,'repeat stack underflow')end
    im.SetWindowFontScale=function(v)h.font=v end
    im.GetTextLineHeight=function()return 16*h.font end
    im.GetIO=function()return{DisplaySize={x=h.width,y=h.height},MouseDelta={x=0,y=0},MouseDown={[0]=false},WantTextInput=false}end
    im.IsItemActive=function()return false end;im.IsAnyItemActive=function()return false end
    im.IsWindowHovered=function()return false end;im.IsMouseDown=function()return false end
    im.IsMouseDragging=function()return false end;im.GetFrameCount=function()return h.frame end
    im.GetWindowPos=function()local c=ctx();return{x=c.px,y=c.py}end
    im.GetWindowSize=function()local c=ctx();return{x=c.w,y=c.h}end
    im.GetColorU32=function(index,alpha)
        local c=type(index)=='table'and rgba(index)or rgba(assert(style_colors[index],'unknown color index'))
        local function byte(v)return math.floor(math.max(0,math.min(1,v))*255+.5)end
        return bit.bor(byte(c.x),bit.lshift(byte(c.y),8),bit.lshift(byte(c.z),16),bit.lshift(byte(c.w*(alpha or 1)*native_style.Alpha),24))
    end
    im.GetWindowDrawList=function()return strict({AddRect=function()end,AddRectFilled=function()end,AddTriangleFilled=function()end,AddLine=function()end},'drawlist')end
    h.imgui=strict(im,'imgui')
    function h:begin_frame()
        assert(#self.contexts==0,'window stack leaked before frame')
        self.frame=self.frame+1;self.rects={};self.violations={};self.windows={};self.font=1
    end
    function h:finish_frame()
        assert(#self.contexts==0,'window/child/popup stack leaked')
        assert(self.colors==0 and #self.vars==0 and self.repeats==0,'style stack leaked')
        assert(next(self.clicks)==nil,'click target absent or clipped: '..tostring(next(self.clicks)))
        assert(next(self.edits)==nil,'input target absent or clipped: '..tostring(next(self.edits)))
    end
    function h:click(id)self.clicks[id]=true end
    function h:edit(id,value)self.edits[id]=value end
    function h:find(id)for _,r in ipairs(self.rects)do if r.id==id then return r end end end
    function h:assert_bounds()assert(#self.violations==0,table.concat(self.violations,'\n'))end
    return h
end
return H
