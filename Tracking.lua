-- Town, service, rare and resource icons from a compact static database
-- (TrackingData.lua, generated from pfQuest + pfQuest-turtle, MIT). Replaces
-- pfQuest's tracking menu so pfQuest itself no longer has to be loaded.
-- Only enabled categories are decoded, in time slices, into a 1024-yard grid.
local M=zMap
local DATA=zMapTrackingData or {categories={}}
local STEP=1024
local ROOT="Interface\\AddOns\\z_Map\\Media\\Tracking\\"
local floor,sqrt=math.floor,math.sqrt
local NONE={}
M.trackingOrder={"chests","herbs","mines","fish","rares","auctioneer","banker","battlemaster","flight",
    "innkeeper","mailbox","meetingstone","repair","spirithealer","stablemaster","vendor"}
M.trackingLabels={chests="Chests & Treasures",herbs="Herbs & Flowers",mines="Mines & Ores",fish="Fishing Pools",
    rares="Rare Mobs",auctioneer="Auctioneer",banker="Banker",battlemaster="Battlemaster",flight="Flight Master",
    innkeeper="Innkeeper",mailbox="Mailbox",meetingstone="Meeting Stones",repair="Repair",spirithealer="Spirit Healer",
    stablemaster="Stable Master",vendor="Vendor"}
local skill={herbs=true,mines=true,rares=true,chests=true}
local alias={flightmaster="flight",taxi="flight",flights="flight",raremobs="rares",treasure="chests",ore="mines",fishing="fish"}
local DIGIT={}
do local B="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    for i=1,64 do DIGIT[string.byte(B,i)]=i-1 end end
local function num(s,p,w)
    local n=0
    for i=p,p+w-1 do n=n*64+DIGIT[string.byte(s,i)] end
    return n
end
local function playerFaction()
    local f=UnitFactionGroup and UnitFactionGroup("player")
    return f=="Horde" and "H" or f=="Alliance" and "A" or ""
end
function M:InitializeTracking()
    if type(zMapDB.track)~="table" then
        zMapDB.track={}
        -- First run: carry over the categories pfQuest was tracking, if it is
        -- still loaded; otherwise start with the common town services.
        local imported
        if type(pfQuest_track)=="table" then
            for name in pairs(pfQuest_track) do
                local key=alias[name] or name
                if M.trackingLabels[key] then zMapDB.track[key]=true;imported=true end
            end
        end
        if not imported then
            for _,key in ipairs({"auctioneer","banker","flight","mailbox","spirithealer","stablemaster"}) do zMapDB.track[key]=true end
        end
    end
    zMapDB.trackMinimap=zMapDB.trackMinimap~=false
    zMapDB.trackHUD=zMapDB.trackHUD==true
    self:InvalidateTracking()
end
function M:InvalidateTracking() self.trackRevision=(self.trackRevision or 0)+1 end
function M:TrackingEnabled()
    for key,on in pairs(zMapDB.track or {}) do if on and DATA.categories[key] then return true end end
end
function M:SetTracking(key,state)
    key=alias[key] or key
    if not self.trackingLabels[key] then return end
    if state==nil then state=not zMapDB.track[key] end
    zMapDB.track[key]=state and true or nil
    self:InvalidateTracking();self:RefreshTrackingPanel()
    if self.InvalidatePFQuest then self:InvalidatePFQuest() end
end
-- Entries are decoded once per category and kept; they are a few hundred
-- small tables at most. Nodes stay encoded until their category is enabled.
local function entries(cat)
    local cache=M.trackEntries;if not cache then cache={};M.trackEntries=cache end
    local list=cache[cat];if list then return list end
    list={};cache[cat]=list
    local data=DATA.categories[cat];if not data then return list end
    local s=data.e.."\n";local start=1
    while true do
        local stop=string.find(s,"\n",start,true);if not stop then break end
        local _,_,name,info,fac,icon,respawn=string.find(string.sub(s,start,stop-1),"^([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)$")
        table.insert(list,{name=name or "?",info=info~="" and info or nil,fac=fac or "",
            icon=icon~="" and ROOT..icon or ROOT..cat,respawn=tonumber(respawn) or 0,cat=cat})
        start=stop+1
    end
    return list
end
function M:BuildTrackingIndex()
    local job={grid={},cats={},cat=1,pos=1,count=0,revision=self.trackRevision,faction=playerFaction()}
    for _,key in ipairs(self.trackingOrder) do
        if zMapDB.track[key] and DATA.categories[key] then table.insert(job.cats,key) end
    end
    self.trackBuilder=job
