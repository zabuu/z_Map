-- Optional click-through automap: native wall traces, nodes, heading up.
local M=zMap
M.hudWallLimit=1536
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
    local radius=max(1,min(v.width,v.height)/2-10)
    local distance=sqrt((x-v.width/2)^2+(y-v.height/2)^2)/radius
    return self.Clamp((1-distance)/.3,0,1)
end
local function clipCircle(x,y,u,v,cx,cy,radius)
    local dx,dy=u-x,v-y;local ox,oy=x-cx,y-cy
    local a=dx*dx+dy*dy
    if a<.000001 then return end
    local b=ox*dx+oy*dy;local c=ox*ox+oy*oy-radius*radius
    local discriminant=b*b-a*c
    if discriminant<=0 then return end
    local root=sqrt(discriminant)
    local lo,hi=max(0,(-b-root)/a),min(1,(-b+root)/a)
    if lo>=hi then return end
    return x+lo*dx,y+lo*dy,x+hi*dx,y+hi*dy
end
local function lineUV(c,s,length,x,y) return .5+(c*x+s*y)/length,.5+(-s*x+c*y)/(32*1.2) end
function M:HUDLine(index,x,y,u,v,alpha)
    local view=self.view;local radius=max(1,min(view.width,view.height)/2-10)
    x,y,u,v=clipCircle(x,y,u,v,view.width/2,view.height/2,radius)
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
    -- Explicit false keeps this context from inheriting the full-map arrow.
    local ctx=setmetatable({hud=true,frame=frame,viewport=frame,view={},layers={},wallTextures={},walls={},serial=0,
        gatherMarkers={},gatherMarkerFree={},gatherRenderEpoch=0,gatherMarkerLimit=128,
        hoveredGather=false,gatherTooltipMarker=false,cos=1,sin=0,smoothFollow=true,playerMarker=false}, {__index=M})
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
    frame:SetScript("OnHide",function() ctx:HidePFQuest() end)
    frame:Hide();self.hudContext=ctx;return ctx
end
function M:SetHUD(enabled)
    zMapDB.hudEnabled=enabled==true
    if not enabled and self.hudContext then self.hudContext.frame:Hide();self.hudContext.wallJob=nil end
    self:RefreshSettingsPanel()
end
local function finite(value) return type(value)=="number" and value==value and abs(value)<10000000 end
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
        abs(a.pitch-b.pitch)<=.01 and abs(a.fov-b.fov)<=.01 and abs(a.aspect-b.aspect)<=.01
end
function M:AlignHUD()
    self.hudAlignPending=true
    self:SetHUD(true)
end
function M:CenterHUDOnPlayer()
    self:ResetHUDOffsets()
    self:AlignHUD()
