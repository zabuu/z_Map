local M=zMap
local WHITE="Interface\\Buttons\\WHITE8X8"
local min,max,abs=math.min,math.max,math.abs
BINDING_HEADER_ZSUITE=BINDING_HEADER_ZSUITE or "zSuite"
BINDING_NAME_ZMAP_TOGGLE="Toggle zMap"
local defaults={replace=true,style="hybrid",interiors="auto",floorArt=true,follow=false,reopen="last",width=1000,height=690,pins={}}
local classColors={
    WARRIOR={r=.78,g=.61,b=.43},MAGE={r=.41,g=.8,b=.94},ROGUE={r=1,g=.96,b=.41},
    DRUID={r=1,g=.49,b=.04},HUNTER={r=.67,g=.83,b=.45},SHAMAN={r=0,g=.44,b=.87},
    PRIEST={r=1,g=1,b=1},WARLOCK={r=.58,g=.51,b=.79},PALADIN={r=.96,g=.55,b=.73}
}
function M:ClassColor(class)
    local color=(RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]) or classColors[class]
    if color then return color.r,color.g,color.b end
    return .4,.7,1
end
function M:HideGroupTooltip(marker)
    if self.hoveredGroupMarker and (not marker or self.hoveredGroupMarker==marker) then
        self.hoveredGroupMarker=nil;self.groupTooltipMarker=nil;GameTooltip:Hide()
    end
end
function M:ShowGroupTooltip(marker)
    local member=marker.member
    if not member then return end
    local r,g,b=self:ClassColor(member.class)
    if self.groupTooltipMarker==marker and self.groupTooltipName==member.name and
        self.groupTooltipClass==member.className and self.groupTooltipR==r and
        self.groupTooltipG==g and self.groupTooltipB==b then return end
    self.groupTooltipMarker=marker;self.groupTooltipName=member.name;self.groupTooltipClass=member.className
    self.groupTooltipR=r;self.groupTooltipG=g;self.groupTooltipB=b
    GameTooltip:SetOwner(marker,"ANCHOR_RIGHT")
    GameTooltip:SetText(member.name,r,g,b)
    if member.className then GameTooltip:AddLine(member.className,.7,.76,.82) end
    GameTooltip:Show()
end

local function surface(frame,r,g,b)
    frame:SetBackdrop({bgFile=WHITE,edgeFile=WHITE,edgeSize=1})
    frame:SetBackdropColor(r or .035,g or .045,b or .06,1)
    frame:SetBackdropBorderColor(.22,.28,.35,1)
end
local function text(parent,value,x,y,width,large)
    local label=parent:CreateFontString(nil,"OVERLAY",large and "GameFontNormalLarge" or "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT",parent,"TOPLEFT",x,y); label:SetWidth(width or 500)
    label:SetJustifyH("LEFT"); label:SetTextColor(.9,.94,.98); label:SetText(value)
    return label
end
local function button(parent,label,width,action)
    local b=CreateFrame("Button",nil,parent)
    b:SetWidth(width); b:SetHeight(24); surface(b,.09,.12,.16)
    local fs=b:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    fs:SetPoint("CENTER",b,"CENTER",0,0); fs:SetTextColor(.9,.94,.98); b.label=fs; fs:SetText(label)
    b:SetHighlightTexture(WHITE)
    b:GetHighlightTexture():SetVertexColor(.25,.7,.65,.16)
    b:SetScript("OnClick",action)
    return b
end
function M:MakeMarker(r,g,b,size)
    local marker=CreateFrame("Frame",nil,self.layers.markers)
    marker:SetWidth(size or 16); marker:SetHeight(size or 16)
    local texture=marker:CreateTexture(nil,"ARTWORK")
    texture:SetAllPoints(marker); texture:SetTexture("Interface\\Minimap\\POIIcons")
    texture:SetTexCoord(0,.125,0,.125); texture:SetVertexColor(r,g,b)
    -- A solid diamond with a dark outline is readable on parchment and terrain.
    texture:SetTexture("Interface\\Buttons\\UI-RadioButton")
    texture:SetTexCoord(.25,.5,0,1); texture:SetVertexColor(r,g,b)
    marker.texture=texture
    marker:Hide()
    return marker
