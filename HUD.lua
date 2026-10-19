-- Optional click-through automap: native wall traces, nodes, heading up.
local M=zMap
local DATA=zMapHudData or {models={},placements={},grid={},cell=128}
local floor,abs,min,max,sqrt=math.floor,math.abs,math.min,math.max,math.sqrt
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
    local radius=sqrt(((x-v.width/2)/(v.width/2-10))^2+((y-v.height/2)/(v.height/2-10))^2)
    return self.Clamp((1-radius)/.3,0,1)
end
local function clipEdge(p,q,lo,hi)
    if p==0 then if q<0 then return end else
        local f=q/p;if p<0 then lo=max(lo,f) else hi=min(hi,f) end
    end
    if lo<=hi then return lo,hi end
end
local function clipLine(x,y,u,v,w,h)
    local dx,dy=u-x,v-y
    local lo,hi=clipEdge(-dx,x-4,0,1);if not lo then return end
    lo,hi=clipEdge(dx,w-4-x,lo,hi);if not lo then return end
    lo,hi=clipEdge(-dy,y-4,lo,hi);if not lo then return end
    lo,hi=clipEdge(dy,h-4-y,lo,hi);if not lo then return end
    return x+lo*dx,y+lo*dy,x+hi*dx,y+hi*dy
end
local function lineUV(c,s,length,x,y) return .5+(c*x+s*y)/length,.5+(-s*x+c*y)/(32*1.2) end
function M:HUDLine(index,x,y,u,v,alpha)
    x,y,u,v=clipLine(x,y,u,v,self.view.width,self.view.height)
    if not x then return false end
    alpha=alpha*self:HUDVisibility((x+u)/2,(y+v)/2)
    local dx,dy=u-x,v-y;local length=sqrt(dx*dx+dy*dy)
    if alpha<.015 or length<1 then return false end
    local texture=self.wallTextures[index]
    if not texture then
        texture=self.layers.walls:CreateTexture(nil,"ARTWORK");self.wallTextures[index]=texture
        texture:SetTexture("Interface\\AddOns\\z_Map\\Media\\Hud\\Line")
    end
    local width,height=abs(dx)+2,abs(dy)+2;local c,s=dx/length,dy/length
    local a,b=lineUV(c,s,length,-width/2,-height/2);local d,e=lineUV(c,s,length,-width/2,height/2)
    local f,g=lineUV(c,s,length,width/2,-height/2);local h,i=lineUV(c,s,length,width/2,height/2)
    texture:SetWidth(width);texture:SetHeight(height)
    texture:SetPoint("CENTER",self.viewport,"TOPLEFT",(x+u)/2,-(y+v)/2)
    texture:SetTexCoord(a,b,d,e,f,g,h,i);texture:SetVertexColor(.74,.84,.81,alpha);texture:Show()
    return true
end
function M:StartHUDWallQuery()
    local ctx=self.hudContext;local v=ctx.view;local radius=zMapDB.hudRange*1.25
    local cell=DATA.cell;local seen,tasks={},{}
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
                            if raw then table.insert(tasks,{raw=raw,x=cx*cell,y=cy*cell,placement=p,
                                distance=(localX-(cx+.5)*cell)^2+(localY-(cy+.5)*cell)^2}) end
                        end
                    end
                end
            end
        end
    end
    table.sort(tasks,function(a,b) return a.distance<b.distance end)
    ctx.wallJob={tasks=tasks,task=1,offset=1,results={},scanned=0}
    ctx.wallQuery={x=v.x,y=v.y,space=v.space,z=ctx.player.z,range=zMapDB.hudRange}
