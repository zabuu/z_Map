-- Current observations are colored; saved locations are unknown and grayscale.
local M=zMap
local DATA=zMapGatherData
M.gatherLabels={herbs="Herbs",ore="Ore",fish="Fishing",treasure="Treasure"}
local labels=M.gatherLabels
local colors={herbs={.4,1,.5},ore={1,.73,.3},fish={.3,.8,1},treasure={1,.88,.3}}
local function number(n) return type(n)=="number" and n==n and math.abs(n)<100000 end
local function entryID(n) return type(n)=="number" and n==n and n>0 and n<=4294967295 and n==math.floor(n) end
local function key(category,name) return category..":"..string.lower(name) end
function M:AddGatherDefinition(info)
    local id=key(info.category,info.name)
    if not self.gatherDefinitions[id] then
        self.gatherDefinitions[id]={key=id,name=info.name,category=info.category,skill=info.skill}
    end
    return id
end
function M:InitializeGather()
    if type(zMapDB.gatherFilters)~="table" then zMapDB.gatherFilters={} end
    if type(zMapDB.gatherCategories)~="table" then zMapDB.gatherCategories={} end
    if zMapDB.gatherEnabled==nil then zMapDB.gatherEnabled=true end
    if zMapDB.gatherShowLogged==nil then zMapDB.gatherShowLogged=true end
    zMapDB.gatherWorldIcons=zMapDB.gatherWorldIcons==true
    for category in pairs(labels) do
        if zMapDB.gatherCategories[category]==nil then zMapDB.gatherCategories[category]=category~="treasure" end
    end
    self.gatherDefinitions={};self.gatherEntries={};self.gatherNodes={};self.gatherByGUID={};self.gatherBuffer={}
    self.gatherMarkers={};self.gatherMarkerFree={};self.gatherEpoch=0;self.gatherElapsed=0
    for entry,info in pairs(DATA.entries) do self.gatherEntries[entry]=info;self:AddGatherDefinition(info) end
    self:InitializeGatherLog()
    self:InitializeGatherSync()
    self:InitializeGatherTimers()
    self.gatherStatus="Waiting for a live scan"
end
function M:HideGatherTooltip(marker)
    if self.hoveredGather and (not marker or self.hoveredGather==marker) then
        self.hoveredGather=nil;self.gatherTooltipMarker=nil;GameTooltip:Hide()
    end
end
function M:ClearGather(status)
    if not self.gatherNodes then return end
    self.gatherLiveAt=nil;self:ClearWorldGatherIcons()
    self:ResetGatherLogLive()
    self:ResetGatherTimingWatch()
    for i=table.getn(self.gatherNodes),1,-1 do self.gatherNodes[i]=nil end
    for guid in pairs(self.gatherByGUID) do self.gatherByGUID[guid]=nil end
    self.gatherStatus=status or "Waiting for a live scan"
    if not self.frame or not self.frame:IsShown() then self:HideGatherTooltip() end
    self:RenderGatherMarkers()
end
function M:GatherEnabled(info)
    return info and zMapDB.gatherCategories[info.category]~=false and zMapDB.gatherFilters[info.key]~=false
