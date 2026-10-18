-- Optional bridge to the running pfQuest. Its database and frames stay owned
-- by pfQuest; each atlas viewport has its own projected buttons and path dots.
local M=zMap
local STEP=1024
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<10000000 end
local function pack(...) return {n=arg.n,unpack(arg,1,arg.n)} end
local function invoke(frame,handler)
    if not handler then return end
    local previous=this;this=frame
    local ok,err=pcall(handler);this=previous
    if not ok then error(err) end
end
function M:PFQuestAvailable()
    return pfMap and pfQuest and type(pfQuest_config)=="table" and pfQuestConfig and type(pfQuestConfig.path)=="string" and
        type(pfMap.nodes)=="table" and type(pfMap.BuildNode)=="function" and type(pfMap.UpdateNode)=="function"
end
function M:PFQuestZone(id)
    local zone=self.byArea[tonumber(id)]
    if zone then return zone end
    local name=pfDB and pfDB.zones and pfDB.zones.loc and pfDB.zones.loc[id]
    if name then for _,z in ipairs(self.data.zones) do if z.name==name then return z end end end
end
function M:InvalidatePFQuest()
    self.pfRevision=(self.pfRevision or 0)+1;self.pfQuietUntil=(GetTime and GetTime() or 0)+.25
end
function M:HidePFQuest()
    for _,marker in ipairs(rawget(self,"pfMarkers") or {}) do if marker:IsShown() then marker:Hide() end end
    for _,dot in ipairs(rawget(self,"pfRouteTextures") or {}) do if dot:IsShown() then dot:Hide() end end
    self.pfShown=0;self.pfRoutesShown=0
end
function M:SetPFQuest(enabled)
    zMapDB.pfQuest=enabled==true
    self:HidePFQuest();if self.miniContext then self.miniContext:HidePFQuest() end
    self:InvalidatePFQuest();self:RefreshSettingsPanel()
end
function M:RestorePFQuestMinimap()
    if self.pfSource then self.pfSource.xPlayer=nil;self.pfSource.tick=nil end
end
local function changedAfter(previous)
    return function(...)
        local result=pack(previous(unpack(arg,1,arg.n)))
        M:InvalidatePFQuest();return unpack(result,1,result.n)
    end
end
function M:InstallPFQuest()
    if not self:PFQuestAvailable() or self.pfSource==pfMap then return end
    self.pfSource=pfMap
    for _,name in ipairs({"AddNode","DeleteNode","UpdateNodes"}) do
        if type(pfMap[name])=="function" then pfMap[name]=changedAfter(pfMap[name]) end
    end
    local show=pfMap.ShowMapID
    if show then pfMap.ShowMapID=function(frame,id)
        if not id then return show(frame,id) end
        local zone=M:PFQuestZone(id)
        if zMapDB.pfQuest and zMapDB.replace and not M.nativeOnly and zone then
            M:BuildUI()
            if WorldMapFrame and WorldMapFrame:IsShown() then HideUIPanel(WorldMapFrame) end
            M.frame:Show();zMapDB.follow=false;M:FocusZone(zone);return true
        end
        if M.frame and M.frame:IsShown() then M.frame:Hide() end
        local previous=M.nativeOnly;M.nativeOnly=true
        local result=pack(pcall(show,frame,id));M.nativeOnly=previous
        if not result[1] then error(result[2]) end
        return unpack(result,2,result.n)
    end end
    local mini=pfMap.UpdateMinimap
    if mini then pfMap.UpdateMinimap=function(...)
        local result=pack(mini(unpack(arg,1,arg.n)))
        if M.miniContext and M.miniContext.frame:IsShown() then
            for _,pin in pairs(pfMap.mpins or {}) do if pin:IsShown() then pin:Hide() end end
        end
        return unpack(result,1,result.n)
    end end
    self:InvalidatePFQuest();self:RefreshSettingsPanel()
end
function M:InitializePFQuest()
    zMapDB.pfQuest=zMapDB.pfQuest~=false
    self:InstallPFQuest()
end
local function priority(meta)
    local texture=meta.texture or ""
    local layer=string.find(texture,"cluster_",1,true) and 9 or
        string.find(texture,"complete_c",1,true) and 4 or
        string.find(texture,"complete",1,true) and 3 or
        string.find(texture,"available_c",1,true) and 2 or
        string.find(texture,"icon_vendor",1,true) and 5 or
        string.find(texture,"fav",1,true) and 6 or 1
    if meta.cluster and meta.priority then layer=layer+10-math.min(meta.priority,10) end
    return layer