end
function M:StepHUDWallQuery()
    local ctx=self.hudContext;local job=ctx.wallJob
    if not job then return end
    local q=ctx.wallQuery;local z=q.z and q.z+2
    local spent=0
    while spent<1200 and job.scanned<16000 do
        local task=job.tasks[job.task]
        if not task then break end
        if job.offset>string.len(task.raw) then job.task=job.task+1;job.offset=1
        else
            local raw,k,p=task.raw,job.offset,task.placement
            job.offset=k+14;spent=spent+1;job.scanned=job.scanned+1
            local low,high=unpackNumber(raw,k+8,3)-65536+p[7],unpackNumber(raw,k+11,3)-65536+p[7]
            if not z or z>=low-.75 and z<=high+.75 then
                local x,y=task.x+unpackNumber(raw,k,2),task.y+unpackNumber(raw,k+2,2)
                local u,v=task.x+unpackNumber(raw,k+4,2),task.y+unpackNumber(raw,k+6,2)
                x,y,u,v=p[3]+p[5]*x+p[6]*y,p[4]+p[6]*x-p[5]*y,p[3]+p[5]*u+p[6]*v,p[4]+p[6]*u-p[5]*v
                local distance=((x+u)/2-q.x)^2+((y+v)/2-q.y)^2
                if distance<(zMapDB.hudRange*1.25)^2 then
                    table.insert(job.results,{x,y,u,v,distance})
                    if table.getn(job.results)>=2400 then break end
                end
            end
        end
    end
    if not job.tasks[job.task] or job.scanned>=16000 or table.getn(job.results)>=2400 then
        table.sort(job.results,function(a,b) return a[5]<b[5] end)
        ctx.walls=job.results;ctx.wallScanned=job.scanned;ctx.wallJob=nil
    end
end
function M:CreateHUDContext()
    local frame=CreateFrame("Frame",nil,UIParent);frame:SetFrameStrata("LOW");frame:EnableMouse(false)
    frame:SetPoint("CENTER",UIParent,"CENTER",0,35)
    local ctx=setmetatable({hud=true,frame=frame,viewport=frame,view={},layers={},wallTextures={},walls={},serial=0,
        gatherMarkers={},gatherMarkerFree={},gatherRenderEpoch=0,gatherMarkerLimit=128,
        hoveredGather=false,gatherTooltipMarker=false,cos=1,sin=0}, {__index=M})
    for i,name in ipairs({"walls","gather","questRoutes","quests","markers"}) do
        local layer=CreateFrame("Frame",nil,frame);layer:SetAllPoints(frame);layer:SetFrameLevel(frame:GetFrameLevel()+i);ctx.layers[name]=layer
    end
    ctx.ToScreen=M.HUDToScreen;ctx.ToWorld=M.HUDToWorld
    ctx.UpdateGatherStatus=function() end
    ctx.GatherPresentation=function() return 13,.9,false end
    ctx.GatherNodeVisible=function(self,node)
        local sx,sy=self:ToScreen(node.x,node.y)
        return self:HUDVisibility(sx,sy)>.03 and (not self.player.z or not node.z or abs(node.z-self.player.z)<18)
    end
    ctx.MakeGatherMarker=function(self)
        local marker=M.MakeGatherMarker(self);marker:EnableMouse(false);marker:EnableMouseWheel(false);return marker
    end
    ctx.MakePFQuestMarker=function(self)
        local marker=M.MakePFQuestMarker(self);marker:EnableMouse(false);marker:EnableMouseWheel(false);return marker
    end
    ctx.RenderPFQuestRoutes=function() end
    ctx.RenderPFQuest=function(self)
        if zMapDB.hudQuests then M.RenderPFQuest(self) else self:HidePFQuest() end
    end
    ctx.playerMarker=ctx:MakeMarker(1,1,1,16)
    ctx.playerMarker.texture:SetTexture("Interface\\Minimap\\MinimapArrow");ctx.playerMarker.texture:SetTexCoord(0,1,0,1)
    ctx.playerMarker:SetFrameLevel(ctx.layers.markers:GetFrameLevel()+4);ctx.playerMarker:SetAlpha(.8)
    frame:SetScript("OnHide",function() ctx:HidePFQuest() end)
    frame:Hide();self.hudContext=ctx;return ctx
end
function M:SetHUD(enabled)
    zMapDB.hudEnabled=enabled==true
    if not enabled and self.hudContext then self.hudContext.frame:Hide();self.hudContext.wallJob=nil end
    self:RefreshSettingsPanel()