end
function M:MakeGroupMarker()
    local marker=CreateFrame("Frame",nil,self.layers.markers)
    marker:SetWidth(14);marker:SetHeight(14)
    local texture=marker:CreateTexture(nil,"ARTWORK")
    texture:SetAllPoints(marker)
    texture:SetTexture("Interface\\AddOns\\z_Map\\Media\\GroupCircle");marker.texture=texture
    marker:EnableMouse(true);marker:EnableMouseWheel(true)
    marker:SetScript("OnEnter",function()
        if marker.member then self.hoveredGroupMarker=marker;self:ShowGroupTooltip(marker) end
    end)
    marker:SetScript("OnLeave",function() self:HideGroupTooltip(marker) end)
    marker:SetScript("OnHide",function() self:HideGroupTooltip(marker) end)
    -- A marker's hover target must not block the map's normal navigation.
    for _,event in ipairs({"OnMouseDown","OnMouseUp","OnMouseWheel"}) do
        local handler=event
        marker:SetScript(handler,function()
            local action=self.viewport:GetScript(handler)
            if action then action() end
        end)
    end
    marker:Hide()
    return marker
end
function M:Cursor()
    local x,y=GetCursorPosition()
    local scale=self.viewport:GetEffectiveScale()
    return x/scale-self.viewport:GetLeft(),self.viewport:GetTop()-y/scale
end
function M:SaveView()
    if not zMapDB then return end
    local v=self.view
    zMapDB.view={x=v.x,y=v.y,scale=v.scale,space=v.space,focus=self.focus and self.focus.id}
end
function M:SaveWindow()
    if self.fullscreen then return end
    zMapDB.width=self.frame:GetWidth(); zMapDB.height=self.frame:GetHeight()
    local x,y=self.frame:GetCenter()
    if x and y then zMapDB.cx=x; zMapDB.cy=y end
end
function M:Resize()
    if self.resizing then return end
    self.resizing=true
    if self.frame:GetWidth()<730 then self.frame:SetWidth(730) end
    if self.frame:GetHeight()<440 then self.frame:SetHeight(440) end
    self.resizing=false
    local v=self.view
    v.width=max(100,self.frame:GetWidth()-20)
    v.height=max(100,self.frame:GetHeight()-110)
    self.viewport:SetWidth(v.width); self.viewport:SetHeight(v.height)
    self:LayoutGatherPanel()
    self:LayoutTransportPanel()
    self:Constrain(); self.dirty=true
end
function M:FindMe(keepZoom)
    self:SamplePlayer(true)
    local p=self.player
    if not p then self:Print("The client has no map position here yet. Use Search to browse an area."); return end
    if keepZoom then self.focus=p.zone;self.view.space=p.space;self.animation=nil
    elseif p.zone then self:FocusZone(p.zone) else self.view.space=p.space end
    self.view.x=p.x; self.view.y=p.y
    if not keepZoom then self.view.scale=max(self.view.scale,.25) end
    self.animation=nil; self.dirty=true
end
local function positionNumber(value)
    return type(value)=="number" and value==value and abs(value)<10000000