end
function M:BuildPFQuestIndex(revision)
    local job={grid={},maps={},index=1,count=0,revision=revision};self.pfBuilder=job
    for addon,maps in pairs(pfMap.nodes) do
        for id,nodes in pairs(maps) do
            local zone=self:PFQuestZone(id)
            if zone then table.insert(job.maps,{addon=addon,zone=zone,nodes=nodes}) end
        end
    end
end
function M:StepPFQuestIndex()
    local job=self.pfBuilder;local work=0
    -- Stock 1.12 does not register Lua's coroutine library. Persist ordinary
    -- table cursors, and cancel before resuming if the source revision changed.
    while work<500 and job.index<=table.getn(job.maps) do
        local task=job.maps[job.index];local coords,node=next(task.nodes,job.key)
        if not coords then job.index=job.index+1;job.key=nil
        else
            job.key=coords;work=work+1
            local best,rank
            for _,meta in pairs(node) do
                local p=priority(meta)
                if meta.spawn and (not rank or p>rank) then best=meta;rank=p end
            end
            local _,_,xs,ys=string.find(coords,"^([^|]+)|([^|]+)$")
            local x,y=tonumber(xs),tonumber(ys);local zone=task.zone
            if best and finite(x) and finite(y) and x>=0 and x<=100 and y>=0 and y<=100 then
                x,y=self:ZonePoint(zone,x/100,y/100)
                local key=zone.space..":"..math.floor(x/STEP)..":"..math.floor(y/STEP)
                local bucket=job.grid[key];if not bucket then bucket={};job.grid[key]=bucket end
                job.count=job.count+1
                table.insert(bucket,{x=x,y=y,space=zone.space,node=node,addon=task.addon,meta=best,rank=rank,id=job.count})
            end
        end
    end
    if job.index>table.getn(job.maps) then
        self.pfGrid=job.grid;self.pfIndexRevision=job.revision;self.pfIndexed=job.count;self.pfBuilder=nil
    end
end
function M:SnapshotPFQuestRoutes()
    local dots={};self.pfRouteDots=dots
    local route=pfQuest and pfQuest.route
    local frame=WorldMapButton and WorldMapButton.routes
    if not route or not route.firstnode or not frame or not frame.GetRegions or pfQuest_config.routes=="0" then return end
    local first=route.coords and route.coords[1];local node=first and first[3] and first[3].node
    local zone
    for _,meta in pairs(node or {}) do zone=self:PFQuestZone(meta.zone);if zone then break end end
    if not zone then return end
    local w,h=WorldMapButton:GetWidth(),WorldMapButton:GetHeight()
    if w<=0 or h<=0 then return end
    -- Mirror pfQuest's actual chosen route, including its watched/manual target
    -- ordering. Never calculate a second quest plan or change the stock map.
    for i,texture in ipairs({frame:GetRegions()}) do
        if i>8192 or table.getn(dots)>=4096 then break end
        if texture.enable and texture:IsShown() and texture.GetTexture and texture:GetTexture()==pfQuestConfig.path.."\\img\\route" then
            local anchor,parent,relative,x,y=texture:GetPoint(1)
            if anchor=="CENTER" and parent==WorldMapButton and relative=="TOPLEFT" and finite(x) and finite(y) then
                local r,g,b,a=texture:GetVertexColor()
                table.insert(dots,{x=zone.x+x/w*zone.w,y=zone.y-y/h*zone.h,space=zone.space,
                    r=r,g=g,b=b,a=(a or 1)*texture:GetAlpha()})
            end
        end
    end
