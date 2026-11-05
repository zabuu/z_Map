-- Optional click-through automap: native wall traces, nodes, heading up.
local M=zMap
M.hudWallLimit=1536
M.hudWallCacheLimit=32768
-- The 9.6 MB wall database lives in the load-on-demand addon z_Map_HUD and is
-- only loaded the first time the HUD actually needs walls.
local EMPTY={models={},placements={},grid={},cell=128}
local DATA
local function hudData()
    if DATA then return DATA end
    if not zMapHudData and LoadAddOn then
        local ok,reason=LoadAddOn("z_Map_HUD")
        if not ok and not zMapHudData then
            M:Print("HUD walls unavailable: z_Map_HUD did not load ("..tostring(reason or "missing").."). Enable it in the AddOns list.")
        end
    end
    DATA=zMapHudData or EMPTY
    return DATA
end
M.HUDData=hudData
local function nearerTask(a,b) return a.distance<b.distance end
local function nearerWall(a,b) return a[5]<b[5] end
local floor,ceil,abs,min,max,sqrt=math.floor,math.ceil,math.abs,math.min,math.max,math.sqrt
local alphabet="0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_-"
local digits={}
for i=1,64 do digits[string.byte(alphabet,i)]=i-1 end
local function unpackNumber(raw,offset,count)
    local value,power=0,1
    for i=offset,offset+count-1 do value=value+digits[string.byte(raw,i)]*power;power=power*64 end
    return value*.5
end
function M:HUDToScreen(x,y)
    local v=self.view;local dx,dy=x-v.x,y-v.y
    return v.width/2+(self.cos*dx-self.sin*dy)*v.scale,v.height/2+(self.sin*dx+self.cos*dy)*v.scale
end
function M:HUDToWorld(x,y)
    local v=self.view;local dx,dy=(x-v.width/2)/v.scale,(y-v.height/2)/v.scale
    return v.x+self.cos*dx+self.sin*dy,v.y-self.sin*dx+self.cos*dy
end
function M:HUDVisibility(x,y)
    local v=self.view
    local radius=max(1,min(v.width,v.height)/2-10)
    local distance=sqrt((x-v.width/2)^2+(y-v.height/2)^2)/radius
    return self.Clamp((1-distance)/.3,0,1)
end
local function clipCircle(x,y,u,v,cx,cy,radius)
    local dx,dy=u-x,v-y;local ox,oy=x-cx,y-cy
    local a=dx*dx+dy*dy
    if a<.000001 then return end
    local r2=radius*radius
    if ox*ox+oy*oy<=r2 and (u-cx)^2+(v-cy)^2<=r2 then return x,y,u,v end
    local b=ox*dx+oy*dy;local c=ox*ox+oy*oy-r2
    local discriminant=b*b-a*c
    if discriminant<=0 then return end
    local root=sqrt(discriminant)
    local lo,hi=max(0,(-b-root)/a),min(1,(-b+root)/a)
    if lo>=hi then return end
    return x+lo*dx,y+lo*dy,x+hi*dx,y+hi*dy
end
local function drawWall(ctx,index,x,y,u,v,alpha,length2,length,parent,stable)
    local mx,my=(x+u)/2,(y+v)/2
    local dx,dy=u-x,v-y
    local texture=ctx.wallTextures[index]
    if not texture then
        texture=ctx.layers.walls:CreateTexture(nil,"ARTWORK");ctx.wallTextures[index]=texture
        texture:SetTexture("Interface\\AddOns\\z_Map\\Media\\Hud\\Line")
    end
    texture.hudRecord=nil
    local qx,qy,width,height=mx,my,abs(dx)+2,abs(dy)+2
    if stable then
        -- Move the line within its texture with UVs. Keep its small quad until
        -- an endpoint leaves the one-pixel guard; turning needs fewer anchors
        -- and dimensions without rounding the line's actual screen position.
        if texture.hudParent==parent and texture.hudX and
            abs(mx-texture.hudX)+abs(dx)/2+1<=texture.hudWidth/2 and
            abs(my-texture.hudY)+abs(dy)/2+1<=texture.hudHeight/2 then
            qx,qy,width,height=texture.hudX,texture.hudY,texture.hudWidth,texture.hudHeight
        else
            qx,qy=floor(mx+.5),floor(my+.5);width,height=ceil(abs(dx)+4),ceil(abs(dy)+4)
        end
    end
    local ox,oy=qx-mx,qy-my
    if not texture.hudDX or abs(texture.hudDX-dx)>.000001 or abs(texture.hudDY-dy)>.000001 or
        texture.hudWidth~=width or texture.hudHeight~=height or texture.hudOX~=ox or texture.hudOY~=oy then
        length=length or sqrt(length2)
        local su=(dx*ox+dy*oy)/length2;local sv=(-dy*ox+dx*oy)/(38.4*length)
        local a=.5-(dx*width+dy*height)/(2*length2)
        local b=.5+(dy*width-dx*height)/(76.8*length)
        local d=.5+(-dx*width+dy*height)/(2*length2)
        local e=.5+(dy*width+dx*height)/(76.8*length)
        if texture.hudWidth~=width then texture:SetWidth(width);texture.hudWidth=width end
        if texture.hudHeight~=height then texture:SetHeight(height);texture.hudHeight=height end
        texture:SetTexCoord(a+su,b+sv,d+su,e+sv,1-d+su,1-e+sv,1-a+su,1-b+sv)
        texture.hudDX=dx;texture.hudDY=dy;texture.hudOX=ox;texture.hudOY=oy
    end
    if texture.hudParent~=parent or texture.hudX~=qx or texture.hudY~=qy then
        texture:SetPoint("CENTER",parent,"TOPLEFT",qx,-qy);texture.hudX=qx;texture.hudY=qy;texture.hudParent=parent
    end
    if not texture.hudAlpha or abs(texture.hudAlpha-alpha)>.000001 then
        texture:SetVertexColor(.74,.84,.81,alpha);texture.hudAlpha=alpha
    end
    if not texture.hudShown then texture:Show();texture.hudShown=true end
    return true
