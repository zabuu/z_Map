-- Independent atlas viewport: never swap the main map's view, pools or focus.
local M=zMap
local ARROW="Interface\\Minimap\\MinimapArrow"
local outdoor={466+2/3,400,333+1/3,266+2/3,200,133+1/3}
local indoor={300,240,180,120,80,50}
local layerNames={"overview","art","artFine","terrain","fine","detail","caves","interior","transitRoutes","gather","transit","questRoutes","quests","markers"}
local strataOrder={BACKGROUND=1,LOW=2,MEDIUM=3,HIGH=4,DIALOG=5,FULLSCREEN=6,FULLSCREEN_DIALOG=7,TOOLTIP=8}
local function angle(value) return type(value)=="number" and value==value and math.abs(value)<1000 end
local function facing(model)
    if not model or not model.GetFacing then return end
    local ok,value=pcall(model.GetFacing,model)
    if ok and angle(value) then return value end
end
local function arrowKind(child,slot)
    if not child or type(child.GetFacing)~="function" then return end
    local ok,model=false,nil
    if child.GetModel then ok,model=pcall(child.GetModel,child) end
    if ok and type(model)=="string" and string.find(string.lower(model),"minimaparrow",1,true) then return "path" end
    -- Vanilla's native arrow is not reliably exposed as a Lua Model with a
    -- readable filename. The stock/pfUI fallback is its ninth child slot.
    local name=child.GetName and child:GetName()
    if name~="MiniMapCompassRing" and (not name or name=="" or slot==9) and angle(child:GetFacing()) then return "facing" end
end
function M:ReadMinimapCVar(name)
    if type(GetCVar)~="function" or self.missingMinimapCVars and self.missingMinimapCVars[name] then return nil end
    local ok,value=pcall(GetCVar,name)
    if ok then return value end
    self.missingMinimapCVars=self.missingMinimapCVars or {};self.missingMinimapCVars[name]=true
    return nil
end
function M:MinimapRotated()
    -- rotateMinimap was added after Vanilla. GetCVar raises on unknown names;
    -- the stock 1.12 client must never be asked for this later-client setting.
    if type(GetBuildInfo)~="function" then return false end
    local _,_,_,interface=GetBuildInfo();interface=tonumber(interface)
    if not interface or interface<=11200 then return false end
    return self:ReadMinimapCVar("rotateMinimap")=="1"
end
function M:FindNativePlayerArrow()
    local now=GetTime and GetTime() or 0
    if not self.nativeArrow and Minimap and Minimap.GetChildren and now>=(self.arrowSearchAt or 0) then
        self.arrowSearchAt=now+2
        local candidate,source
        for slot,child in pairs({Minimap:GetChildren()}) do
            local ok,kind=pcall(arrowKind,child,slot)
            if ok and kind=="path" then candidate=child;source="model path";break end
            if ok and kind=="facing" and (not candidate or slot==9) then
                candidate=child;source=slot==9 and "native slot 9" or "native facing frame"
            end
        end
        self.nativeArrow=candidate;self.nativeArrowSource=source
    end
    return self.nativeArrow
end
function M:SuppressNativePlayerArrow(enabled)
    local arrow=enabled and self:FindNativePlayerArrow() or self.nativeArrow
    if not arrow or not arrow.GetAlpha or not arrow.SetAlpha then return end
    if enabled then
        local alpha=arrow:GetAlpha()
        if alpha~=0 then
            self.nativeArrowAlpha=alpha;arrow:SetAlpha(0)
        elseif self.nativeArrowAlpha==nil then self.nativeArrowAlpha=0 end
        -- The 1.12 model renderer can ignore alpha. Hide the model itself too;
        -- its native facing remains readable without a second rendered arrow.
        if arrow:IsShown() then self.nativeArrowShown=true;arrow:Hide()
        elseif self.nativeArrowShown==nil then self.nativeArrowShown=false end
    elseif self.nativeArrowAlpha~=nil then
        if arrow:GetAlpha()==0 then arrow:SetAlpha(self.nativeArrowAlpha) end
        self.nativeArrowAlpha=nil
        if self.nativeArrowShown and not arrow:IsShown() then arrow:Show() end
        self.nativeArrowShown=nil
    end