end
function M:UpdatePFQuest(elapsed)
    self:InstallPFQuest()
    if not zMapDB.pfQuest or not self:PFQuestAvailable() then
        self:HidePFQuest();if self.miniContext then self.miniContext:HidePFQuest() end;return
    end
    local large=self.frame and self.frame:IsShown()
    local mini=self.miniContext and self.miniContext.frame:IsShown()
    if not large and not mini then return end
    local now=GetTime and GetTime() or 0
    if self.pfIndexRevision~=self.pfRevision and now>=(self.pfQuietUntil or 0) then
        if self.pfBuildingRevision~=self.pfRevision then
            self.pfBuildingRevision=self.pfRevision;self:BuildPFQuestIndex(self.pfRevision)
        end
        if self.pfBuilder then self:StepPFQuestIndex() end
    end
    self.pfRouteElapsed=(self.pfRouteElapsed or 0)+elapsed
    if self.pfRouteElapsed>=.5 then self.pfRouteElapsed=0;self:SnapshotPFQuestRoutes() end
    if large then self:RenderPFQuest() end
    if mini then self.miniContext:RenderPFQuest() end
end
function M:MakePFQuestMarker()
    local ctx=self;local marker=pfMap:BuildNode(nil,self.layers.quests)
    marker.pfContext=ctx;marker:EnableMouseWheel(true)
    marker:SetScript("OnMouseDown",function()
        marker.pfDownX,marker.pfDownY=GetCursorPosition();marker.pfSkipClick=arg1~="LeftButton" or IsControlKeyDown()
        if not (IsShiftKeyDown and IsShiftKeyDown()) then invoke(ctx.viewport,ctx.viewport:GetScript("OnMouseDown")) end
    end)
    marker:SetScript("OnMouseUp",function()
        local x,y=GetCursorPosition()
        if marker.pfDownX and (x-marker.pfDownX)^2+(y-marker.pfDownY)^2>16 then marker.pfSkipClick=true end
        invoke(ctx.viewport,ctx.viewport:GetScript("OnMouseUp"))
    end)
    marker:SetScript("OnMouseWheel",function() invoke(ctx.viewport,ctx.viewport:GetScript("OnMouseWheel")) end)
    marker:SetScript("OnEnter",function() ctx.pfHovered=marker;invoke(marker,pfMap.NodeEnter) end)
    marker:SetScript("OnLeave",function()
        if ctx.pfHovered==marker then ctx.pfHovered=nil;invoke(marker,pfMap.NodeLeave) end
    end)
    marker:SetScript("OnHide",function()
        if ctx.pfHovered==marker then ctx.pfHovered=nil;invoke(marker,pfMap.NodeLeave) end
    end)
    return marker