end
function M:HUDLine(index,x,y,u,v,alpha)
    local view=self.view;local radius=max(1,min(view.width,view.height)/2-10)
    x,y,u,v=clipCircle(x,y,u,v,view.width/2,view.height/2,radius)
    if not x then return false end
    local mx,my=(x+u)/2,(y+v)/2
    local distance=(mx-view.width/2)^2+(my-view.height/2)^2
    if distance>radius*radius*.49 then alpha=alpha*max(0,(1-sqrt(distance)/radius)/.3) end
    local dx,dy=u-x,v-y;local length2=dx*dx+dy*dy
    if alpha<.015 or length2<1 then return false end
    local parent=self.viewport
    if self.wallOffsetX then
        parent=self.layers.walls;x=x-self.wallOffsetX;u=u-self.wallOffsetX;y=y-self.wallOffsetY;v=v-self.wallOffsetY
    end
    return drawWall(self,index,x,y,u,v,alpha,length2,nil,parent,false)
end
local function wallPage(ctx,task,page)
    local cache=ctx.wallCache
    if not cache then cache={cells={},size=0,clock=0,decoded=0,hits=0};ctx.wallCache=cache end
    cache.clock=cache.clock+1
    local key=task.key..":"..page
    local entry=cache.cells[key]
    if not entry then
        local count=min(256,string.len(task.raw)/14-page*256)
        if count>M.hudWallCacheLimit then return end
        -- Small pages avoid reserving an entire dense WMO cell at once.
        while cache.size+count>M.hudWallCacheLimit do
            local oldestKey,oldest
            for key,cell in pairs(cache.cells) do
                if not oldest or cell.used<oldest.used then oldestKey=key;oldest=cell end
            end
            if not oldest then break end
            cache.cells[oldestKey]=nil;cache.size=cache.size-oldest.count
        end
        entry={values={},count=count};cache.cells[key]=entry;cache.size=cache.size+count
    end
    entry.used=cache.clock
    return entry.values
end
function M:StartHUDWallQuery()
    local ctx=self.hudContext;local v=ctx.view;local radius=zMapDB.hudRange*1.25
    local DATA=hudData();local cell=DATA.cell
    -- Scratch tables are reused: a query starts every ~10 yards of movement.
    local seen=ctx.wallSeen or {};ctx.wallSeen=seen
    for id in pairs(seen) do seen[id]=nil end
    local tasks=ctx.wallTasks or {};ctx.wallTasks=tasks
    local pool=ctx.wallTaskPool or {};ctx.wallTaskPool=pool
    local count=0
    for x=floor((v.x-radius)/cell),floor((v.x+radius)/cell) do
        for y=floor((v.y-radius)/cell),floor((v.y+radius)/cell) do
            for _,id in ipairs(DATA.grid[v.space..":"..x..":"..y] or {}) do
                if not seen[id] then
                    seen[id]=true;local p=DATA.placements[id]
                    local dx,dy=v.x-p[3],v.y-p[4]
                    local localX,localY=p[5]*dx+p[6]*dy,p[6]*dx-p[5]*dy
                    for cx=floor((localX-radius)/cell),floor((localX+radius)/cell) do
                        for cy=floor((localY-radius)/cell),floor((localY+radius)/cell) do
                            local raw=DATA.models[p[1]][cx..":"..cy]
                            if raw then
                                count=count+1;local task=pool[count]
                                if not task then task={};pool[count]=task end
                                task.raw=raw;task.key=id..":"..cx..":"..cy;task.x=cx*cell;task.y=cy*cell;task.placement=p
                                task.distance=(localX-(cx+.5)*cell)^2+(localY-(cy+.5)*cell)^2;tasks[count]=task
                            end
                        end
                    end
                end
            end
        end
    end
    for i=count+1,table.getn(tasks) do tasks[i]=nil end
    table.sort(tasks,nearerTask)
    -- Results alternate between two buffers whose wall tuples are reused. The
    -- visible buffer (ctx.walls) is never written while its replacement builds.
    local buffers=ctx.wallBuffers
    if not buffers then buffers={{list={},pool={}},{list={},pool={}}};ctx.wallBuffers=buffers end
    local back=buffers[1].list==ctx.walls and buffers[2] or buffers[1]
    local list=back.list;for i=table.getn(list),1,-1 do list[i]=nil end
    local job=ctx.wallJob or ctx.wallJobSpare or {};ctx.wallJob=job;ctx.wallJobSpare=nil
    job.tasks=tasks;job.task=1;job.offset=1;job.results=list;job.pool=back.pool;job.count=0
    job.scanned=0;job.heightRejected=0;job.cell=nil;job.page=nil
    ctx.wallQuery={x=v.x,y=v.y,space=v.space,z=ctx.floorZ,range=zMapDB.hudRange,filter=zMapDB.hudHeightFilter}