end
function M:PlayerFacing()
    if type(GetPlayerFacing)=="function" then
        local ok,value=pcall(GetPlayerFacing)
        if ok and angle(value) then self.playerFacing=value;return value end
    end
    local rotated=self:MinimapRotated()
    local value=rotated and facing(MiniMapCompassRing)
    if value then self.playerFacing=-value;return -value end
    value=facing(self:FindNativePlayerArrow())
    if value then self.playerFacing=value end
    return self.playerFacing
end
function M:RaiseMapPlayer(ctx)
    local level=ctx.viewport:GetFrameLevel();local strata=ctx.viewport:GetFrameStrata()
    for _,name in ipairs(layerNames) do
        local layer=ctx.layers[name];local layerStrata=layer:GetFrameStrata()
        level=math.max(level,layer:GetFrameLevel())
        if (strataOrder[layerStrata] or 0)>(strataOrder[strata] or 0) then strata=layerStrata end
    end
    level=level+4
    if ctx.playerMarker:GetFrameStrata()~=strata then ctx.playerMarker:SetFrameStrata(strata) end
    if ctx.playerMarker:GetFrameLevel()~=level then ctx.playerMarker:SetFrameLevel(level) end
    return level,strata
end
function M:UseNativeMinimapPlayer(enabled)
    local rotated=self:MinimapRotated()
    -- The ordinary 1.12 minimap is north up, like this atlas. Reuse its actual
    -- player model rather than drawing another arrow over a client model.
    self:SuppressNativePlayerArrow(enabled and rotated)
    local arrow=enabled and self:FindNativePlayerArrow() or self.nativeArrow
    -- The native minimap model can render while IsShown() returns nil. Its
    -- existence, not that unreliable flag, decides whether to draw a copy.
    self.miniUsesNativeArrow=enabled and not rotated and arrow and arrow:GetAlpha()>0 or false
    local level,strata
    if enabled then
        -- Leave room for marker children, live-node rims and quest highlights.
        -- Frame levels alone cannot put a native BACKGROUND model above LOW art.
        level,strata=self:RaiseMapPlayer(self.miniContext)
        if self.miniUsesNativeArrow then self.miniContext.playerMarker:Hide() end
    end
    if self.miniUsesNativeArrow then
        local current=arrow:GetFrameLevel()
        local currentStrata=arrow:GetFrameStrata()
        if current~=self.nativeArrowAppliedLevel then self.nativeArrowLevel=current end
        if currentStrata~=self.nativeArrowAppliedStrata then self.nativeArrowStrata=currentStrata end
        if (strataOrder[currentStrata] or 0)>(strataOrder[strata] or 0) then strata=currentStrata end
        if currentStrata~=strata then arrow:SetFrameStrata(strata) end
        if current~=level then arrow:SetFrameLevel(level) end
        self.nativeArrowAppliedLevel=level;self.nativeArrowAppliedStrata=strata
    else
        local restoreLevel=arrow and self.nativeArrowLevel~=nil and arrow:GetFrameLevel()==self.nativeArrowAppliedLevel
        if arrow and self.nativeArrowStrata and arrow:GetFrameStrata()==self.nativeArrowAppliedStrata then arrow:SetFrameStrata(self.nativeArrowStrata) end
        if restoreLevel then arrow:SetFrameLevel(self.nativeArrowLevel) end
        self.nativeArrowLevel=nil;self.nativeArrowAppliedLevel=nil
        self.nativeArrowStrata=nil;self.nativeArrowAppliedStrata=nil
    end
end
function M:UpdatePlayerArrow(texture)
    if not texture then return end
    local value=M:PlayerFacing() or 0
    if texture.zMapFacing==value then return end
    -- Facing is radians counterclockwise from north; the native texture points up.
    local c,s=math.cos(value)/2,-math.sin(value)/2
    texture:SetTexCoord(.5-c-s,.5+s-c, .5-c+s,.5+s+c,
        .5+c-s,.5-s-c, .5+c+s,.5-s+c)
    texture.zMapFacing=value
end
function M:IsGatherVisible()
    return self.frame and self.frame:IsShown() or
        zMapDB.minimapOverride and self.miniContext and self.miniContext.frame:IsShown() or
        self.hudContext and self.hudContext.frame:IsShown()
end
local function hideTooltip(self,key,cache,marker)
    local current=rawget(self,key)
    if current and (not marker or current==marker) then self[key]=false;if cache then self[cache]=false end;GameTooltip:Hide() end