end
function M:RefreshDistantGroupPositions(pending,now)
    if table.getn(pending)==0 or now<(self.groupProbeAt or 0) or self.groupMapProbe or
        WorldMapFrame and WorldMapFrame:IsShown() or type(SetMapZoom)~="function" or
        type(GetCurrentMapContinent)~="function" or type(GetCurrentMapZone)~="function" then return end
    self.groupProbeAt=now+2
    local continent,zone=GetCurrentMapContinent(),GetCurrentMapZone()
    local priorThis,priorEvent=this,event
    local a1,a2,a3,a4,a5,a6,a7,a8,a9=arg1,arg2,arg3,arg4,arg5,arg6,arg7,arg8,arg9
    local sampled={};self.groupMapProbe=true
    local ok=pcall(function()
        -- The native world projection matches the atlas's WorldMapContinent
        -- layout. Read all unavailable groupmates in one batched world view.
        SetMapZoom(0)
        for _,member in ipairs(pending) do
            local x,y=GetPlayerMapPosition(member.unit)
            if positionNumber(x) and positionNumber(y) and (x~=0 or y~=0) and x>=0 and x<=1 and y>=0 and y<=1 then
                local bounds=self.data.bounds
                sampled[member.name]={x=bounds[1]+x*(bounds[3]-bounds[1]),y=bounds[2]+y*(bounds[4]-bounds[2]),at=now}
            end
        end
    end)
    local restored=pcall(function()
        if continent and continent>0 then SetMapZoom(continent,zone or 0) else SetMapToCurrentZone() end
    end)
    -- Even a rejected position query must leave other addons on the old map.
    if not restored then restored=pcall(SetMapToCurrentZone) end
    self.groupMapProbe=nil;this=priorThis;event=priorEvent
    arg1,arg2,arg3,arg4,arg5,arg6,arg7,arg8,arg9=a1,a2,a3,a4,a5,a6,a7,a8,a9
    if ok and restored then
        for _,member in ipairs(pending) do self.groupWorldPositions[member.name]=sampled[member.name] end
    end
end
function M:SampleGroup(selected)
    self.group=self.group or {};self.groupWorldPositions=self.groupWorldPositions or {}
    local members,pending,keep={},{},{}
    local now=GetTime and GetTime() or 0
    if zMapDB.group~=false then
        local count=GetNumRaidMembers and GetNumRaidMembers() or 0
        local prefix="raid"
        if count==0 then prefix="party";count=GetNumPartyMembers and GetNumPartyMembers() or 0 end
        for i=1,min(40,count) do
            local unit=prefix..i
            if not UnitIsUnit(unit,"player") and (not UnitIsConnected or UnitIsConnected(unit)) then
                local member={unit=unit,name=UnitName(unit) or unit};keep[member.name]=true
                local x,y=GetPlayerMapPosition(unit)
                if selected and positionNumber(x) and positionNumber(y) and (x~=0 or y~=0) then
                    member.x,member.y=self:ZonePoint(selected,x,y);member.space=selected.space
                else table.insert(pending,member) end
                table.insert(members,member)
            end
        end
    end
    for name in pairs(self.groupWorldPositions) do if not keep[name] then self.groupWorldPositions[name]=nil end end
    self:RefreshDistantGroupPositions(pending,now)
    local used=0
    for _,member in ipairs(members) do
        if not member.x then
            local point=self.groupWorldPositions[member.name]
            if point and now-point.at<=5 then member.x=point.x;member.y=point.y;member.space="world" end
        end
        if member.x then
            used=used+1;local result=self.group[used] or {}
            result.x=member.x;result.y=member.y;result.space=member.space
            result.unit=member.unit;result.name=member.name
            result.className,result.class=UnitClass(member.unit);self.group[used]=result
        end
    end
    for i=used+1,table.getn(self.group) do self.group[i]=nil end
end
function M:SamplePlayer(resetMap)
    -- GetPlayerMapPosition is native 1.12 and works without ClassicAPI/SuperWoW.
    -- Keep the hidden stock map on the player's area, so its normalization stays
    -- valid while zMap independently pans across the entire atlas.
    local file=GetMapInfo()
    local selected=file and self.byFile[string.lower(file)]
    if resetMap or self.mapChanged or not selected or selected~=self.sampleZone then
        SetMapToCurrentZone()
        self.mapChanged=false
        file=GetMapInfo(); selected=file and self.byFile[string.lower(file)]
    end
    self.sampleZone=selected
    local x,y=GetPlayerMapPosition("player")
    self:SampleGroup(selected)
    if not selected or not x or not y or (x==0 and y==0) then
        self.player=nil; self:RenderMarkers(); return
    end
    local wx,wy=self:ZonePoint(selected,x,y)
    self.player=self.player or {}
    self.player.x=wx; self.player.y=wy; self.player.space=selected.space; self.player.zone=selected
    if zMapDB.follow and not self.drag and not self.animation then
        if selected.space~="world" then self.focus=selected end
        self.view.space=selected.space; self.view.x=wx; self.view.y=wy; self.dirty=true
    end
    self:RenderMarkers()