end
function M:StepHUDWallQuery()
    local ctx=self.hudContext;local job=ctx.wallJob
    if not job then return end
    local q=ctx.wallQuery;local z=q.filter~="off" and q.z and q.z+2
    local margin=q.filter=="relaxed" and 12 or 3
    local spent=0
    while spent<1200 and job.scanned<16000 do
        local task=job.tasks[job.task]
        if not task then break end
        if job.offset>string.len(task.raw) then job.task=job.task+1;job.offset=1;job.cell=nil;job.page=nil
        else
            local raw,k,p=task.raw,job.offset,task.placement
            local record=(k-1)/14;local page=floor(record/256)
            if k==1 or page~=job.page then job.cell=wallPage(ctx,task,page);job.page=page end
            job.offset=k+14;spent=spent+1;job.scanned=job.scanned+1
            local values=job.cell;local index=(record-page*256)*6+1
            local low,high
            if values and values[index+4] then
                low,high=values[index+4],values[index+5];ctx.wallCache.hits=ctx.wallCache.hits+1
            else
                low,high=unpackNumber(raw,k+8,3)-65536+p[7],unpackNumber(raw,k+11,3)-65536+p[7]
                ctx.wallCache.decoded=ctx.wallCache.decoded+1
                if values then values[index+4]=low;values[index+5]=high end
            end
            if not z or z>=low-margin and z<=high+margin then
                local x,y,u,v
                if values and values[index] then
                    x,y,u,v=values[index],values[index+1],values[index+2],values[index+3]
                else
                    x,y=task.x+unpackNumber(raw,k,2),task.y+unpackNumber(raw,k+2,2)
                    u,v=task.x+unpackNumber(raw,k+4,2),task.y+unpackNumber(raw,k+6,2)
                    x,y,u,v=p[3]+p[5]*x+p[6]*y,p[4]+p[6]*x-p[5]*y,p[3]+p[5]*u+p[6]*v,p[4]+p[6]*u-p[5]*v
                    if values then values[index]=x;values[index+1]=y;values[index+2]=u;values[index+3]=v end
                end
                local distance=((x+u)/2-q.x)^2+((y+v)/2-q.y)^2
                if distance<(q.range*1.25)^2 then
                    local n=job.count+1;job.count=n
                    local wall=job.pool[n];if not wall then wall={};job.pool[n]=wall end
                    wall[1]=x;wall[2]=y;wall[3]=u;wall[4]=v;wall[5]=distance;job.results[n]=wall
                    if n>=2400 then break end
                end
            else job.heightRejected=job.heightRejected+1 end
        end
    end
    if not job.tasks[job.task] or job.scanned>=16000 or job.count>=2400 then
        table.sort(job.results,nearerWall)
        ctx.walls=job.results;ctx.wallScanned=job.scanned
        ctx.wallReport={scanned=job.scanned,heightRejected=job.heightRejected,tasks=table.getn(job.tasks),
            candidates=job.count,z=q.z,filter=q.filter,query=q,
            limited=job.scanned>=16000 or job.count>=2400}
        ctx.wallJob=nil;ctx.wallJobSpare=job
    end
end
function M:CreateHUDContext()
    local frame=CreateFrame("Frame",nil,UIParent);frame:SetFrameStrata("LOW");frame:EnableMouse(false)
    -- Explicit false keeps this context from inheriting the full-map arrow.
    local ctx=setmetatable({hud=true,frame=frame,viewport=frame,view={},layers={},wallTextures={},walls={},serial=0,
        gatherMarkers={},gatherMarkerFree={},gatherRenderEpoch=0,gatherMarkerLimit=128,unitDots={},
        hoveredGather=false,gatherTooltipMarker=false,cos=1,sin=0,smoothFollow=true,playerMarker=false}, {__index=M})
    for i,name in ipairs({"walls","gather","questRoutes","quests","markers"}) do
        local layer=CreateFrame("Frame",nil,frame)
        if name=="walls" then
            -- A single translated parent carries unchanged wall textures.
            layer:SetWidth(1);layer:SetHeight(1);layer:SetPoint("TOPLEFT",frame,"TOPLEFT",0,0)
        else layer:SetAllPoints(frame) end
        layer:SetFrameLevel(frame:GetFrameLevel()+i);ctx.layers[name]=layer
    end
    ctx.playerDot=ctx.layers.markers:CreateTexture(nil,"OVERLAY")
    ctx.playerDot:SetTexture("Interface\\AddOns\\z_Map\\Media\\GroupCircle")
    ctx.playerDot:SetWidth(7);ctx.playerDot:SetHeight(7)
    ctx.playerDot:SetVertexColor(.85,1,.95,.95);ctx.playerDot:SetPoint("CENTER",frame,"CENTER",0,0)
    ctx.ToScreen=M.HUDToScreen;ctx.ToWorld=M.HUDToWorld
    ctx.UpdateGatherStatus=function() end
    ctx.GatherPresentation=function() return 13,.9,false end
    ctx.GatherNodeVisible=function(self,node)
        local sx,sy=self:ToScreen(node.x,node.y)
        return self:HUDVisibility(sx,sy)>.03 and (not self.floorZ or not node.z or abs(node.z-self.floorZ)<18)
    end
    ctx.MakeGatherMarker=function(self)
        local marker=M.MakeGatherMarker(self);marker:EnableMouse(false);marker:EnableMouseWheel(false);return marker
    end
    ctx.MakePFQuestMarker=function(self)
        local marker=M.MakePFQuestMarker(self);marker:EnableMouse(false);marker:EnableMouseWheel(false);return marker
    end
    ctx.RenderPFQuestRoutes=function() end
    ctx.RenderTracking=function(self)
        if zMapDB.trackHUD then M.RenderTracking(self) else self:HideTracking() end
    end
    ctx.RenderPFQuest=function(self)
        if zMapDB.hudQuests then M.RenderPFQuest(self) else self:HidePFQuest() end
    end
    frame:SetScript("OnHide",function() ctx:HidePFQuest();ctx:HideTracking() end)
    frame:Hide();self.hudContext=ctx;return ctx
end
function M:SetHUD(enabled)
    zMapDB.hudEnabled=enabled==true
    if not enabled then
        self.hudZoomPending=nil
        if self.hudContext then self.hudContext.frame:Hide();self.hudContext.wallJob=nil end
    end
    self:RefreshSettingsPanel()