end
function M:UpdateHUD(elapsed)
    if not zMapDB.hudEnabled or not self.miniWorld or self.frame and self.frame:IsShown() or WorldMapFrame and WorldMapFrame:IsShown() then
        if self.hudContext then self.hudContext.frame:Hide() end;return
    end
    self.hudElapsed=(self.hudElapsed or 0)+elapsed
    if self.hudElapsed<.05 then return end
    local dt=self.hudElapsed;self.hudElapsed=0
    local mini=self.miniContext and self.miniContext.frame:IsShown()
    if not mini then self:SamplePlayer();self:UpdateGather(dt) end
    local p=self.player
    if not p then if self.hudContext then self.hudContext.frame:Hide() end;return end
    local ctx=self.hudContext or self:CreateHUDContext();local v=ctx.view
    v.width=min(640,UIParent:GetWidth()*.6);v.height=min(440,UIParent:GetHeight()*.55)
    v.x=p.x;v.y=p.y;v.space=p.space;v.scale=v.width/(zMapDB.hudRange*2)
    ctx.player=p;ctx.gatherNodes=self.gatherNodes;ctx.serial=ctx.serial+1
    local angle=self:PlayerFacing() or 0;ctx.cos=math.cos(angle);ctx.sin=math.sin(angle)
    ctx.frame:SetWidth(v.width);ctx.frame:SetHeight(v.height);ctx.frame:Show()
    local q=ctx.wallQuery
    if not q or q.space~=p.space or (q.x-p.x)^2+(q.y-p.y)^2>100 or q.range~=zMapDB.hudRange or
        p.z and (not q.z or abs(q.z-p.z)>3) or not p.z and q.z then
        if not q or q.space~=p.space or p.z and q.z and abs(q.z-p.z)>3 then ctx.walls={} end
        self:StartHUDWallQuery()
    end
    self:StepHUDWallQuery()
    local draw=ctx.wallDraw
    if not draw or draw.x~=v.x or draw.y~=v.y or abs(draw.angle-angle)>.001 or draw.walls~=ctx.walls or
        draw.width~=v.width or draw.height~=v.height or draw.scale~=v.scale or draw.opacity~=zMapDB.hudOpacity then
        local used=0
        for _,wall in ipairs(ctx.walls) do
            local x,y=ctx:ToScreen(wall[1],wall[2]);local u,w=ctx:ToScreen(wall[3],wall[4])
            if ctx:HUDLine(used+1,x,y,u,w,zMapDB.hudOpacity) then used=used+1 end
            if used>=512 then break end
        end
        for i=used+1,table.getn(ctx.wallTextures) do ctx.wallTextures[i]:Hide() end
        ctx.wallShown=used
        ctx.wallDraw={x=v.x,y=v.y,angle=angle,walls=ctx.walls,width=v.width,height=v.height,scale=v.scale,opacity=zMapDB.hudOpacity}
    end
    ctx:RenderGatherMarkers();ctx:UpdateGatherVisuals(dt);ctx:RenderPFQuest()
    for _,marker in pairs(ctx.gatherMarkers) do
        if marker:IsShown() then marker:SetAlpha(.9*ctx:HUDVisibility(marker.sx,marker.sy)) end
    end
    for _,marker in ipairs(rawget(ctx,"pfMarkers") or {}) do
        if marker:IsShown() then
            marker:SetAlpha(marker:GetAlpha()*.85*ctx:HUDVisibility(marker.zMapPointX,marker.zMapPointY))
        end
    end
    ctx:PlaceMarker(ctx.playerMarker,p.x,p.y,p.space)
end
function M:InitializeHUD()
    zMapDB.hudEnabled=zMapDB.hudEnabled==true;zMapDB.hudQuests=zMapDB.hudQuests==true
    zMapDB.hudRange=self.Clamp(tonumber(zMapDB.hudRange) or 240,120,360)
    zMapDB.hudOpacity=self.Clamp(tonumber(zMapDB.hudOpacity) or .35,.1,.6)
end