end
local function forward(script)
    if script=="OnMouseWheel" and zMapDB.minimapOverride then M:ZoomAtlasMinimap(arg1);return end
    local handler=Minimap and Minimap:GetScript(script)
    if handler then
        local previous=this;this=Minimap
        local ok,err=pcall(handler);this=previous
        if not ok then error(err) end
    elseif script=="OnMouseWheel" and Minimap and Minimap.SetZoom then
        Minimap:SetZoom(M.Clamp(Minimap:GetZoom()+(arg1>0 and 1 or -1),0,5))
    end
end
function M:CreateMinimapContext()
    local frame=CreateFrame("Frame",nil,Minimap);frame:SetAllPoints(Minimap)
    frame:EnableMouseWheel(true)
    frame:SetFrameLevel(Minimap:GetFrameLevel()+1)
    frame:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"});frame:SetBackdropColor(.075,.12,.15,1)
    local ctx=setmetatable({frame=frame,viewport=frame,view={x=0,y=0,width=140,height=140,scale=1,space="world"},
        layers={},pools={},grids=self.grids,gridSeen={},stats={},serial=0,loadLimit=1,focus=false,
        groupMarkers={},pinMarkers={},gatherMarkers={},gatherMarkerFree={},gatherRenderEpoch=0,
        hoveredGather=false,gatherTooltipMarker=false,hoveredGroupMarker=false,groupTooltipMarker=false,hoveredTransport=false,
        transportDockMarkers={},transportVehicleMarkers={},transportVehicleByEntry={},transportRouteDots={},transportRouteView=false},
        {__index=M})
    ctx.UpdateLayerButton=function() end;ctx.UpdateGatherStatus=function() end
    ctx.HideGatherTooltip=function(self,marker) hideTooltip(self,"hoveredGather","gatherTooltipMarker",marker) end
    ctx.HideGroupTooltip=function(self,marker) hideTooltip(self,"hoveredGroupMarker","groupTooltipMarker",marker) end
    ctx.HideTransportTooltip=function(self,marker) hideTooltip(self,"hoveredTransport",nil,marker) end
    ctx.RenderMarkers=function(self) M:RenderMinimapMarkers(self) end
    for i,name in ipairs(layerNames) do
        local layer=CreateFrame("Frame",nil,frame);layer:SetAllPoints(frame)
        layer:SetFrameLevel(frame:GetFrameLevel()+i);ctx.layers[name]=layer
    end
    ctx.playerMarker=ctx:MakeMarker(1,1,1,22)
    ctx.playerMarker.texture:SetTexture(ARROW);ctx.playerMarker.texture:SetTexCoord(0,1,0,1)
    for _,name in ipairs({"OnMouseDown","OnMouseUp","OnMouseWheel"}) do
        local script=name;frame:SetScript(script,function() forward(script) end)
    end
    frame:SetScript("OnHide",function()
        ctx:HideGatherTooltip();ctx:HideGroupTooltip();ctx:HideTransportTooltip()
        ctx:HidePFQuest();M:RestorePFQuestMinimap();M:UseNativeMinimapPlayer(false);M:RaiseMinimapWidgets(false)
    end)
    frame:Hide();self.miniContext=ctx;return ctx
end
function M:RenderMinimapMarkers(ctx)
    ctx:RenderGatherMarkers();ctx:RenderTransports();ctx:RenderPFQuest()
    local p=ctx.player
    if p and not self.miniUsesNativeArrow then
        ctx:PlaceMarker(ctx.playerMarker,p.x,p.y,p.space);self:UpdatePlayerArrow(ctx.playerMarker.texture)
    else ctx.playerMarker:Hide() end
    local used=0
    for i,member in ipairs(self.group or {}) do
        local marker=ctx.groupMarkers[i]
        if not marker then marker=ctx:MakeGroupMarker();ctx.groupMarkers[i]=marker end
        marker.member=member;local r,g,b=self:ClassColor(member.class)
        if marker.r~=r or marker.g~=g or marker.b~=b then marker.texture:SetVertexColor(r,g,b);marker.r=r;marker.g=g;marker.b=b end
        local size=14*(ctx.gatherIconScale or 1)
        if marker:GetWidth()~=size then marker:SetWidth(size);marker:SetHeight(size) end
        ctx:PlaceMarker(marker,member.x,member.y,member.space);used=i
    end
    for i=used+1,table.getn(ctx.groupMarkers) do ctx.groupMarkers[i]:Hide() end
    for i,pin in ipairs(zMapDB.pins) do
        local marker=ctx.pinMarkers[i]
        if not marker then marker=ctx:MakeMarker(1,.75,.22,10);ctx.pinMarkers[i]=marker end
        ctx:PlaceMarker(marker,pin.x,pin.y,pin.space)
    end
    for i=table.getn(zMapDB.pins)+1,table.getn(ctx.pinMarkers) do ctx.pinMarkers[i]:Hide() end