end
function M:RenderPFQuest()
    local mini=self~=M
    local cfg=pfQuest_config
    local span=math.max(self.view.width,self.view.height)/self.view.scale
    if not zMapDB.pfQuest or not M:PFQuestAvailable() or not M.pfGrid or not self.layers or
        span>=18000 or mini and cfg.minimapnodes=="0" then self:HidePFQuest();return end
    local v=self.view
    self:SetLayer("quests",1);self:SetLayer("questRoutes",1)
    local left,top=self:ToWorld(10,10);local right,bottom=self:ToWorld(v.width-10,v.height-10)
    local ctrl=IsControlKeyDown() and MouseIsOver and MouseIsOver(self.viewport)
    local cache=rawget(self,"pfQuery")
    if not cache or cache.revision~=M.pfIndexRevision or cache.space~=v.space or cache.left~=left or cache.top~=top or
        cache.right~=right or cache.bottom~=bottom or cache.ctrl~=ctrl or cache.cluster~=cfg.showcluster or cache.spawn~=cfg.showspawn then
        cache={revision=M.pfIndexRevision,space=v.space,left=left,top=top,right=right,bottom=bottom,
            ctrl=ctrl,cluster=cfg.showcluster,spawn=cfg.showspawn,entries={}};self.pfQuery=cache
        for row=math.floor(top/STEP),math.floor(bottom/STEP) do
            for col=math.floor(left/STEP),math.floor(right/STEP) do
                for _,entry in ipairs(M.pfGrid[v.space..":"..col..":"..row] or {}) do
                    local meta=entry.meta
                    if entry.x>=left and entry.x<=right and entry.y>=top and entry.y<=bottom and
                        not (meta.cluster and (cfg.showcluster=="0" or ctrl)) and
                        not (cfg.showspawn=="0" and entry.addon=="PFQUEST" and not meta.texture) and not (mini and ctrl) then
                        table.insert(cache.entries,entry)
                    end
                end
            end
        end
        table.sort(cache.entries,function(a,b)
            if a.rank~=b.rank then return a.rank>b.rank end
            local da=(a.x-v.x)^2+(a.y-v.y)^2;local db=(b.x-v.x)^2+(b.y-v.y)^2
            if da~=db then return da<db end;return a.id<b.id
        end)
    end
    local candidates=cache.entries
    local markers=rawget(self,"pfMarkers") or {};self.pfMarkers=markers
    local used=math.min(table.getn(candidates),mini and 128 or 512)
    for i=1,used do
        local entry=candidates[i];local marker=markers[i]
        if not marker then marker=self:MakePFQuestMarker();markers[i]=marker end
        if marker.node~=entry.node or marker.pfRevision~=M.pfIndexRevision then
            if self.pfHovered==marker then self.pfHovered=nil;invoke(marker,pfMap.NodeLeave) end
            pfMap:UpdateNode(marker,entry.node,cfg.spawncolors=="1" and "spawn" or "title",mini and "minimap" or nil,1000)
            -- This viewport handles its own highlight/size. Do not add another
            -- atlas-sized pool to pfQuest's every-frame native animation loop.
            if pfMap.highlightdb then pfMap.highlightdb[marker]=nil end
            local click=marker:GetScript("OnClick")
            marker:SetScript("OnClick",function() if not marker.pfSkipClick then invoke(marker,click) end end)
            marker.pfRevision=M.pfIndexRevision
        end
        local level=self.layers.quests:GetFrameLevel()
        if marker:GetFrameLevel()~=level then marker:SetFrameLevel(level) end
        local highlight=pfMap.highlight and entry.node[pfMap.highlight]
        local size=(marker.cluster or marker.layer==4) and 18 or 14
        if highlight and marker.texture then size=size+4 end
        if marker:GetWidth()~=size then marker:SetWidth(size);marker:SetHeight(size) end
        local alpha=marker.texture and 1 or tonumber(mini and cfg.minimaptransp or cfg.worldmaptransp) or 1
        if pfMap.highlight and not highlight then alpha=tonumber(cfg.nodefade) or .3 end
        if marker:GetAlpha()~=alpha then marker:SetAlpha(alpha) end
        local target=pfQuest.route and pfQuest.route.IsTarget and pfQuest.route.IsTarget(marker)
        if target then if not marker.hl:IsShown() then marker.hl:Show() end elseif marker.hl:IsShown() then marker.hl:Hide() end
        self:PlaceMarker(marker,entry.x,entry.y,entry.space)
    end
    for i=used+1,table.getn(markers) do if markers[i]:IsShown() then markers[i]:Hide() end end
    self.pfShown=used
    self:RenderPFQuestRoutes(mini,cfg)
end
function M:RenderPFQuestRoutes(mini,cfg)
    local textures=rawget(self,"pfRouteTextures") or {};self.pfRouteTextures=textures
    local used=0
    if cfg.routes~="0" and (not mini or cfg.routeminimap~="0") then
        for _,dot in ipairs(M.pfRouteDots or {}) do
            local x,y=self:ToScreen(dot.x,dot.y)
            if dot.space==self.view.space and (not mini or dot.r>.9 and dot.g>.7) and
                x>=3 and y>=3 and x<=self.view.width-3 and y<=self.view.height-3 then
                used=used+1;if used>768 then used=768;break end
                local texture=textures[used]
                if not texture then
                    texture=self.layers.questRoutes:CreateTexture(nil,"ARTWORK");textures[used]=texture
                    texture:SetTexture(pfQuestConfig.path.."\\img\\route");texture:SetWidth(4);texture:SetHeight(4)
                end
                if texture.pfX~=x or texture.pfY~=y then
                    texture:ClearAllPoints();texture:SetPoint("CENTER",self.viewport,"TOPLEFT",x,-y);texture.pfX=x;texture.pfY=y
                end
                if texture.pfR~=dot.r or texture.pfG~=dot.g or texture.pfB~=dot.b or texture.pfA~=dot.a then
                    texture:SetVertexColor(dot.r,dot.g,dot.b,dot.a);texture.pfR=dot.r;texture.pfG=dot.g;texture.pfB=dot.b;texture.pfA=dot.a
                end
                if not texture:IsShown() then texture:Show() end
            end
        end
    end
    for i=used+1,table.getn(textures) do if textures[i]:IsShown() then textures[i]:Hide() end end
    self.pfRoutesShown=used
end