end
local function finite(value) return type(value)=="number" and value==value and abs(value)<10000000 end
local function styleDot(dot,r,g,b,alpha)
    if dot.hudR~=r or dot.hudG~=g or dot.hudB~=b then
        dot:SetVertexColor(r,g,b);dot.hudR=r;dot.hudG=g;dot.hudB=b
    end
    if dot:GetAlpha()~=alpha then dot:SetAlpha(alpha) end
end
function M:HUDUnitPoint(unit,p)
    if type(UnitExists)~="function" or not UnitExists(unit) then return end
    if p.rawX and type(zAPI)=="function" then
        local ok,x,y,z=pcall(zAPI,"unitPosition",unit)
        if ok and finite(x) and finite(y) and finite(z) then
            return p.x+p.rawY-y,p.y+p.rawX-x,p.space
        end
    end
    for _,member in ipairs(self.group or {}) do
        if member.unit==unit then return member.x,member.y,member.space end
    end
end
function M:PlaceHUDUnitDot(ctx,unit,x,y,space,r,g,b,size)
    if not x or space~=ctx.view.space then return end
    local sx,sy=ctx:ToScreen(x,y);local alpha=ctx:HUDVisibility(sx,sy)*.95
    if alpha<.03 then return end
    local dot=ctx.unitDots[unit]
    if not dot then
        dot=ctx.layers.markers:CreateTexture(nil,"ARTWORK");ctx.unitDots[unit]=dot
        dot:SetTexture("Interface\\AddOns\\z_Map\\Media\\GroupCircle")
        dot:SetWidth(size);dot:SetHeight(size)
    end
    if dot.hudX~=sx or dot.hudY~=sy then
        dot:ClearAllPoints();dot:SetPoint("CENTER",ctx.viewport,"TOPLEFT",sx,-sy);dot.hudX=sx;dot.hudY=sy
    end
    styleDot(dot,r,g,b,alpha);dot.hudEpoch=ctx.serial
    if not dot:IsShown() then dot:Show() end
    return true
end
function M:RenderHUDUnits(ctx,p,refresh)
    ctx.unitDots=ctx.unitDots or {}
    local _,class=UnitClass("player");local r,g,b=self:ClassColor(class)
    styleDot(ctx.playerDot,r,g,b,.95)
    if zMapDB.hudPlayer then
        if not ctx.playerDot:IsShown() then ctx.playerDot:Show() end
    elseif ctx.playerDot:IsShown() then ctx.playerDot:Hide() end
    local target
    if zMapDB.hudTarget and not UnitIsUnit("target","player") then
        local x,y,space=self:HUDUnitPoint("target",p)
        local combat=UnitAffectingCombat and UnitAffectingCombat("target")
        target=self:PlaceHUDUnitDot(ctx,"target",x,y,space,1,combat and .15 or .85,combat and .15 or 0,9)
    end
    if zMapDB.hudPet and not (target and UnitIsUnit("pet","target")) then
        local x,y,space=self:HUDUnitPoint("pet",p)
        self:PlaceHUDUnitDot(ctx,"pet",x,y,space,1,.5,0,7)
    end
    if zMapDB.hudParty then
        local count=GetNumRaidMembers and GetNumRaidMembers() or 0;local prefix="raid"
        if count==0 then prefix="party";count=min(4,GetNumPartyMembers and GetNumPartyMembers() or 0) end
        -- Up to 40 members: query positions and classes at the 20 Hz refresh
        -- and only reproject the cached world points on the frames between.
        local samples=ctx.unitSamples;if not samples then samples={};ctx.unitSamples=samples end
        if refresh or ctx.unitSampleSerial==nil then
            ctx.unitSampleSerial=ctx.serial
            for i=1,40 do
                local unit=prefix..i;local s=samples[i]
                if not s then s={};samples[i]=s end
                s.unit=nil
                if i<=count and not UnitIsUnit(unit,"player") and (not UnitIsConnected or UnitIsConnected(unit)) then
                    local x,y,space=self:HUDUnitPoint(unit,p)
                    if x then
                        local _,class=UnitClass(unit);s.r,s.g,s.b=self:ClassColor(class)
                        s.unit=unit;s.x=x;s.y=y;s.space=space
                    end
                end
            end
        end
        for i=1,min(40,count) do
            local s=samples[i]
            if s.unit and not (target and UnitIsUnit(s.unit,"target")) then
                self:PlaceHUDUnitDot(ctx,s.unit,s.x,s.y,s.space,s.r,s.g,s.b,7)
            end
        end
    end
    for _,dot in pairs(ctx.unitDots) do if dot.hudEpoch~=ctx.serial and dot:IsShown() then dot:Hide() end end
end
M.hudOffsetLimit=3000
local function offsetValue(value)
    value=tonumber(value)
    return finite(value) and M.Clamp(floor(value+.5),-M.hudOffsetLimit,M.hudOffsetLimit) or 0
end
function M:SetHUDOffset(axis,value)
    if axis~="X" and axis~="Y" then return end
    zMapDB["hudOffset"..axis]=offsetValue(value)
    self:RefreshHUDPositionPanel()
end
function M:ResetHUDOffsets()
    zMapDB.hudOffsetX=0;zMapDB.hudOffsetY=0
    self:RefreshHUDPositionPanel()
end
local function validCamera(value)
    return type(value)=="table" and finite(value.distance) and value.distance>=0 and value.distance<1000 and
        finite(value.pitch) and abs(value.pitch)<=1 and finite(value.fov) and value.fov>0 and
        finite(value.aspect) and value.aspect>0