end
function M:CycleStyle()
    local nextStyle={hybrid="painted",painted="terrain",terrain="hybrid"}
    zMapDB.style=nextStyle[zMapDB.style] or "hybrid"
    self.styleButton.label:SetText("Look: "..zMapDB.style)
    self.dirty=true
end
function M:Maximize()
    self.fullscreen=not self.fullscreen
    self.frame:ClearAllPoints()
    if self.fullscreen then
        self.frame:SetPoint("CENTER",UIParent,"CENTER",0,0)
        self.frame:SetWidth(UIParent:GetWidth()-12); self.frame:SetHeight(UIParent:GetHeight()-12)
    else
        self.frame:SetWidth(zMapDB.width); self.frame:SetHeight(zMapDB.height)
        self.frame:SetPoint("CENTER",UIParent,"BOTTOMLEFT",zMapDB.cx or UIParent:GetWidth()/2,zMapDB.cy or UIParent:GetHeight()/2)
    end
    self:Resize()
end
function M:UpdateSearch()
    local query=self.search:GetText()
    local results=self:Search(query)
    self.searchResults=results
    for i,row in ipairs(self.searchRows) do
        local z=results[i]
        row.zone=z
        if z then
            local suffix=z.space~="world" and "  |cff8c9cab(instance)|r" or ""
            row.label:SetText(z.name..suffix); row:Show()
        else row:Hide() end
    end
    if query~="" then
        self.searchPanel:SetHeight(max(1,min(8,table.getn(results)))*26+8)
        self.searchPanel:Show()
        self.noResults:SetText(table.getn(results)==0 and "No matching maps" or "")
    else self.searchPanel:Hide() end