end
function M:MinimapZoom()
    return Minimap.GetZoom and self.Clamp(Minimap:GetZoom(),0,5) or 0
end
function M:MinimapSpan()
    local zoom=self:MinimapZoom()
    local inside=IsIndoors and IsIndoors()
    local a,b=tonumber(self:ReadMinimapCVar("minimapInsideZoom")),tonumber(self:ReadMinimapCVar("minimapZoom"))
    if not IsIndoors and a and b and a~=b then inside=zoom==a end
    return (inside and indoor or outdoor)[zoom+1]*1.3^(zoom==0 and (zMapDB.minimapExtraZoom or 0) or 0)
end
function M:ZoomAtlasMinimap(delta)
    if not Minimap or not Minimap.SetZoom or not delta or delta==0 then return end
    local zoom=self:MinimapZoom();local extra=zMapDB.minimapExtraZoom or 0
    if delta>0 then
        if zoom==0 and extra>0 then extra=extra-1 else Minimap:SetZoom(math.min(5,zoom+1));extra=0 end
    elseif zoom==0 then extra=math.min(2,extra+1)
    else Minimap:SetZoom(zoom-1);extra=0 end
    zMapDB.minimapExtraZoom=extra;self:UpdateMinimapZoomButtons(true)
end
function M:UpdateMinimapZoomButtons(enabled)
    local zoom=self:MinimapZoom();local extra=enabled and (zMapDB.minimapExtraZoom or 0) or 0
    for _,item in ipairs({{MinimapZoomIn,zoom<5 or extra>0},{MinimapZoomOut,zoom>0 or enabled and extra<2}}) do
        local button=item[1]
        if button then if item[2] then button:Enable() else button:Disable() end end
    end
end
function M:RaiseMinimapWidgets(enabled)
    if enabled and self.miniWidgetLevels then return end
    if enabled then
        self.miniWidgetLevels={};local level=self.miniContext.layers.markers:GetFrameLevel()+3
        for _,name in ipairs({"MinimapZoomIn","MinimapZoomOut","MinimapToggleButton","MiniMapTrackingFrame","MiniMapMailFrame","MiniMapBattlefieldFrame","MiniMapPing","GameTimeFrame"}) do
            local widget=getglobal and getglobal(name)
            if widget and widget.GetFrameLevel and widget.SetFrameLevel then
                table.insert(self.miniWidgetLevels,{widget,widget:GetFrameLevel(),level});widget:SetFrameLevel(level)
            end
        end
    elseif self.miniWidgetLevels then
        for _,item in ipairs(self.miniWidgetLevels) do if item[1]:GetFrameLevel()==item[3] then item[1]:SetFrameLevel(item[2]) end end
        self.miniWidgetLevels=nil
    end
end
function M:HideAtlasMinimap()
    if self.miniContext and self.miniContext.frame:IsShown() then self.miniContext.frame:Hide() end
    self:UseNativeMinimapPlayer(false)
    self:RaiseMinimapWidgets(false)
    if self.miniZoomOwned then self:UpdateMinimapZoomButtons(false);self.miniZoomOwned=nil end
end
function M:SetAtlasMinimap(enabled)
    zMapDB.minimapOverride=enabled==true
    if not enabled then self:HideAtlasMinimap();if not self:IsGatherVisible() then self:ClearGather() end end
    self.miniRenderKey=nil;self:RefreshSettingsPanel()