end
function M:SampleGather()
    if not self:IsGatherVisible() then return end
    if not zMapDB.gatherEnabled then self:ClearGather("Live gathering is off");return end
    if type(zAPI)~="function" then self:ClearGather("Live nodes require zAPI 2.4");return end
    if self.gatherProbedAPI~=zAPI then
        self.gatherProbedAPI=zAPI
        local ok,version=pcall(zAPI,"gatherBufferVersion");self.gatherCompatible=ok and version==1
    end
    if not self.gatherCompatible then self:ClearGather("Install zAPI 2.4 and restart WoW");return end
    local player=self.player
    if not player or not player.zone or self.mapChanged then self:ClearGather("Waiting for a map position");return end
    local ok,count,px,py,pz=pcall(zAPI,"gatherObjectsInto",self.gatherBuffer)
    if not ok or not number(count) or count<0 or count~=math.floor(count) or
        not number(px) or not number(py) or not number(pz) or table.getn(self.gatherBuffer)~=count*10 then self:ClearGather("Live scan unavailable");return end
    local origin=self.data.origins[player.zone.map]
    local ox,oy=0,0
    if origin then ox=origin[1];oy=origin[2] end
    -- Confirm the coordinate space against the native map sample. Loading,
    -- teleports and a stale native map must never pin nodes to another map.
    if math.abs(ox-py-player.x)>8 or math.abs(oy-px-player.y)>8 then
        self:ClearGather("Waiting for the current map position");return
    end
    self:ResetGatherLogLive();self.gatherPlayerZ=pz
    self.gatherEpoch=self.gatherEpoch+1
    local epoch=self.gatherEpoch;local used=0;local buffer=self.gatherBuffer
    for i=1,count do
        local n=(i-1)*10
        local guid,entry,x,y,z,display,kind=buffer[n+1],buffer[n+2],buffer[n+3],buffer[n+4],buffer[n+5],buffer[n+6],buffer[n+7]
        if type(guid)=="string" and entryID(entry) and number(x) and number(y) and number(z) and (kind==3 or kind==25) then
            local info=self.gatherEntries[entry]
            if not info then
                local category=kind==25 and "fish" or DATA.displays[display] or "treasure"
                local title=category=="herbs" and "Herb" or category=="ore" and "Ore" or category=="fish" and "Fishing pool" or "Container"
                info={name=title.." #"..entry,category=category};self.gatherEntries[entry]=info
            end
            local definition=self.gatherDefinitions[self:AddGatherDefinition(info)]
            local node=self.gatherByGUID[guid] or {}
            if node.epoch~=epoch then
                node.guid=guid;node.entry=entry;node.x=ox-y;node.y=oy-x;node.z=z;node.space=player.space
                node.worldX=x;node.worldY=y
                node.definition=definition;node.epoch=epoch
                node.distance=math.sqrt((x-px)^2+(y-py)^2+(z-pz)^2);node.height=z-pz
                node.location=nil;self:RememberGatherNode(node,player.zone.map,x,y,z)
                self.gatherByGUID[guid]=node;used=used+1;self.gatherNodes[used]=node
            end
        end
    end
    for i=used+1,table.getn(self.gatherNodes) do self.gatherNodes[i]=nil end
    for guid,node in pairs(self.gatherByGUID) do if node.epoch~=epoch then self.gatherByGUID[guid]=nil end end
    self.gatherLiveAt=GetTime and GetTime() or 0
    self:SampleGatherTimers(player.zone.map,px,py,pz)
    self.gatherStatus="Detected nearby: "..used;self:RenderGatherMarkers()
    if self.gatherPanel and self.gatherPanel:IsShown() then self:RefreshGatherPanel() end
end
function M:UpdateGather(elapsed)
    self:UpdateGatherVisuals(elapsed)
    self.gatherElapsed=(self.gatherElapsed or 0)+elapsed
    if self.gatherElapsed>=.5 then self.gatherElapsed=0;self:SampleGather() end
end
function M:ShowGatherTooltip(marker)
    local node=marker.node
    if not node then return end
    local info=node.definition;local color=colors[info.category]
    local rawDistance,rawHeight=node.distance,node.height
    if not marker.live then
        rawDistance=nil;rawHeight=nil
        if self.player and self.player.zone and self.player.zone.map==node.record.map then
            if self.gatherPlayerZ then rawHeight=node.z-self.gatherPlayerZ end
            rawDistance=math.sqrt((node.x-self.player.x)^2+(node.y-self.player.y)^2+(rawHeight or 0)^2)
        end
    end
    local distance=rawDistance and math.floor(rawDistance+.5)
    local height=rawHeight and math.abs(rawHeight)>8 and math.floor(rawHeight+.5) or 0
    local timing=not marker.live and node.record and node.record.respawnEstimate
    if self.gatherTooltipMarker==marker and self.gatherTooltipKey==info.key and self.gatherTooltipDistance==distance and self.gatherTooltipHeight==height and self.gatherTooltipLive==marker.live and self.gatherTooltipTiming==timing then return end
    self.gatherTooltipMarker=marker;self.gatherTooltipKey=info.key;self.gatherTooltipDistance=distance;self.gatherTooltipHeight=height
    self.gatherTooltipLive=marker.live
    self.gatherTooltipTiming=timing
    GameTooltip:SetOwner(marker,"ANCHOR_RIGHT")
    if marker.live then GameTooltip:SetText(info.name,unpack(color)) else GameTooltip:SetText(info.name,.7,.7,.7) end
    GameTooltip:AddLine(labels[info.category]..(marker.live and " | detected now" or " | logged location"),.7,.76,.82)
    if not marker.live then GameTooltip:AddLine("Availability unknown",.7,.7,.7) end
    if timing then GameTooltip:AddLine("Respawn timing: learned estimate",.7,.82,1) end
    if rawDistance then GameTooltip:AddLine(string.format("%.0f yards away",rawDistance),.7,.76,.82) end
    if rawHeight and math.abs(rawHeight)>8 then
        GameTooltip:AddLine(string.format("%.0f yards %s you",math.abs(rawHeight),rawHeight>0 and "above" or "below"),.7,.76,.82)
    end
    GameTooltip:Show()