end
local function sameCamera(a,b)
    return a and b and abs(a.distance-b.distance)<=max(.25,b.distance*.015) and
        abs(a.pitch-b.pitch)<=.01 and abs(a.fov-b.fov)<=.01 and abs(a.aspect-b.aspect)<=.01 and
        abs(a.fx-b.fx)<=.01 and abs(a.fy-b.fy)<=.01 and
        abs(a.px-b.px)<=.02 and abs(a.py-b.py)<=.02 and abs(a.pz-b.pz)<=.02
end
function M:QueueHUDZoomAlignment()
    if not zMapDB or not zMapDB.hudEnabled then return end
    self.hudZoomPending=true;self.hudCameraSample=nil;self.hudCameraStable=0;self.hudCameraElapsed=0
end
function M:InstallHUDCameraZoomHooks()
    self.hudCameraZoomHooks=self.hudCameraZoomHooks or {}
    for _,name in ipairs({"CameraZoomIn","CameraZoomOut"}) do
        if not self.hudCameraZoomHooks[name] and type(_G[name])=="function" then
            local previous=_G[name]
            _G[name]=function(...)
                self:QueueHUDZoomAlignment()
                return previous(unpack(arg,1,arg.n))
            end
            self.hudCameraZoomHooks[name]=true
        end
    end
end
function M:AlignHUD()
    self.hudAlignPending=true;self.hudZoomPending=nil
    self:SetHUD(true)
end
function M:CenterHUDOnPlayer()
    self:ResetHUDOffsets()
    self:AlignHUD()
end
function M:UpdateHUDCamera(elapsed,p)
    -- A measured camera displacement can be movement lag or collision, not zoom.
    -- Only an actual zoom command may schedule automatic feet realignment.
    if not self.hudZoomPending or self.hudAlignPending then return end
    self.hudCameraElapsed=(self.hudCameraElapsed or 0)+elapsed
    if self.hudCameraElapsed<.2 then return end
    local dt=self.hudCameraElapsed;self.hudCameraElapsed=0
    if not p.rawX or type(zAPI)~="function" then self.hudZoomPending=nil;return end
    local ok,x,y,z,fx,fy,fz,rx,ry,rz,ux,uy,uz,fov,aspect=pcall(zAPI,"camera")
    if not ok or not finite(x) or not finite(y) or not finite(z) or not finite(fx) or not finite(fy) or not finite(fz) then
        self.hudZoomPending=nil;return
    end
    local length=sqrt(fx*fx+fy*fy+fz*fz)
    if length<.001 then self.hudZoomPending=nil;return end
    -- Vertical camera lag during jumps/falls must not be mistaken for zoom.
    local camera={distance=sqrt((x-p.rawX)^2+(y-p.rawY)^2),pitch=fz/length,fov=fov,aspect=aspect,
        fx=fx/length,fy=fy/length,px=p.rawX,py=p.rawY,pz=p.rawZ}
    if not validCamera(camera) then self.hudZoomPending=nil;return end
    if not sameCamera(camera,self.hudCameraSample) then
        self.hudCameraSample=camera;self.hudCameraStable=0
    else
        self.hudCameraStable=(self.hudCameraStable or 0)+dt
        if self.hudCameraStable>=.4 then
            self.hudAlignPending=true;self.hudZoomPending=nil
        end
    end
end
function M:UpdateHUDFloor(ctx,p,elapsed)
    ctx.floorElapsed=(ctx.floorElapsed or 0)+elapsed
    local reset=ctx.floorSpace~=p.space or ctx.floorZone~=p.zone or
        ctx.floorX and (ctx.floorX-p.x)^2+(ctx.floorY-p.y)^2>40000
    if reset then
        ctx.floorGrounded=false;ctx.floorZ=p.z;ctx.floorMissZ=nil;ctx.floorStableTime=0;ctx.floorMissTime=0
    end
    if not reset and ctx.floorElapsed<.5 then return end
    local dt=ctx.floorElapsed
    ctx.floorElapsed=0;ctx.floorSpace=p.space;ctx.floorZone=p.zone;ctx.floorX=p.x;ctx.floorY=p.y
    ctx.floorTrace="unavailable"
    if p.rawX and type(zAPI)=="function" then
        -- Start just above the feet so an overhead roof cannot win the trace.
        local ok,hit,x,y,z=pcall(zAPI,"raycast",p.rawX,p.rawY,p.rawZ+.25,p.rawX,p.rawY,p.rawZ-180)
        if ok and hit==1 and finite(z) and z<=p.rawZ+.3 and z>=p.rawZ-180.1 then
            ctx.floorZ=z;ctx.floorGrounded=true
            ctx.floorTrace="hit";ctx.floorMissTime=0;ctx.floorMissZ=nil;ctx.floorStableTime=0
            return
        end
        ctx.floorTrace=ok and hit~=1 and "miss" or "invalid"
    end
    ctx.floorMissTime=(ctx.floorMissTime or 0)+dt
    if finite(p.z) then
        if not ctx.floorMissZ or abs(p.z-ctx.floorMissZ)>1 then
            ctx.floorMissZ=p.z;ctx.floorStableTime=0
        else ctx.floorStableTime=(ctx.floorStableTime or 0)+dt end
        -- Keep the ground through jumps/falls. If traces keep missing after
        -- settling on another level, do not keep the old floor indefinitely.
        if not ctx.floorGrounded or ctx.floorStableTime>=2 and abs(p.z-ctx.floorZ)>3 then
            ctx.floorZ=p.z;ctx.floorGrounded=false
        end
    elseif not ctx.floorGrounded then ctx.floorZ=nil end
end
function M:CycleHUDHeightFilter()
    local nextFilter={normal="relaxed",relaxed="off",off="normal"}
    zMapDB.hudHeightFilter=nextFilter[zMapDB.hudHeightFilter] or "normal"
    self:RefreshSettingsPanel()