end
function M:UpdateAtlasMinimap(elapsed)
    if not zMapDB.minimapOverride or not self.miniWorld or not Minimap or
        not Minimap:IsShown() or Minimap.IsVisible and not Minimap:IsVisible() or WorldMapFrame and WorldMapFrame:IsShown() then
        self:HideAtlasMinimap();return
    end
    local large=self.frame and self.frame:IsShown()
    if not large then self:SamplePlayer() end
    local p=self.player
    if not p then self:HideAtlasMinimap();return end
    local ctx=self.miniContext or self:CreateMinimapContext();local v=ctx.view
    local w,h=Minimap:GetWidth(),Minimap:GetHeight()
    if w<30 or h<30 then self:HideAtlasMinimap();return end
    local scale=math.min(w,h)/self:MinimapSpan()
    local style=zMapDB.minimapStyle=="match" and zMapDB.style or zMapDB.minimapStyle
    local changed=v.x~=p.x or v.y~=p.y or v.space~=p.space or v.width~=w or v.height~=h or v.scale~=scale or ctx.style~=style or ctx.focus~=p.zone or ctx.interiorMode~=zMapDB.interiors
    v.x=p.x;v.y=p.y;v.space=p.space;v.width=w;v.height=h;v.scale=scale
    ctx.gatherIconScale=.65+.35*self:MinimapZoom()/5
    ctx.player=p;ctx.group=self.group;ctx.gatherNodes=self.gatherNodes;ctx.focus=p.zone or false;ctx.style=style;ctx.interiorMode=zMapDB.interiors
    if ctx.frame:GetWidth()~=w then ctx.frame:SetWidth(w) end;if ctx.frame:GetHeight()~=h then ctx.frame:SetHeight(h) end
    if not ctx.frame:IsShown() then ctx.frame:Show();changed=true end
    self:UseNativeMinimapPlayer(true)
    self:RaiseMinimapWidgets(true)
    self:UpdateMinimapZoomButtons(true);self.miniZoomOwned=true
    if not large then self:UpdateGather(elapsed) end
    if changed or ctx.pending then ctx:Render() else self:RenderMinimapMarkers(ctx) end
    ctx:UpdateGatherVisuals(elapsed)
end
function M:InitializeMinimap()
    zMapDB.minimapOverride=zMapDB.minimapOverride==true
    if zMapDB.minimapStyle~="terrain" and zMapDB.minimapStyle~="painted" then zMapDB.minimapStyle="match" end
    zMapDB.minimapExtraZoom=self.Clamp(math.floor(tonumber(zMapDB.minimapExtraZoom) or 0),0,2)
    for _,direction in ipairs({"In","Out"}) do
        local name="Minimap_Zoom"..direction;local previous=getglobal and getglobal(name);local delta=direction=="In" and 1 or -1
        if type(previous)=="function" then setglobal(name,function()
            if zMapDB.minimapOverride and self.miniContext and self.miniContext.frame:IsShown() then self:ZoomAtlasMinimap(delta)
            else return previous() end
        end) end
    end
    self.miniWorld=false
    local driver=CreateFrame("Frame");self.minimapDriver=driver
    driver:RegisterEvent("PLAYER_ENTERING_WORLD");driver:RegisterEvent("PLAYER_LEAVING_WORLD")
    driver:SetScript("OnEvent",function()
        self.miniWorld=event=="PLAYER_ENTERING_WORLD"
        if not self.miniWorld then self:HideAtlasMinimap() end
    end)
    local arrowElapsed,miniElapsed=0,0
    driver:SetScript("OnUpdate",function()
        if not self.ready then return end
        local dt=arg1 or 0;arrowElapsed=arrowElapsed+dt;miniElapsed=miniElapsed+dt
        if arrowElapsed>=.05 then
            arrowElapsed=0
            if self.frame and self.frame:IsShown() then self:UpdatePlayerArrow(self.playerMarker and self.playerMarker.texture) end
            if self.miniContext and self.miniContext.frame:IsShown() then self:UpdatePlayerArrow(self.miniContext.playerMarker.texture) end
        end
        if miniElapsed>=.1 then
            local elapsed=miniElapsed;miniElapsed=0
            self:UpdateAtlasMinimap(elapsed);self:UpdatePFQuest(elapsed)
        end
        self:UpdateHUD(dt)
        -- Repair ordering after rendering/integration updates, even on frames
        -- where the stationary atlas skips its slower texture/marker refresh.
        if self.miniContext and self.miniContext.frame:IsShown() then self:UseNativeMinimapPlayer(true) end
    end)