end
function M:StepTrackingIndex()
    local job=self.trackBuilder;local work=0
    while work<400 and job.cat<=table.getn(job.cats) do
        local cat=job.cats[job.cat];local data=DATA.categories[cat]
        local list=entries(cat);local s=data.n;local w=data.w;local size=6+w;local len=string.len(s)
        local filter=not skill[cat] and job.faction~=""
        while work<400 and job.pos<=len do
            local p=job.pos;job.pos=p+size;work=work+1
            local entry=list[num(s,p+6,w)]
            local zone=self.byID[num(s,p,2)]
            if entry and zone and (not filter or string.find(entry.fac,job.faction,1,true)) then
                local x,y=self:ZonePoint(zone,num(s,p+2,2)/1000,num(s,p+4,2)/1000)
                -- Numeric cell keys per space: queries never build key strings.
                local cells=job.grid[zone.space];if not cells then cells={};job.grid[zone.space]=cells end
                local key=floor(x/STEP)*65536+floor(y/STEP)
                local bucket=cells[key];if not bucket then bucket={};cells[key]=bucket end
                -- Flat triples keep the grid to one table per occupied cell.
                local n=table.getn(bucket);bucket[n+1]=x;bucket[n+2]=y;bucket[n+3]=entry
                job.count=job.count+1
            end
        end
        if job.pos>len then job.cat=job.cat+1;job.pos=1 end
    end
    if job.cat>table.getn(job.cats) then
        self.trackGrid=job.grid;self.trackIndexRevision=job.revision;self.trackIndexed=job.count
        self.trackFaction=job.faction;self.trackBuilder=nil;self.dirty=true
    end
end
function M:UpdateTracking()
    if not zMapDB.track then return end
    local faction=playerFaction()
    if self.trackFaction and self.trackFaction~=faction and not self.trackBuilder then self:InvalidateTracking() end
    if self.trackIndexRevision==self.trackRevision then return end
    local large=self.frame and self.frame:IsShown()
    local mini=zMapDB.trackMinimap and self.miniContext and self.miniContext.frame:IsShown()
    local hud=zMapDB.trackHUD and self.hudContext and self.hudContext.frame:IsShown()
    if not large and not mini and not hud then return end
    if not self.trackBuilder or self.trackBuilder.revision~=self.trackRevision then self:BuildTrackingIndex() end
    self:StepTrackingIndex()
end
function M:HideTracking()
    for _,marker in ipairs(rawget(self,"trackMarkers") or {}) do if marker:IsShown() then marker:Hide() end end
    self.trackShown=0
end
local function invoke(frame,handler)
    if not handler then return end
    local previous=this;this=frame
    local ok,err=pcall(handler);this=previous
    if not ok then error(err) end
end
local factionText={A="Alliance",H="Horde",AH="Both factions"}
function M:ShowTrackingTooltip(marker)
    local entry=marker.trackEntry;if not entry then return end
    GameTooltip:SetOwner(marker,"ANCHOR_LEFT")
    GameTooltip:SetText(entry.name,1,.82,0)
    GameTooltip:AddLine(M.trackingLabels[entry.cat],.7,.76,.82)
    if entry.info then
        GameTooltip:AddLine((skill[entry.cat] and entry.cat~="rares" and "Skill: " or "Level: ")..entry.info,.9,.94,.98)
    end
    if factionText[entry.fac] and entry.fac~="AH" then GameTooltip:AddLine(factionText[entry.fac],.7,.76,.82) end
    if entry.respawn>0 and SecondsToTime then GameTooltip:AddLine("Respawn: "..SecondsToTime(entry.respawn),.7,.76,.82) end
    GameTooltip:Show()
end
function M:MakeTrackingMarker()
    local ctx=self
    local marker=CreateFrame("Button",nil,self.layers.quests)
    marker:SetWidth(16);marker:SetHeight(16)
    marker.texture=marker:CreateTexture(nil,"ARTWORK");marker.texture:SetAllPoints(marker)
    if self.hud then marker:EnableMouse(false);marker.hudBaseAlpha=.85;return marker end
    marker:EnableMouse(true);marker:EnableMouseWheel(true)
    -- Clicks, drags and the wheel belong to the map underneath.
    marker:SetScript("OnMouseDown",function() invoke(ctx.viewport,ctx.viewport:GetScript("OnMouseDown")) end)
    marker:SetScript("OnMouseUp",function() invoke(ctx.viewport,ctx.viewport:GetScript("OnMouseUp")) end)
    marker:SetScript("OnMouseWheel",function() invoke(ctx.viewport,ctx.viewport:GetScript("OnMouseWheel")) end)
    marker:SetScript("OnEnter",function() ctx.trackHovered=marker;M:ShowTrackingTooltip(marker) end)
    marker:SetScript("OnLeave",function() if ctx.trackHovered==marker then ctx.trackHovered=nil;GameTooltip:Hide() end end)
    marker:SetScript("OnHide",function() if ctx.trackHovered==marker then ctx.trackHovered=nil;GameTooltip:Hide() end end)
    return marker