end
function M:MakeGatherMarker()
    local marker=CreateFrame("Frame",nil,self.layers.gather)
    marker:SetWidth(17);marker:SetHeight(17);marker:EnableMouse(true);marker:EnableMouseWheel(true)
    marker.texture=marker:CreateTexture(nil,"ARTWORK");marker.texture:SetAllPoints(marker)
    self:BuildGatherVisuals(marker)
    marker:SetScript("OnEnter",function() self.hoveredGather=marker;self:ShowGatherTooltip(marker) end)
    marker:SetScript("OnLeave",function() self:HideGatherTooltip(marker) end)
    marker:SetScript("OnHide",function() self:HideGatherTooltip(marker) end)
    for _,event in ipairs({"OnMouseDown","OnMouseUp","OnMouseWheel"}) do
        local handler=event
        marker:SetScript(handler,function() local action=self.viewport:GetScript(handler);if action then action() end end)
    end
    return marker
end
function M:RenderGatherMarkers()
    if not self.layers or not self.layers.gather or not self.gatherNodes then return end
    local size,alpha,dot=self:GatherPresentation()
    if not self.frame:IsShown() or not size then
        for id,marker in pairs(self.gatherMarkers) do
            marker:Hide();marker.node=nil;self.gatherMarkers[id]=nil;table.insert(self.gatherMarkerFree,marker)
        end
        self.gatherShown=0;self.gatherLiveShown=0;self.gatherLoggedShown=0;self.gatherEligible=0
        self:UpdateGatherStatus(not size);return
    end
    self.gatherRenderEpoch=(self.gatherRenderEpoch or 0)+1
    local epoch=self.gatherRenderEpoch;local shown=0;local eligible=0;local liveShown=0;local loggedShown=0
    local function draw(node,live)
        if self:GatherEnabled(node.definition) and node.space==self.view.space and (not self.GatherNodeVisible or self:GatherNodeVisible(node)) then
            local sx,sy=self:ToScreen(node.x,node.y)
            if sx>=10 and sy>=10 and sx<=self.view.width-10 and sy<=self.view.height-10 then
                eligible=eligible+1
                if shown<(self.gatherMarkerLimit or 512) then
                    local id=node.location and node.location.id or node.id or "live:"..node.guid
                    local marker=self.gatherMarkers[id]
                    if not marker then marker=table.remove(self.gatherMarkerFree) or self:MakeGatherMarker();self.gatherMarkers[id]=marker end
                    marker.node=node;marker.live=live;marker.epoch=epoch
                    self:StyleGatherMarker(marker,node,live,size,alpha,dot)
                    if marker.liveLevel~=live then
                        marker:SetFrameLevel(self.layers.gather:GetFrameLevel()+(live and 1 or 0));marker.liveLevel=live
                    end
                    if marker.sx~=sx or marker.sy~=sy or not marker:IsShown() then
                        self:PlaceMarker(marker,node.x,node.y,node.space);marker.sx=sx;marker.sy=sy
                    end
                    shown=shown+1
                    if live then liveShown=liveShown+1 else loggedShown=loggedShown+1 end
                    if self.hoveredGather==marker then self:ShowGatherTooltip(marker) end
                end
            end
        end
        return shown<(self.gatherMarkerLimit or 512)
    end
    -- Native observations have priority over history when the display is full.
    for _,node in ipairs(self.gatherNodes) do
        local location=node.location
        if not location or location.renderOwner~=self or location.renderEpoch~=epoch then
            if location then location.renderOwner=self;location.renderEpoch=epoch end
            draw(node,true)
        end
    end
    if zMapDB.gatherShowLogged then self:VisitLoggedGatherLocations(function(node) return draw(node,false) end) end
    for id,marker in pairs(self.gatherMarkers) do
        if marker.epoch~=epoch then marker:Hide();marker.node=nil;self.gatherMarkers[id]=nil;table.insert(self.gatherMarkerFree,marker) end
    end
    self.gatherShown=shown;self.gatherEligible=eligible
    self.gatherLiveShown=liveShown;self.gatherLoggedShown=loggedShown
    self:UpdateGatherStatus()
end
function M:UpdateGatherStatus(zoomHidden)
    local shown=self.gatherShown or 0
    if self.gatherStatusLabel then
        local status=self.gatherStatus.." | shown: "..shown
        if not zMapDB.gatherEnabled and not zMapDB.gatherShowLogged then
            status="Nodes hidden: enable Live or Logged"
        elseif self.gatherEnabledTypes==0 then status="Nodes hidden by filters: select All" end
        if zoomHidden then status="Zoom in to see nodes" end
        if shown>=512 then status=status.." (limit 512)" end
        if self.gatherStatusText~=status then self.gatherStatusLabel:SetText(status);self.gatherStatusText=status end
    end
    if self.gatherCountLabel then
        local count=self.gatherFiltered and table.getn(self.gatherFiltered) or 0
        local text=count.." types | "..table.getn(self.gatherLogNodes).." logged | scroll"
        if self.gatherLogFull then text="Location log full (20,000); new nodes stay live only" end
        if self.gatherCountText~=text then self.gatherCountLabel:SetText(text);self.gatherCountText=text end
    end
end