end
function M:BuildUI()
    if self.frame then return end
    local f=CreateFrame("Frame","zMapFrame",UIParent)
    self.frame=f
    f:SetWidth(zMapDB.width); f:SetHeight(zMapDB.height)
    f:SetPoint("CENTER",UIParent,"BOTTOMLEFT",zMapDB.cx or UIParent:GetWidth()/2,zMapDB.cy or UIParent:GetHeight()/2)
    f:SetFrameStrata("HIGH"); f:SetMovable(true); f:SetResizable(true)
    if f.SetMinResize then f:SetMinResize(730,440) end
    f:EnableMouse(true)
    if f.SetClampedToScreen then f:SetClampedToScreen(true) end
    surface(f)
    text(f,"|cff59d9c5z|rMap",14,-13,70,true)
    self.settingsButton=button(f,"Settings",75,function() self:ToggleSettingsPanel() end)
    self.settingsButton:SetPoint("TOPLEFT",f,"TOPLEFT",82,-8)
    self.areaLabel=text(f,"OctoWoW",175,-16,210)
    local close=button(f,"X",26,function() f:Hide() end)
    close:SetPoint("TOPRIGHT",f,"TOPRIGHT",-10,-9)
    local full=button(f,"[ ]",30,function() self:Maximize() end)
    full:SetPoint("RIGHT",close,"LEFT",-5,0)
    self.layerButton=button(f,"Layer: auto",122,function() self:CycleLayer() end)
    self.layerButton:SetPoint("RIGHT",full,"LEFT",-6,0)
    self.transportButton=button(f,"Transit",70,function() self:ToggleTransportPanel() end)
    self.transportButton:SetPoint("RIGHT",self.layerButton,"LEFT",-6,0)
    self.layerButton:SetScript("OnEnter",function()
        GameTooltip:SetOwner(self.layerButton,"ANCHOR_BOTTOM")
        GameTooltip:SetText(self.focus and self.view.space~="world" and self.focus.name or "Map layers",.9,.94,.98)
        local list=self.floors[self.view.space] or {}
        if table.getn(list)>1 then GameTooltip:AddLine("Click to cycle the available floors.",.7,.76,.82)
        elseif self.view.space=="world" then GameTooltip:AddLine("Click to cycle auto, surface and underground.",.7,.76,.82)
        else GameTooltip:AddLine("Click to switch between the interior plan and geometry.",.7,.76,.82) end
        GameTooltip:Show()
    end)
    self.layerButton:SetScript("OnLeave",function() GameTooltip:Hide() end)
    local title=CreateFrame("Frame",nil,f)
    title:SetPoint("TOPLEFT",f,"TOPLEFT",5,-3); title:SetPoint("BOTTOMRIGHT",self.transportButton,"BOTTOMLEFT",-4,-4)
    title:EnableMouse(true); title:RegisterForDrag("LeftButton")
    title:SetScript("OnDragStart",function() if not self.fullscreen then f:StartMoving() end end)
    title:SetScript("OnDragStop",function() f:StopMovingOrSizing(); self:SaveWindow() end)
    local top=CreateFrame("Frame",nil,f)
    top:SetPoint("TOPLEFT",f,"TOPLEFT",10,-42); top:SetWidth(710); top:SetHeight(26)
    local world=button(top,"World",45,function() zMapDB.follow=false; self:World() end)
    world:SetPoint("LEFT",top,"LEFT",0,0)
    local kal=button(top,"Kalimdor",65,function() zMapDB.follow=false; self:Continent(1) end)
    kal:SetPoint("LEFT",world,"RIGHT",5,0)
    local ek=button(top,"Eastern K.",76,function() zMapDB.follow=false; self:Continent(0) end)
    ek:SetPoint("LEFT",kal,"RIGHT",5,0)
    local find=button(top,"Find me",65,function() self:FindMe() end)
    find:SetPoint("LEFT",ek,"RIGHT",5,0)
    self.followButton=button(top,"Follow",50,function()
        zMapDB.follow=not zMapDB.follow
        if zMapDB.follow then self:FindMe(true) end
    end)
    self.followButton:SetPoint("LEFT",find,"RIGHT",5,0)
    self.styleButton=button(top,"Look: "..zMapDB.style,100,function() self:CycleStyle() end)
    self.styleButton:SetPoint("LEFT",self.followButton,"RIGHT",5,0)
    self.gatherButton=button(top,"Nodes",75,function() self:ToggleGatherPanel() end)
    self.gatherButton:SetPoint("LEFT",self.styleButton,"RIGHT",7,0)
    local search=CreateFrame("EditBox","zMapSearch",top)
    self.search=search
    search:SetWidth(150); search:SetHeight(24); search:SetPoint("LEFT",self.gatherButton,"RIGHT",7,0)
    search:SetFontObject(GameFontHighlightSmall); search:SetTextInsets(8,8,0,0); search:SetAutoFocus(false)
    surface(search,.055,.07,.09)
    self.searchHint=text(search,"Search maps...",8,-7,134)
    self.searchHint:SetTextColor(.5,.59,.66)
    search:SetScript("OnTextChanged",function()
        if search:GetText()=="" then self.searchHint:Show() else self.searchHint:Hide() end
        self:UpdateSearch()
    end)
    search:SetScript("OnEscapePressed",function() search:ClearFocus(); self.searchPanel:Hide() end)
    search:SetScript("OnEnterPressed",function()
        if self.searchResults and self.searchResults[1] then
            zMapDB.follow=false; self:FocusZone(self.searchResults[1]); search:ClearFocus(); self.searchPanel:Hide()
        end
    end)
    local panel=CreateFrame("Frame",nil,f)
    self.searchPanel=panel; panel:SetWidth(330); panel:SetHeight(220)
    panel:SetPoint("TOPRIGHT",search,"BOTTOMRIGHT",0,-3); panel:SetFrameLevel(f:GetFrameLevel()+20)
    panel:EnableMouse(true); surface(panel); panel:Hide()
    self.noResults=text(panel,"",8,-8,310)
    self.searchRows={}
    for i=1,8 do
        local row=button(panel,"",322,function() end)
        row:SetPoint("TOPLEFT",panel,"TOPLEFT",4,-4-(i-1)*26)
        row:SetScript("OnClick",function()
            if row.zone then zMapDB.follow=false; self:FocusZone(row.zone); search:ClearFocus(); panel:Hide() end
        end)
        self.searchRows[i]=row
    end
    local viewport=CreateFrame("Frame","zMapViewport",f)
    self.viewport=viewport
    viewport:SetPoint("TOPLEFT",f,"TOPLEFT",10,-77)
    surface(viewport,.075,.12,.15); viewport:EnableMouse(true); viewport:EnableMouseWheel(true)
    self.layers={}
    local layers={"overview","art","artFine","terrain","fine","detail","caves","interior","transitRoutes","gather","transit","questRoutes","quests","markers"}
    for i,name in ipairs(layers) do
        local layer=CreateFrame("Frame",nil,viewport)
        layer:SetAllPoints(viewport); layer:SetFrameLevel(viewport:GetFrameLevel()+i)
        self.layers[name]=layer
    end
    self.playerMarker=self:MakeMarker(.35,1,.87,24)
    self.playerMarker.texture:SetTexture("Interface\\Minimap\\MinimapArrow")
    self.playerMarker.texture:SetTexCoord(0,1,0,1);self.playerMarker.texture:SetVertexColor(1,1,1)
    self:BuildGatherUI(self.gatherButton,button,text,surface)
    self:BuildTransportUI(self.transportButton,button,text,surface)
    self:BuildSettingsUI(button,text,surface)
    self.groupMarkers={}; self.pinMarkers={}
    for i=1,40 do self.groupMarkers[i]=self:MakeGroupMarker() end
    viewport:SetScript("OnMouseWheel",function()
        local x,y=self:Cursor(); self:Zoom(arg1,x,y); panel:Hide(); search:ClearFocus()
    end)
    viewport:SetScript("OnMouseDown",function()
        local x,y=self:Cursor()
        if arg1=="MiddleButton" then self:FindMe(); return end
        if arg1=="RightButton" then self:Zoom(-3,x,y); return end
        if arg1~="LeftButton" then return end
        search:ClearFocus(); panel:Hide()
        if IsControlKeyDown() then
            if table.getn(zMapDB.pins)>=100 then self:Print("The map already has 100 pins. Remove a pin to add another."); return end
            local wx,wy=self:ToWorld(x,y)
            table.insert(zMapDB.pins,{x=wx,y=wy,space=self.view.space}); self.dirty=true; return
        end
        self.animation=nil; zMapDB.follow=false
        self.drag={x=x,y=y,cx=self.view.x,cy=self.view.y}
    end)
    viewport:SetScript("OnMouseUp",function() self.drag=nil; self:SaveView() end)
    viewport:SetScript("OnLeave",function()
        if not IsMouseButtonDown then self.drag=nil end
    end)
    local grip=CreateFrame("Frame",nil,f)
    grip:SetWidth(20); grip:SetHeight(20); grip:SetPoint("BOTTOMRIGHT",f,"BOTTOMRIGHT",0,0)
    grip:EnableMouse(true)
    text(grip,"//",2,-4,16)
    grip:SetScript("OnMouseDown",function() if arg1=="LeftButton" and not self.fullscreen then f:StartSizing("BOTTOMRIGHT") end end)
    grip:SetScript("OnMouseUp",function() f:StopMovingOrSizing(); self:SaveWindow(); self:Resize() end)
    self.help=text(f,"Wheel: zoom  |  Drag: pan  |  Middle: find me  |  Ctrl-click: pin",12,-f:GetHeight()+22,540)
    self.help:ClearAllPoints(); self.help:SetPoint("BOTTOMLEFT",f,"BOTTOMLEFT",12,11)
    self.help:SetTextColor(.65,.72,.8)
    self.coords=text(f,"",0,0,310)
    self.coords:ClearAllPoints(); self.coords:SetPoint("BOTTOMRIGHT",f,"BOTTOMRIGHT",-28,11)
    self.coords:SetJustifyH("RIGHT"); self.coords:SetTextColor(.65,.72,.8)
    f:SetScript("OnSizeChanged",function() if self.viewport then self:Resize() end end)
    f:SetScript("OnShow",function()
        self.mapChanged=true; self:SamplePlayer(true); self:Resize()
        self.gatherElapsed=0;self:SampleGather()
        if zMapDB.reopen=="player" then self:FindMe() end
        self.dirty=true
    end)
    f:SetScript("OnHide",function()
        self:HideGroupTooltip()
        self:HidePFQuest()
        self:ClearGather();self.gatherPanel:Hide()
        self.transportPanel:Hide();self:HideTransportTooltip()
        self.settingsPanel:Hide()
        self.drag=nil; self.animation=nil; search:ClearFocus(); panel:Hide()
        self:SaveView(); self:SaveWindow()
    end)
    f:SetScript("OnUpdate",function()
        local elapsed=arg1 or 0
        self:Animate(elapsed)
        if self.drag then
            if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then self.drag=nil
            else
                local x,y=self:Cursor(); local d=self.drag
                self.view.x=d.cx-(x-d.x)/self.view.scale
                self.view.y=d.cy-(y-d.y)/self.view.scale
                self:Constrain(); self.dirty=true
            end
        end
        if self.dirty then self:Render() end
        self.tick=(self.tick or 0)+elapsed
        if self.tick>=.15 then
            self.tick=0; self:SamplePlayer()
            local x,y=self:Cursor()
            local label="OctoWoW"
            if x>=0 and y>=0 and x<=self.view.width and y<=self.view.height then
                local wx,wy=self:ToWorld(x,y); local zone=self:ZoneAt(wx,wy)
                if zone then
                    label=zone.name
                    self.coords:SetText(string.format("%.1f, %.1f  |  %.0fx",(wx-zone.x)/zone.w*100,(wy-zone.y)/zone.h*100,self.view.scale/self:MinScale()))
                else self.coords:SetText(string.format("%.0fx",self.view.scale/self:MinScale())) end
            else self.coords:SetText("") end
            self.areaLabel:SetText(label)
            self.followButton.label:SetText(zMapDB.follow and "|cff59d9c5Follow|r" or "Follow")
        end
        self:UpdateGather(elapsed)
    end)
    table.insert(UISpecialFrames,"zMapFrame")
    self:Resize(); f:Hide()