end
function M:HUDStatus()
    local ctx=self.hudContext
    if not ctx then self:Print("HUD: "..(zMapDB.hudEnabled and "waiting for player position." or "off."));return end
    local function height(z) return finite(z) and string.format("%.1f",z) or "unknown" end
    local source=ctx.floorGrounded and (ctx.floorTrace=="hit" and "ground trace" or "cached ground") or "feet fallback"
    self:Print("HUD height: feet "..height(ctx.player and ctx.player.z).."y | floor "..height(ctx.floorZ).."y ("..source..
        ") | trace "..(ctx.floorTrace or "waiting")..
        ((ctx.floorMissTime or 0)>0 and string.format(" (%.1fs)",ctx.floorMissTime) or "")..
        " | filter "..(zMapDB.hudHeightFilter or "normal")..".")
    local job,report=ctx.wallJob,ctx.wallReport
    if job then self:Print("HUD scan: pending | "..job.scanned.." records | "..job.heightRejected.." height-filtered.") end
    if report then
        local reason=""
        if report.tasks==0 then reason=" | no bundled wall cells in range"
        elseif report.scanned>0 and report.heightRejected==report.scanned then reason=" | all scanned walls rejected by height"
        elseif report.candidates==0 then reason=" | no matching walls in range"
        elseif not job and (ctx.wallShown or 0)==0 then reason=" | outside view or below fade/detail threshold" end
        self:Print("HUD last scan: "..report.scanned.." records | "..report.heightRejected.." height-filtered | "..
            report.candidates.." candidates at "..height(report.z).."y | "..(ctx.wallShown or 0).." drawn"..
            (report.limited and " | budget reached" or "")..reason..".")
    end
    if not ctx.frame:IsShown() then self:Print("HUD frame hidden: "..(not zMapDB.hudEnabled and "disabled" or
        (self.frame and self.frame:IsShown() or WorldMapFrame and WorldMapFrame:IsShown()) and "map open" or "player position unavailable")..".") end
end
function M:AnchorHUD(ctx,p)
    local reference=WorldFrame or UIParent
    local height=reference:GetHeight()
    if self.hudAlignPending then
        self.hudAlignPending=nil
        if p.rawX and type(zAPI)=="function" then
            local ok,x,y,depth=pcall(zAPI,"worldToScreen",p.rawX,p.rawY,p.rawZ)
            -- The native API returns normalized bottom-left screen coordinates.
            -- Capture the actual foot point once; never interpret it as pixels.
            if ok and finite(x) and finite(y) and finite(depth) and depth>0 and x>=0 and x<=1 and y>=.05 and y<=.95 then
                zMapDB.hudCenterX=x;zMapDB.hudCenterY=y
            end
        end
    end
    local fractionX,fraction=zMapDB.hudCenterX or .5,zMapDB.hudCenterY or .43
    local worldScale,frameScale=reference:GetEffectiveScale(),ctx.frame:GetEffectiveScale()
    local factor=frameScale>0 and worldScale/frameScale or 1
    local offsetX=(fractionX-.5)*reference:GetWidth()*factor+(zMapDB.hudOffsetX or 0)
    local offset=(fraction-.5)*height*factor+(zMapDB.hudOffsetY or 0)
    -- Convert the automatic screen point to frame units, then apply the
    -- user's offsets on both axes without changing the world coordinates.
    if ctx.anchorReference~=reference or ctx.anchorOffsetX~=offsetX or ctx.anchorOffsetY~=offset then
        ctx.frame:ClearAllPoints();ctx.frame:SetPoint("CENTER",reference,"CENTER",offsetX,offset)
        ctx.anchorReference=reference;ctx.anchorOffsetX=offsetX;ctx.anchorOffsetY=offset
    end
    ctx.anchorMode="fixed screen anchor"
end
local function prepareWalls(ctx,limit)
    local v=ctx.view;local prepared=ctx.wallPrepared
    if prepared and prepared.x==v.x and prepared.y==v.y and prepared.walls==ctx.walls and
        prepared.width==v.width and prepared.height==v.height and prepared.scale==v.scale and
        prepared.opacity==zMapDB.hudOpacity and prepared.limit==limit then return false end
    local reset=not prepared or prepared.walls~=ctx.walls or prepared.width~=v.width or
        prepared.height~=v.height or prepared.scale~=v.scale
    if reset then ctx.wallBaseX=v.x;ctx.wallBaseY=v.y end
    prepared=prepared or {};ctx.wallPrepared=prepared
    local records=ctx.wallSegments or {};ctx.wallSegments=records
    local visible=ctx.wallVisible or {};ctx.wallVisible=visible
    local scale=v.scale;local bx,by=ctx.wallBaseX,ctx.wallBaseY
    local px,py=(v.x-bx)*scale,(v.y-by)*scale
    local radius=max(1,min(v.width,v.height)/2-10);local inner=radius*radius*.49
    local changed,used=reset,0
    -- Circular clipping, radial fade and segment length are invariant under
    -- heading changes. Prepare them in unrotated pixels, only after movement.
    for i,wall in ipairs(ctx.walls) do
        local record=records[i]
        if not record then record={};records[i]=record end
        if reset or record.source~=wall then
            record.geometry=(record.geometry or 0)+1
            record.ax=(wall[1]-bx)*scale;record.ay=(wall[2]-by)*scale
            record.bx=(wall[3]-bx)*scale;record.by=(wall[4]-by)*scale
            record.mx=(record.ax+record.bx)/2;record.my=(record.ay+record.by)/2
            local dx,dy=record.bx-record.ax,record.by-record.ay
            record.baseLength2=dx*dx+dy*dy;record.baseLength=sqrt(record.baseLength2)
            local safeRadius=radius-record.baseLength/2
            record.inside2=safeRadius>=0 and safeRadius*safeRadius or -1
            record.source=wall
        end
        local x,y,u,w=record.ax,record.ay,record.bx,record.by
        local mx,my=record.mx-px,record.my-py
        local distance=mx*mx+my*my
        local length2,length=record.baseLength2,record.baseLength
        if distance>record.inside2 then
            x,y,u,w=clipCircle(x,y,u,w,px,py,radius)
            if x then
                mx,my=(x+u)/2-px,(y+w)/2-py;distance=mx*mx+my*my
                local dx,dy=u-x,w-y;length2=dx*dx+dy*dy
                if record.x~=x or record.y~=y or record.u~=u or record.v~=w then length=sqrt(length2)
                else length=record.length end
            end
        end
        if x then
            local alpha=zMapDB.hudOpacity
            if distance>inner then alpha=alpha*max(0,(1-sqrt(distance)/radius)/.3) end
            if alpha>=.015 and length2>=1 then
                used=used+1
                if record.x~=x or record.y~=y or record.u~=u or record.v~=w then
                    record.x=x;record.y=y;record.u=u;record.v=w
                    record.length2=length2;record.length=length;record.geometry=record.geometry+1;changed=true
                end
                if record.alpha~=alpha then record.alpha=alpha;changed=true end
                if visible[used]~=record then visible[used]=record;changed=true end
                if used>=limit then break end
            end
        end
    end
    for i=used+1,table.getn(visible) do visible[i]=nil;changed=true end
    -- A later query may contain fewer records; do not retain old geometry.
    for i=table.getn(ctx.walls)+1,table.getn(records) do records[i]=nil end
    prepared.x=v.x;prepared.y=v.y;prepared.walls=ctx.walls;prepared.width=v.width;prepared.height=v.height
    prepared.scale=v.scale;prepared.opacity=zMapDB.hudOpacity;prepared.limit=limit
    ctx.wallShown=used
    return changed