end
function M:UpdateHUDCamera(elapsed,p)
    self.hudCameraElapsed=(self.hudCameraElapsed or 0)+elapsed
    if self.hudCameraElapsed<.2 and not self.hudAlignPending then return end
    local dt=self.hudCameraElapsed;self.hudCameraElapsed=0
    if not p.rawX or type(zAPI)~="function" then return end
    local ok,x,y,z,fx,fy,fz,rx,ry,rz,ux,uy,uz,fov,aspect=pcall(zAPI,"camera")
    if not ok or not finite(x) or not finite(y) or not finite(z) or not finite(fx) or not finite(fy) or not finite(fz) then return end
    local length=sqrt(fx*fx+fy*fy+fz*fz)
    if length<.001 then return end
    -- Translation and horizontal yaw do not change the vertical calibration.
    local camera={distance=sqrt((x-p.rawX)^2+(y-p.rawY)^2+(z-p.rawZ)^2),pitch=fz/length,fov=fov,aspect=aspect}
    if not validCamera(camera) then return end
    if not sameCamera(camera,self.hudCameraSample) then
        self.hudCameraSample=camera;self.hudCameraStable=0
        self.hudCameraNeedsAlignment=not sameCamera(camera,self.hudCameraApplied)
    else
        self.hudCameraStable=(self.hudCameraStable or 0)+dt
        if self.hudCameraStable>=.4 and self.hudCameraNeedsAlignment then
            self.hudAlignPending=true;self.hudCameraNeedsAlignment=false
        end
    end
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
                if self.hudCameraSample then zMapDB.hudCamera=self.hudCameraSample end
            end
        end
        self.hudCameraApplied=self.hudCameraSample;self.hudCameraNeedsAlignment=false
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
function M:RenderHUDWalls(ctx,angle)
    local v=ctx.view
    local draw=ctx.wallDraw
    if not draw or draw.x~=v.x or draw.y~=v.y or abs(draw.angle-angle)>.001 or draw.walls~=ctx.walls or
        draw.width~=v.width or draw.height~=v.height or draw.scale~=v.scale or draw.opacity~=zMapDB.hudOpacity then
        local used=0
        for _,wall in ipairs(ctx.walls) do
            local x,y=ctx:ToScreen(wall[1],wall[2]);local u,w=ctx:ToScreen(wall[3],wall[4])
            if ctx:HUDLine(used+1,x,y,u,w,zMapDB.hudOpacity) then used=used+1 end
            if used>=self.hudWallLimit then break end
        end
        for i=used+1,table.getn(ctx.wallTextures) do ctx.wallTextures[i]:Hide() end
        ctx.wallShown=used
        ctx.wallDraw={x=v.x,y=v.y,angle=angle,walls=ctx.walls,width=v.width,height=v.height,scale=v.scale,opacity=zMapDB.hudOpacity}
    end
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
    local mini=self.miniContext and self.miniContext.frame:IsShown()
    if refresh and not mini then self:SamplePlayer();self:UpdateGather(dt) end
    local p=pose or self:ReadFollowPlayer()
    if not p then if self.hudContext then self.hudContext.frame:Hide() end;return end
    local ctx=self.hudContext or self:CreateHUDContext();local v=ctx.view
    local diameter=min(640,UIParent:GetWidth()*.6,UIParent:GetHeight()*.8)
    v.width=diameter;v.height=diameter
    v.x=p.x;v.y=p.y;v.space=p.space;v.scale=v.width/(zMapDB.hudRange*2)
    ctx.player=p;ctx.gatherNodes=self.gatherNodes;ctx.serial=ctx.serial+1
    local angle=self:PlayerFacing() or 0;ctx.cos=math.cos(angle);ctx.sin=math.sin(angle)
    if ctx.frame:GetWidth()~=v.width then ctx.frame:SetWidth(v.width) end
    if ctx.frame:GetHeight()~=v.height then ctx.frame:SetHeight(v.height) end
    self:UpdateHUDCamera(elapsed,p);self:AnchorHUD(ctx,p);ctx.frame:Show()
    local q=ctx.wallQuery
    if refresh and (not q or q.space~=p.space or (q.x-p.x)^2+(q.y-p.y)^2>100 or q.range~=zMapDB.hudRange or
        p.z and (not q.z or abs(q.z-p.z)>3) or not p.z and q.z) then
        if not q or q.space~=p.space or p.z and q.z and abs(q.z-p.z)>3 then ctx.walls={} end
        self:StartHUDWallQuery()
    end
    if refresh then
        self:StepHUDWallQuery()
        ctx:RenderGatherMarkers();ctx:UpdateGatherVisuals(dt);ctx:RenderPFQuest()
        for _,marker in ipairs(rawget(ctx,"pfMarkers") or {}) do
            if marker:IsShown() then marker.hudBaseAlpha=marker:GetAlpha()*.85 end
        end
    end
    self:RenderHUDWalls(ctx,angle);ctx:ReprojectFollowMarkers()
end
function M:InitializeHUD()
    zMapDB.hudEnabled=zMapDB.hudEnabled==true;zMapDB.hudQuests=zMapDB.hudQuests==true
    zMapDB.hudRange=self.Clamp(tonumber(zMapDB.hudRange) or 240,120,360)
    zMapDB.hudOpacity=self.Clamp(tonumber(zMapDB.hudOpacity) or .35,.1,.6)
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
    zMapDB.hudCamera=validCamera(zMapDB.hudCamera) and zMapDB.hudCamera or nil
    self.hudCameraApplied=zMapDB.hudCamera;self.hudCameraSample=nil;self.hudCameraStable=0;self.hudCameraElapsed=0;self.hudCameraNeedsAlignment=false
end
function M:InstallHUDBinding()
    -- Apply the requested default once, after the client's bindings are loaded.
    -- Later edits in Key Bindings belong to the user and must survive reloads.
    if zMapDB.hudBindingInstalled or type(SetBinding)~="function" or type(SaveBindings)~="function" then return end
    if SetBinding("SHIFT-M","ZMAP_HUD") then
        SaveBindings(GetCurrentBindingSet and GetCurrentBindingSet() or 1)
        zMapDB.hudBindingInstalled=true
    end
end