end
function M:Toggle()
    if not self.ready then return end
    self:BuildUI()
    if self.frame:IsShown() then self.frame:Hide() else
        if WorldMapFrame and WorldMapFrame:IsShown() then HideUIPanel(WorldMapFrame) end
        self.frame:Show()
    end
end
function M:InstallToggle()
    if ToggleWorldMap==self.toggleWrapper then return end
    -- A closure owns its predecessor. Other addons can wrap this function later
    -- without creating a cycle when zMap installs after their initialization.
    local previous=ToggleWorldMap
    self.originalToggle=previous
    self.toggleWrapper=function()
        if zMapDB.replace and not M.nativeOnly and not (WorldMapFrame and WorldMapFrame:IsShown()) then
            M:Toggle()
        elseif previous then previous() end
    end
    ToggleWorldMap=self.toggleWrapper
end
function M:ShowNative()
    if self.frame then self.frame:Hide() end
    self.nativeOnly=true
    local ok,err=true,nil
    if self.originalToggle then ok,err=pcall(self.originalToggle) end
    self.nativeOnly=false
    if not ok then self:Print("The original map reported: "..tostring(err)) end
end
function M:Initialize()
    zMapDB=zMapDB or {}
    for k,value in pairs(defaults) do
        if zMapDB[k]==nil then
            if type(value)=="table" then zMapDB[k]={} else zMapDB[k]=value end
        end
    end
    zMapDB.width=self.Clamp(tonumber(zMapDB.width) or 1000,730,max(730,UIParent:GetWidth()-12))
    zMapDB.height=self.Clamp(tonumber(zMapDB.height) or 690,440,max(440,UIParent:GetHeight()-12))
    if zMapDB.style~="painted" and zMapDB.style~="terrain" then zMapDB.style="hybrid" end
    if zMapDB.interiors~="surface" and zMapDB.interiors~="underground" then zMapDB.interiors="auto" end
    self:InitializeSync()
    self:InitializeGather()
    self:InitializeTransports()
    if type(zMapDB.pins)~="table" then zMapDB.pins={} end
    if zMapDB.layoutVersion~=self.data.layoutVersion then
        for _,pin in ipairs(zMapDB.pins) do
            if pin.space=="world" and type(pin.x)=="number" and type(pin.y)=="number" then
                local mapID=pin.map or (pin.x>=26000 and 0 or 1)
                local old,new=self.data.legacyOrigins[mapID],self.data.origins[mapID]
                if old and new then pin.x=pin.x-old[1]+new[1];pin.y=pin.y-old[2]+new[2] end
            end
        end
        if type(zMapDB.view)=="table" and zMapDB.view.space=="world" then zMapDB.view=nil end
        zMapDB.layoutVersion=self.data.layoutVersion
    end
    self.ready=true
    self:World()
    local saved=zMapDB.view
    if type(saved)=="table" and type(saved.x)=="number" and type(saved.y)=="number" and
        type(saved.scale)=="number" and type(saved.space)=="string" then
        self.view.x=saved.x; self.view.y=saved.y; self.view.scale=saved.scale; self.view.space=saved.space
        self.focus=self.byID[saved.focus]; self:Constrain()
    end
    self:InstallToggle()
    self:InitializePFQuest()
    self:InitializeMinimap()
    self:Print("Loaded. Press M or type /zmap. Search includes custom zones and instance maps.")