end
function M:RenderTracking()
    local mini=self~=M and not self.hud
    local v=self.view
    if not M.trackGrid or not self.layers or not self.layers.quests or mini and not zMapDB.trackMinimap or
        math.max(v.width,v.height)/v.scale>=18000 then self:HideTracking();return end
    local left,top=self:ToWorld(10,10);local right,bottom=self:ToWorld(v.width-10,v.height-10)
    if self.hud then
        local radius=sqrt(v.width*v.width+v.height*v.height)/(v.scale*2)
        left=v.x-radius;right=v.x+radius;top=v.y-radius;bottom=v.y+radius
    end
    if left>right then left,right=right,left end
    if top>bottom then top,bottom=bottom,top end
    self:SetLayer("quests",1)
    -- Reused scratch arrays: the minimap re-queries every 0.1 s while moving,
    -- so this path must not allocate per call.
    local q=rawget(self,"trackQuery")
    if not q then
        q={x={},y={},e={},d={},order={},n=0};self.trackQuery=q
        q.less=function(a,b) local da,db=q.d[a],q.d[b];if da~=db then return da<db end;return a<b end
    end
    if q.revision~=M.trackIndexRevision or q.space~=v.space or q.left~=left or q.top~=top or q.right~=right or q.bottom~=bottom then
        q.revision=M.trackIndexRevision;q.space=v.space;q.left=left;q.top=top;q.right=right;q.bottom=bottom
        local n=0;local qx,qy,qe=q.x,q.y,q.e;local cells=M.trackGrid[v.space] or NONE
        for row=floor(top/STEP),floor(bottom/STEP) do
            for col=floor(left/STEP),floor(right/STEP) do
                local bucket=cells[col*65536+row]
                if bucket then
                    for i=1,table.getn(bucket),3 do
                        local x,y=bucket[i],bucket[i+1]
                        if x>=left and x<=right and y>=top and y<=bottom then
                            n=n+1;qx[n]=x;qy[n]=y;qe[n]=bucket[i+2]
                        end
                    end
                end
            end
        end
        q.n=n;q.sorted=nil
    end
    local limit=mini and 128 or self.hud and 96 or 512
    local used=math.min(q.n,limit)
    -- Only rank by distance when there are more candidates than markers.
    if q.n>limit and (q.sorted~=q.revision or q.cx~=v.x or q.cy~=v.y) then
        local order,d=q.order,q.d
        for i=1,q.n do order[i]=i;d[i]=(q.x[i]-v.x)^2+(q.y[i]-v.y)^2 end
        for i=q.n+1,table.getn(order) do order[i]=nil end
        table.sort(order,q.less);q.sorted=q.revision;q.cx=v.x;q.cy=v.y
    end
    local markers=rawget(self,"trackMarkers");if not markers then markers={};self.trackMarkers=markers end
    local size=mini and 14 or self.hud and 14 or 16
    local level=self.layers.quests:GetFrameLevel()
    for i=1,used do
        local k=q.n>limit and q.order[i] or i
        local entry=q.e[k];local marker=markers[i]
        if not marker then marker=self:MakeTrackingMarker();markers[i]=marker end
        if marker.trackEntry~=entry then
            marker.trackEntry=entry
            if marker.trackIcon~=entry.icon then marker.texture:SetTexture(entry.icon);marker.trackIcon=entry.icon end
            if self.trackHovered==marker then M:ShowTrackingTooltip(marker) end
        end
        if marker:GetFrameLevel()~=level then marker:SetFrameLevel(level) end
        if marker:GetWidth()~=size then marker:SetWidth(size);marker:SetHeight(size) end
        self:PlaceMarker(marker,q.x[k],q.y[k],v.space)
    end
    for i=used+1,table.getn(markers) do if markers[i]:IsShown() then markers[i]:Hide() end end
    self.trackShown=used