end
function M:RenderHUDWalls(ctx,angle)
    local v=ctx.view;local draw=ctx.wallDraw
    if draw and draw.x==v.x and draw.y==v.y and abs(draw.angle-angle)<=.001 and draw.walls==ctx.walls and
        draw.width==v.width and draw.height==v.height and draw.scale==v.scale and
        draw.opacity==zMapDB.hudOpacity and draw.limit==self.hudWallLimit then return end
    local changed=prepareWalls(ctx,self.hudWallLimit)
    local c,s,scale=ctx.cos,ctx.sin,v.scale
    local offsetX=(c*(ctx.wallBaseX-v.x)-s*(ctx.wallBaseY-v.y))*scale
    local offsetY=(s*(ctx.wallBaseX-v.x)+c*(ctx.wallBaseY-v.y))*scale
    if ctx.wallOffsetX~=offsetX or ctx.wallOffsetY~=offsetY then
        ctx.layers.walls:SetPoint("TOPLEFT",ctx.viewport,"TOPLEFT",offsetX,-offsetY)
        ctx.wallOffsetX=offsetX;ctx.wallOffsetY=offsetY
    end
    if changed or not draw or draw.angle~=angle then
        local cx,cy=v.width/2,v.height/2
        local rotated=not draw or draw.angle~=angle
        for i,record in ipairs(ctx.wallVisible) do
            local texture=ctx.wallTextures[i]
            if not rotated and texture and texture.hudRecord==record and texture.hudGeometry==record.geometry then
                -- Straight movement leaves an unclipped wall's local geometry
                -- alone. Only an edge wall's radial opacity may need a setter.
                if not texture.hudAlpha or abs(texture.hudAlpha-record.alpha)>.000001 then
                    texture:SetVertexColor(.74,.84,.81,record.alpha);texture.hudAlpha=record.alpha
                end
                if not texture.hudShown then texture:Show();texture.hudShown=true end
            else
                local x,y=cx+c*record.x-s*record.y,cy+s*record.x+c*record.y
                local u,w=cx+c*record.u-s*record.v,cy+s*record.u+c*record.v
                drawWall(ctx,i,x,y,u,w,record.alpha,record.length2,record.length,ctx.layers.walls,true)
                texture=ctx.wallTextures[i];texture.hudRecord=record;texture.hudGeometry=record.geometry
            end
        end
        for i=ctx.wallShown+1,table.getn(ctx.wallTextures) do
            local texture=ctx.wallTextures[i]
            if texture.hudShown then texture:Hide();texture.hudShown=false end
        end
    end
    draw=draw or {};ctx.wallDraw=draw
    draw.x=v.x;draw.y=v.y;draw.angle=angle;draw.walls=ctx.walls
    draw.width=v.width;draw.height=v.height;draw.scale=v.scale;draw.opacity=zMapDB.hudOpacity;draw.limit=self.hudWallLimit