end
SLASH_ZMAP1="/zmap"
SLASH_ZMAP2="/zm"
SlashCmdList["ZMAP"]=function(message)
    message=string.lower(message or "")
    if message=="blizzard" then
        M:ShowNative()
    elseif message=="replace" then
        zMapDB.replace=not zMapDB.replace; M:Print("M opens "..(zMapDB.replace and "zMap." or "the stock map."))
    elseif message=="player" or message=="last" then
        zMapDB.reopen=message; M:Print("Reopen view: "..message..".")
    elseif message=="reset" then
        zMapDB.follow=false; M:World(); if not M.frame or not M.frame:IsShown() then M:Toggle() end
    elseif message=="status" then
        M:Print("v"..M.version.." | atlas "..M.data.built.." | "..table.getn(M.data.zones).." areas | no addon dependencies")
        if M.viewport then
            M:Print("Textures: "..M.stats.drawn.." drawn, "..M.stats.native.." native terrain, "..M.stats.interior.." interior, "..(M.stats.caves or 0).." cave, "..M.stats.loads.." loaded in last render (limit 4).")
            M:Print(M.gatherStatus.." | "..(M.gatherShown or 0).." resource markers shown.")
        end
        M:Print("Nodes: "..table.getn(M.gatherLogNodes).." logged | sharing "..M:GatherSharingStatus()..
            " | "..(M.gatherShareReceived or 0).." new shared locations this session.")
        if M:PFQuestAvailable() then M:Print("pfQuest: "..(zMapDB.pfQuest and "on" or "off").." | "..(M.pfShown or 0).." map icons | "..(M.pfRoutesShown or 0).." route dots.") end
        if zMapDB.minimapOverride then M:Print("Minimap player: "..(M.miniUsesNativeArrow and "native model ("..(M.nativeArrowSource or "detected")..")" or "projected arrow")..".") end
    elseif message=="nodes reset" then M:ResetGatherVisibility()
    elseif message=="nodes" then M:ToggleGatherPanel()
    elseif message=="transit" then M:ToggleTransportPanel()
    elseif message=="settings" then M:ToggleSettingsPanel()
    elseif message=="help" then
        M:Print("/zmap, /zmap settings, /zmap nodes, /zmap nodes reset, /zmap transit, /zmap blizzard, /zmap replace, /zmap player, /zmap last, /zmap reset, /zmap status. Wheel zooms; drag pans; Ctrl-click drops a pin.")
    else M:Toggle() end
end
local events=CreateFrame("Frame")
events:RegisterEvent("VARIABLES_LOADED"); events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA"); events:RegisterEvent("ZONE_CHANGED")
events:RegisterEvent("ZONE_CHANGED_INDOORS");events:RegisterEvent("PLAYER_LEAVING_WORLD")
events:SetScript("OnEvent",function()
    if event=="VARIABLES_LOADED" then M:Initialize() else
        M.mapChanged=true
        if M.ready then M:ClearGather() end
        if event=="PLAYER_ENTERING_WORLD" and M.ready then M:InstallToggle() end
    end
end)