end
function M:TrackingStatus()
    local on={}
    for _,key in ipairs(self.trackingOrder) do if zMapDB.track[key] then table.insert(on,key) end end
    self:Print("Tracking: "..(table.getn(on)>0 and table.concat(on,", ") or "nothing").." | "..(self.trackIndexed or 0)..
        " icons indexed | "..(self.trackShown or 0).." on the map | minimap "..(zMapDB.trackMinimap and "on" or "off")..
        " | HUD "..(zMapDB.trackHUD and "on" or "off")..".")
end
function M:TrackingCommand(arg)
    if arg=="" then self:ToggleTrackingPanel();return end
    if arg=="status" then self:TrackingStatus();return end
    if arg=="minimap" then zMapDB.trackMinimap=not zMapDB.trackMinimap;self:RefreshTrackingPanel();self:TrackingStatus();return end
    if arg=="hud" then zMapDB.trackHUD=not zMapDB.trackHUD;self:RefreshTrackingPanel();self:TrackingStatus();return end
    if arg=="none" then zMapDB.track={};self:InvalidateTracking();self:RefreshTrackingPanel();self:TrackingStatus();return end
    local key=alias[arg] or arg
    if not self.trackingLabels[key] then
        self:Print("Unknown category. Use one of: "..table.concat(self.trackingOrder,", ")..", or status, minimap, hud, none.");return
    end
    self:SetTracking(key);self:TrackingStatus()
end
function M:BuildTrackingUI(anchor,button,text,surface)
    local panel=CreateFrame("Frame",nil,self.frame);self.trackPanel=panel
    local rows=table.getn(self.trackingOrder)
    panel:SetWidth(232);panel:SetHeight(84+rows*22);panel:SetPoint("TOPRIGHT",anchor,"BOTTOMRIGHT",0,-5)
    panel:SetFrameLevel(self.frame:GetFrameLevel()+40);surface(panel,.035,.045,.06);panel:EnableMouse(true)
    text(panel,"Track on map",12,-12,150,true)
    local close=button(panel,"X",24,function() panel:Hide() end);close:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-8,-8)
    self.trackMiniOption=button(panel,"",100,function()
        zMapDB.trackMinimap=not zMapDB.trackMinimap;self:RefreshTrackingPanel()
    end);self.trackMiniOption:SetPoint("TOPLEFT",panel,"TOPLEFT",12,-40)
    self.trackHUDOption=button(panel,"",100,function()
        zMapDB.trackHUD=not zMapDB.trackHUD;self:RefreshTrackingPanel()
    end);self.trackHUDOption:SetPoint("LEFT",self.trackMiniOption,"RIGHT",8,0)
    self.trackRows={}
    for i,key in ipairs(self.trackingOrder) do
        local name=key
        local row=button(panel,"",208,function() self:SetTracking(name) end)
        row:SetHeight(20);row:SetPoint("TOPLEFT",panel,"TOPLEFT",12,-72-(i-1)*22)
        local icon=row:CreateTexture(nil,"OVERLAY");icon:SetWidth(16);icon:SetHeight(16)
        icon:SetPoint("LEFT",row,"LEFT",4,0);icon:SetTexture(ROOT..key);row.icon=icon
        if row.label then row.label:ClearAllPoints();row.label:SetPoint("LEFT",icon,"RIGHT",6,0) end
        self.trackRows[key]=row
    end
    panel:Hide();self:RefreshTrackingPanel()
end
function M:RefreshTrackingPanel()
    if not self.trackPanel then return end
    self.trackMiniOption.label:SetText("Minimap: "..(zMapDB.trackMinimap and "on" or "off"))
    self.trackHUDOption.label:SetText("HUD: "..(zMapDB.trackHUD and "on" or "off"))
    for key,row in pairs(self.trackRows) do
        local on=zMapDB.track[key]
        row.label:SetText((on and "|cff59d9c5" or "|cff777777")..self.trackingLabels[key].."|r")
        row.icon:SetAlpha(on and 1 or .35)
    end
end
function M:ToggleTrackingPanel()
    if not self.frame then self:BuildUI() end
    if not self.frame:IsShown() then self.frame:Show() end
    if self.trackPanel:IsShown() then self.trackPanel:Hide() else
        if self.gatherPanel then self.gatherPanel:Hide() end
        if self.transportPanel then self.transportPanel:Hide() end
        if self.settingsPanel then self.settingsPanel:Hide() end
        self.searchPanel:Hide();self:RefreshTrackingPanel();self.trackPanel:Show()
    end
end