end
function M:UpdateHUD(elapsed,pose)
    if not zMapDB.hudEnabled or not self.miniWorld or self.frame and self.frame:IsShown() or WorldMapFrame and WorldMapFrame:IsShown() then
        if self.hudContext then self.hudContext.frame:Hide() end;return
    end
    self.hudElapsed=(self.hudElapsed or 0)+elapsed
    local refresh=self.hudElapsed>=.05
    local dt=self.hudElapsed
    if refresh then self.hudElapsed=0 end
    if not refresh and not self.hudContext then return end
    local perf=OctoPerf;local started,token
    if perf and perf.BeginOperation and perf.EndOperation then started,token=perf.BeginOperation() end
    local part=started and perf.BeginOperation()
    local mini=self.miniContext and self.miniContext.frame:IsShown()
    if refresh and not mini then self:SamplePlayer();self:UpdateGather(dt) end
    local p=pose or self:ReadFollowPlayer()
    if part then perf.EndOperation("zMap HUD sampling",part,token) end
    if not p then
        if self.hudContext then self.hudContext.frame:Hide() end
        if started then perf.EndOperation("zMap HUD full update",started,token) end
        return
    end
    local ctx=self.hudContext or self:CreateHUDContext();local v=ctx.view
    local diameter=min(640,UIParent:GetWidth()*.6,UIParent:GetHeight()*.8)
    v.width=diameter;v.height=diameter
    v.x=p.x;v.y=p.y;v.space=p.space;v.scale=v.width/(zMapDB.hudRange*2)
    ctx.player=p;ctx.gatherNodes=self.gatherNodes;ctx.serial=ctx.serial+1
    local angle=self:PlayerFacing() or 0;ctx.cos=math.cos(angle);ctx.sin=math.sin(angle)
    if ctx.frame:GetWidth()~=v.width then ctx.frame:SetWidth(v.width) end
    if ctx.frame:GetHeight()~=v.height then ctx.frame:SetHeight(v.height) end
    self:UpdateHUDCamera(elapsed,p);self:AnchorHUD(ctx,p);ctx.frame:Show()
    self:UpdateHUDFloor(ctx,p,elapsed)
    part=started and perf.BeginOperation()
    local q=ctx.wallQuery
    local floorZ=ctx.floorZ
    if refresh then
        local distance=q and (q.x-p.x)^2+(q.y-p.y)^2 or 0
        local invalid=not q or q.space~=p.space or distance>40000 or q.filter~=zMapDB.hudHeightFilter or q.range~=zMapDB.hudRange
        local heightChanged=zMapDB.hudHeightFilter~="off" and
            (floorZ and (not q or not q.z or abs(q.z-floorZ)>3) or not floorZ and q and q.z)
        if invalid or not ctx.wallJob and (not ctx.wallReport or ctx.wallReport.query~=q or distance>100 or heightChanged) then
            -- Let a bounded scan finish while running over slopes. Restarting
            -- every ten yards/three yards of height could starve dense queries.
            -- Keep the previous floor visible until its replacement is ready.
            if not q or q.space~=p.space or distance>40000 then ctx.walls={};ctx.wallReport=nil end
            self:StartHUDWallQuery()
        end
    end
    if refresh then self:StepHUDWallQuery() end
    if part then perf.EndOperation("zMap HUD wall query",part,token) end
    part=started and perf.BeginOperation()
    if refresh then
        ctx:RenderGatherMarkers();ctx:UpdateGatherVisuals(dt);ctx:RenderPFQuest();ctx:RenderTracking()
        for _,marker in ipairs(rawget(ctx,"pfMarkers") or {}) do
            if marker:IsShown() then marker.hudBaseAlpha=marker:GetAlpha()*.85 end
        end
    end
    if part then perf.EndOperation("zMap HUD icon refresh",part,token) end
    part=started and perf.BeginOperation()
    self:RenderHUDWalls(ctx,angle)
    if part then perf.EndOperation("zMap HUD wall rendering",part,token) end
    part=started and perf.BeginOperation()
    ctx:ReprojectFollowMarkers();self:RenderHUDUnits(ctx,p,refresh)
    if part then perf.EndOperation("zMap HUD marker motion",part,token) end
    if started then perf.EndOperation("zMap HUD full update",started,token) end
end
function M:InitializeHUD()
    zMapDB.hudEnabled=zMapDB.hudEnabled==true;zMapDB.hudQuests=zMapDB.hudQuests==true
    for _,key in ipairs({"hudPlayer","hudPet","hudTarget","hudParty"}) do zMapDB[key]=zMapDB[key]~=false end
    zMapDB.hudRange=self.Clamp(tonumber(zMapDB.hudRange) or 240,120,360)
    zMapDB.hudOpacity=self.Clamp(tonumber(zMapDB.hudOpacity) or .35,.1,.6)
    if zMapDB.hudHeightFilter~="relaxed" and zMapDB.hudHeightFilter~="off" then zMapDB.hudHeightFilter="normal" end
    zMapDB.hudOffsetX=offsetValue(zMapDB.hudOffsetX);zMapDB.hudOffsetY=offsetValue(zMapDB.hudOffsetY)
    if zMapDB.hudProjectionVersion~=1 then
        zMapDB.hudCenterX=nil;zMapDB.hudCenterY=nil;zMapDB.hudCamera=nil
        zMapDB.hudProjectionVersion=1
    end
    local centerX=tonumber(zMapDB.hudCenterX)
    zMapDB.hudCenterX=finite(centerX) and centerX>=0 and centerX<=1 and centerX or nil
    local center=tonumber(zMapDB.hudCenterY)
    zMapDB.hudCenterY=finite(center) and center>=.05 and center<=.95 and center or nil
    self.hudAlignPending=zMapDB.hudCenterY==nil
    -- Retire passive camera signatures without changing the saved screen point.
    zMapDB.hudCamera=nil;zMapDB.hudCameraVersion=nil
    self.hudZoomPending=nil;self.hudCameraSample=nil;self.hudCameraStable=0;self.hudCameraElapsed=0
    self:InstallHUDCameraZoomHooks()
end
function M:InstallHUDBinding()
    self:InstallHUDCameraZoomHooks()
    -- Apply the requested default once, after the client's bindings are loaded.
    -- Later edits in Key Bindings belong to the user and must survive reloads.
    if zMapDB.hudBindingInstalled or type(SetBinding)~="function" or type(SaveBindings)~="function" then return end
    if SetBinding("SHIFT-M","ZMAP_HUD") then
        SaveBindings(GetCurrentBindingSet and GetCurrentBindingSet() or 1)
        zMapDB.hudBindingInstalled=true
    end
end