end
function M:RefreshSettingsPanel()
    if not self.settingsPanel then return end
    self.minimapOption.label:SetText(zMapDB.minimapOverride and "Minimap: zMap" or "Minimap: Blizzard")
    self.minimapLookOption.label:SetText("Look: "..(zMapDB.minimapStyle=="match" and "same as map" or zMapDB.minimapStyle))
    self.pfQuestOption.label:SetText(not self:PFQuestAvailable() and "pfQuest: not loaded" or zMapDB.pfQuest and "pfQuest: on" or "pfQuest: off")
    self.hudOption.label:SetText(zMapDB.hudEnabled and "HUD: on" or "HUD: off")
    self.hudQuestOption.label:SetText(zMapDB.hudQuests and "HUD quests: on" or "HUD quests: off")
    self.hudRangeOption.label:SetText("HUD range: "..zMapDB.hudRange.."y")
    self.hudOpacityOption.label:SetText("Wall opacity: "..math.floor(zMapDB.hudOpacity*100+.5).."%")
end
function M:BuildSettingsUI(button,text,surface)
    local panel=CreateFrame("Frame",nil,self.frame);self.settingsPanel=panel
    panel:SetWidth(340);panel:SetHeight(390);panel:SetPoint("TOPLEFT",self.frame,"TOPLEFT",82,-42)
    panel:SetFrameLevel(self.frame:GetFrameLevel()+50);panel:EnableMouse(true);surface(panel)
    text(panel,"Map settings",12,-12,270,true)
    local close=button(panel,"X",24,function() panel:Hide() end);close:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-8,-8)
    self.minimapOption=button(panel,"",150,function() self:SetAtlasMinimap(not zMapDB.minimapOverride) end)
    self.minimapOption:SetPoint("TOPLEFT",panel,"TOPLEFT",12,-42)
    self.minimapLookOption=button(panel,"",150,function()
        local nextLook={match="terrain",terrain="painted",painted="match"};zMapDB.minimapStyle=nextLook[zMapDB.minimapStyle]
        self:RefreshSettingsPanel()
    end);self.minimapLookOption:SetPoint("LEFT",self.minimapOption,"RIGHT",8,0)
    text(panel,"Optional square atlas, north up. Uses the minimap's zoom controls and follows your position.",12,-82,316)
    text(panel,"Shows zMap nodes, group members and transit. Uses Blizzard's map when your position is unavailable.",12,-126,316)
    self.pfQuestOption=button(panel,"",150,function() self:SetPFQuest(not zMapDB.pfQuest) end)
    self.pfQuestOption:SetPoint("TOPLEFT",panel,"TOPLEFT",12,-174)
    text(panel,"Quest icons, tooltips, map links and active paths. Uses pfQuest's filters and route selection.",12,-208,316)
    self.hudOption=button(panel,"",150,function() self:SetHUD(not zMapDB.hudEnabled) end)
    self.hudOption:SetPoint("TOPLEFT",panel,"TOPLEFT",12,-252)
    self.hudQuestOption=button(panel,"",150,function() zMapDB.hudQuests=not zMapDB.hudQuests;self:RefreshSettingsPanel() end)
    self.hudQuestOption:SetPoint("LEFT",self.hudOption,"RIGHT",8,0)
    self.hudRangeOption=button(panel,"",150,function()
        local ranges={[120]=180,[180]=240,[240]=360,[360]=120};zMapDB.hudRange=ranges[zMapDB.hudRange] or 240;self:RefreshSettingsPanel()
    end);self.hudRangeOption:SetPoint("TOPLEFT",panel,"TOPLEFT",12,-286)
    self.hudOpacityOption=button(panel,"",150,function()
        local opacity=zMapDB.hudOpacity;zMapDB.hudOpacity=opacity<.3 and .35 or opacity<.45 and .5 or .2;self:RefreshSettingsPanel()
    end);self.hudOpacityOption:SetPoint("LEFT",self.hudRangeOption,"RIGHT",8,0)
    text(panel,"Experimental HUD: walls and nodes, direction up. Click-through. Assign a key in Key Bindings.",12,-328,316)
    self:RefreshSettingsPanel();panel:Hide()
end
function M:ToggleSettingsPanel()
    self:BuildUI();self.frame:Show()
    if self.settingsPanel:IsShown() then self.settingsPanel:Hide()
    else self.searchPanel:Hide();self.gatherPanel:Hide();self.transportPanel:Hide();self:RefreshSettingsPanel();self.settingsPanel:Show() end
end
