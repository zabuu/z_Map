local M=zMap
local PREFIX="Interface\\AddOns\\z_Map\\Media\\Transports14\\"
local WHITE="Interface\\Buttons\\WHITE8X8"
local function clock(seconds)
    seconds=math.max(0,math.ceil(seconds));return string.format("%d:%02d",math.floor(seconds/60),math.mod(seconds,60))
end
function M:TransportStatusText(stop)
    local status,seconds=self:TransportStopStatus(stop)
    if status=="docked" then return seconds and "Docked; leaves ~"..clock(seconds) or "Docked; departure unknown" end
    if status=="reported" then return seconds and "Reported docked; leaves ~"..clock(seconds) or "Reported docked" end
    if status=="expected" then return "Expected docked; leaves ~"..clock(seconds) end
    if status=="arriving" then return "Arrives ~"..clock(seconds) end
    if stop.route.data.identitySource~="installed client cache" and not stop.route.state.detectedAt then return "Service unconfirmed" end
    return "Awaiting sync"
end
function M:HideTransportTooltip(marker)
    if self.hoveredTransport and (not marker or self.hoveredTransport==marker) then self.hoveredTransport=nil;GameTooltip:Hide() end
end
function M:ShowTransportTooltip(marker)
    self.hoveredTransport=marker
    GameTooltip:SetOwner(marker,"ANCHOR_RIGHT")
    local live=marker.vehicle
    if live then
        GameTooltip:SetText(live.route.name,1,.82,.35)
        if live.source=="estimated" then
            GameTooltip:AddLine(live.stop and "Estimated: docked" or "Estimated: in transit",.75,.8,.85)
            GameTooltip:AddLine("Model: "..live.method..". This is a prediction.",.7,.76,.82)
            if live.correctedAt then GameTooltip:AddLine("Corrected by "..live.correctionSource.." ~"..clock(self:TransportNow()-live.correctedAt).." ago.",.7,.76,.82) end
        elseif live.source=="shared" then
            GameTooltip:AddLine(live.stop and "Shared report: docked" or "Shared report: in transit",.5,.8,1)
            GameTooltip:AddLine("Transport sighted by "..live.sender.." ~"..string.format("%.1f",live.age).."s ago.",.7,.76,.82)
        else
            GameTooltip:AddLine(live.stop and "Live: docked" or (live.route.kind=="zeppelin" and "Live: flying" or "Live: sailing"),.35,1,.75)
            GameTooltip:AddLine("Detected locally; movement is smoothed between samples.",.7,.76,.82)
        end
    else GameTooltip:SetText(marker.route and marker.route.name or "Transport terminal",1,.82,.35) end
    local stops=marker.stops or (live and live.route.stops) or (marker.route and marker.route.stops) or {}
    for _,stop in ipairs(stops) do
        local _,_,source=self:TransportStopStatus(stop)
        GameTooltip:AddLine(stop.name..": "..self:TransportStatusText(stop),.9,.94,.98)
        GameTooltip:AddLine(stop.route.name.." | "..source,.6,.68,.75)
        if stop.route.data.identitySource~="installed client cache" and not stop.route.state.detectedAt then
            GameTooltip:AddLine("Client route only; this server service is unconfirmed.",.75,.65,.5)
        end
    end
    GameTooltip:AddLine("~ times are estimates; restart schedules can drift.",.7,.76,.82)
    if marker.route then
        local count=0
        for leg=1,2 do for _ in pairs(marker.route.state.motion.legs[leg].samples) do count=count+1 end end
        GameTooltip:AddLine(count.." recorded speed samples (maximum 128 per service).",.7,.76,.82)
    end
    GameTooltip:AddLine("Dotted links at wide zoom show service connections.",.7,.76,.82)
    GameTooltip:Show()
end
function M:MakeTransportMarker()
    local marker=CreateFrame("Frame",nil,self.layers.transit)
    marker.icon=marker:CreateTexture(nil,"ARTWORK");marker.icon:SetAllPoints(marker)
    marker.label=marker:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    marker.label:SetPoint("LEFT",marker,"RIGHT",3,0);marker.label:SetWidth(200);marker.label:SetJustifyH("LEFT")
    marker.label:SetTextColor(1,.88,.55)
    marker.badge=marker:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    marker.badge:SetPoint("BOTTOMRIGHT",marker,"BOTTOMRIGHT",3,-2);marker.badge:Hide()
    marker:EnableMouse(true);marker:EnableMouseWheel(true)
    marker:SetScript("OnEnter",function() self:ShowTransportTooltip(marker) end)
    marker:SetScript("OnLeave",function() self:HideTransportTooltip(marker) end)
    marker:SetScript("OnHide",function() self:HideTransportTooltip(marker) end)
    for _,name in ipairs({"OnMouseDown","OnMouseUp","OnMouseWheel"}) do
        local handler=name
        marker:SetScript(handler,function() local action=self.viewport:GetScript(handler);if action then action() end end)
    end
    marker:Hide();return marker
end
local function clip(x,y,dx,dy,w,h)
    local lo,hi=0,1
    for _,pair in ipairs({{-dx,x-3},{dx,w-3-x},{-dy,y-3},{dy,h-3-y}}) do
        local p,q=pair[1],pair[2]
        if p==0 then if q<0 then return end
        else
            local t=q/p
            if p<0 then lo=math.max(lo,t) else hi=math.min(hi,t) end
            if lo>hi then return end
        end
    end
    return lo,hi
end
function M:TransportRouteSegment(x,y,a,b,kind,schematic)
    if self.transportDotsUsed>=384 then return end
    local sx,sy=self:ToScreen(x,y);local ex,ey=self:ToScreen(a,b)
    local dx,dy=ex-sx,ey-sy
    local lo,hi=clip(sx,sy,dx,dy,self.view.width,self.view.height);if not lo then return end
    local length=math.sqrt(dx*dx+dy*dy);if length<1 then return end
    local step=schematic and 13 or 10
    local count=math.min(384-self.transportDotsUsed,math.max(1,math.floor(length*(hi-lo)/step)+1))
    for i=1,count do
        local t=lo+(hi-lo)*(i-.5)/count
        local index=self.transportDotsUsed+1;local dot=self.transportRouteDots[index]
        if not dot then
            dot=self.layers.transitRoutes:CreateTexture(nil,"ARTWORK");dot:SetTexture(WHITE)
            dot:SetWidth(2);dot:SetHeight(2);self.transportRouteDots[index]=dot
        end
        dot:ClearAllPoints();dot:SetPoint("CENTER",self.viewport,"TOPLEFT",sx+dx*t,-sy-dy*t)
        if kind=="zeppelin" then dot:SetVertexColor(.95,.71,.27,schematic and .34 or .52)
        else dot:SetVertexColor(.3,.76,.92,schematic and .34 or .52) end
        dot:Show();self.transportDotsUsed=index
    end
end
function M:RenderTransportRoutes()
    local v=self.view;local enabled=zMapDB.transportsEnabled and zMapDB.transportRoutes and v.space=="world"
    local key=self.transportRouteView
    if key and key.x==v.x and key.y==v.y and key.scale==v.scale and key.w==v.width and key.h==v.height and key.enabled==enabled then return end
    self.transportRouteView={x=v.x,y=v.y,scale=v.scale,w=v.width,h=v.height,enabled=enabled};self.transportDotsUsed=0
    if enabled then
        local wide=math.max(v.width,v.height)/v.scale>14000
        for _,route in ipairs(self.transportRoutes) do
            if wide then
                local a,b=route.stops[1],route.stops[2]
                if a and b then self:TransportRouteSegment(a.x,a.y,b.x,b.y,route.kind,true) end
            else
                for i,node in ipairs(route.data.points) do
                    local other=route.data.points[i+1]
                    if other and node[1]==other[1] and node[5]~=1 and other[5]~=1 and
                        (other[2]-node[2])^2+(other[3]-node[3])^2<6000^2 then
                        local origin=self.data.origins[node[1]]
                        if origin then self:TransportRouteSegment(origin[1]-node[3],origin[2]-node[2],origin[1]-other[3],origin[2]-other[2],route.kind,false) end
                    end
                end
            end
        end
    end
    for i=self.transportDotsUsed+1,table.getn(self.transportRouteDots) do self.transportRouteDots[i]:Hide() end
end
function M:RenderTransports()
    if not self.layers or not self.layers.transit then return end
    self:RenderTransportRoutes()
    local visible=zMapDB.transportsEnabled and self.view.space=="world"
    local groups={};local now=self:TransportNow();local span=math.max(self.view.width,self.view.height)/self.view.scale
    if visible then
        for _,route in ipairs(self.transportRoutes) do for _,stop in ipairs(route.stops) do
            local x,y=self:ToScreen(stop.x,stop.y)
            if x>=10 and y>=10 and x<=self.view.width-10 and y<=self.view.height-10 then
                local group
                for _,g in ipairs(groups) do if (g.sx-x)^2+(g.sy-y)^2<32^2 then group=g;break end end
                if not group then group={x=stop.x,y=stop.y,sx=x,sy=y,kind=route.kind,stops={}};table.insert(groups,group) end
                table.insert(group.stops,stop)
            end
        end end
    end
    local labels={}
    for i,group in ipairs(groups) do
        local marker=self.transportDockMarkers[i]
        if not marker then marker=self:MakeTransportMarker();self.transportDockMarkers[i]=marker end
        marker.vehicle=nil;marker.stops=group.stops
        local path=PREFIX..(group.kind=="zeppelin" and "Zeppelin" or "Boat")
        if marker.path~=path then marker.icon:SetTexture(path);marker.path=path end
        marker.icon:SetVertexColor(.72,.78,.81,.92)
        local size=span>20000 and 13 or 18;marker:SetWidth(size);marker:SetHeight(size)
        self:PlaceMarker(marker,group.x,group.y,"world")
        local show=zMapDB.transportTimers and span<14000 and group.sx<self.view.width-215
        if show then
            for _,label in ipairs(labels) do if math.abs(label.x-group.sx)<215 and math.abs(label.y-group.sy)<20 then show=false;break end end
        end
        if show then
            local stop=group.stops[1];local status,seconds=self:TransportStopStatus(stop,now)
            local value=seconds and ((status=="arriving" and "~" or "leaves ~")..clock(seconds)) or self:TransportStatusText(stop)
            local destination=stop.route.stops[stop.index==1 and 2 or 1]
            local name=destination and string.gsub(destination.name,"%s*%b()","") or ""
            marker.destination=name
            if string.len(name)>20 then name=string.sub(name,1,18)..".." end
            value=name.." "..value
            if table.getn(group.stops)>1 then value=value.." (+"..(table.getn(group.stops)-1)..")" end
            marker.label:SetText(value);marker.label:Show();table.insert(labels,{x=group.sx,y=group.sy})
        else marker.label:Hide() end
    end
    for i=table.getn(groups)+1,table.getn(self.transportDockMarkers) do self.transportDockMarkers[i]:Hide() end
    self:RenderTransportVehicles()
    if self.hoveredTransport then self:ShowTransportTooltip(self.hoveredTransport) end
end
function M:RenderTransportVehicles()
    if not self.layers or not self.layers.transit then return end
    local visible=zMapDB.transportsEnabled and self.view.space=="world";local now=self:TransportNow()
    self.transportVehicleByEntry=self.transportVehicleByEntry or {}
    if visible then for _,route in ipairs(self.transportRoutes) do
        local live=self:TransportVehiclePose(route,now)
        local marker=self.transportVehicleByEntry[route.entry]
        if live then
            if not marker then
                marker=self:MakeTransportMarker();self.transportVehicleByEntry[route.entry]=marker
                table.insert(self.transportVehicleMarkers,marker)
            end
            marker.vehicle=live;marker.stops=nil;marker.label:Hide()
            local path=PREFIX..(route.kind=="zeppelin" and "Zeppelin" or "Boat")
            if marker.path~=path then marker.icon:SetTexture(path);marker.path=path end
            if live.source=="estimated" then
                marker.icon:SetVertexColor(.65,.7,.75,.72);marker.badge:SetText("~");marker.badge:SetTextColor(.85,.9,.95);marker.badge:Show()
            elseif live.source=="shared" then
                marker.icon:SetVertexColor(.6,.86,1,1);marker.badge:SetText("+");marker.badge:SetTextColor(.4,.8,1);marker.badge:Show()
            else marker.icon:SetVertexColor(1,1,1,1);marker.badge:Hide() end
            marker:SetWidth(25);marker:SetHeight(25)
            marker:SetFrameLevel(self.layers.transit:GetFrameLevel()+1)
            self:PlaceMarker(marker,live.x,live.y,"world")
        elseif marker then marker:Hide() end
    end end
    if not visible then for _,marker in ipairs(self.transportVehicleMarkers) do marker:Hide() end end
end
function M:FocusTransport(route)
    local stop=route.stops[1];zMapDB.follow=false;self.animation=nil;self.focus=nil
    self.view.space="world";self.view.x=stop.x;self.view.y=stop.y;self.view.scale=.35;self:Constrain();self.dirty=true
end
function M:LayoutTransportPanel()
    if not self.transportPanel then return end
    self.transportVisibleRows=self.Clamp(math.floor((self.frame:GetHeight()-262)/42),4,8)
    self.transportPanel:SetHeight(150+self.transportVisibleRows*42);self:RefreshTransportPanel()
end
function M:RefreshTransportPanel()
    if not self.transportPanel then return end
    self.transportMaster.label:SetText(zMapDB.transportsEnabled and "Transit: on" or "Transit: off")
    self.transportRouteButton.label:SetText(zMapDB.transportRoutes and "Routes: on" or "Routes: off")
    self.transportTimerButton.label:SetText(zMapDB.transportTimers and "Timers: on" or "Timers: off")
    self.transportPredictButton.label:SetText(zMapDB.transportPredict and "Predict: on" or "Predict: off")
    self.transportRecordButton.label:SetText(zMapDB.transportRecord and "Record: on" or "Record: off")
    self.transportShareButton.label:SetText(zMapDB.transportSharing and "Share: on" or "Share: off")
    self.transportStatusLabel:SetText((self.transportProviderReady and "Reader ready. " or "No live reader. Dock schedules still work. ").."Sharing: "..self:TransportSharingStatus())
    local visible=self.transportVisibleRows or 6
    self.transportOffset=self.Clamp(self.transportOffset or 0,0,math.max(0,table.getn(self.transportRoutes)-visible))
    for i,row in ipairs(self.transportRows) do
        local route=i<=visible and self.transportRoutes[self.transportOffset+i] or nil;row.route=route
        if route then
            row.label:SetText(route.name)
            row.status:SetText(self:TransportStatusText(route.stops[1]).." / "..self:TransportStatusText(route.stops[2]));row:Show()
        else row:Hide() end
    end
end
function M:BuildTransportUI(anchor,button,text,surface)
    local panel=CreateFrame("Frame",nil,self.frame);self.transportPanel=panel
    panel:SetWidth(430);panel:SetPoint("TOPRIGHT",self.frame,"TOPRIGHT",-10,-76)
    panel:SetFrameLevel(self.frame:GetFrameLevel()+42);panel:EnableMouse(true);panel:EnableMouseWheel(true);surface(panel)
    text(panel,"Zeppelins & boats",12,-12,350,true)
    local close=button(panel,"X",24,function() panel:Hide() end);close:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-8,-8)
    self.transportMaster=button(panel,"Transit: on",116,function()
        zMapDB.transportsEnabled=not zMapDB.transportsEnabled
        if zMapDB.transportsEnabled then self.transportQueryAt=self:TransportNow()+1;self:SampleTransports() else self:ClearTransportObservations() end
        self:RenderTransports();self:RefreshTransportPanel()
    end);self.transportMaster:SetPoint("TOPLEFT",panel,"TOPLEFT",12,-40)
    self.transportRouteButton=button(panel,"Routes: on",116,function()
        zMapDB.transportRoutes=not zMapDB.transportRoutes;self:RenderTransports();self:RefreshTransportPanel()
    end);self.transportRouteButton:SetPoint("LEFT",self.transportMaster,"RIGHT",8,0)
    self.transportTimerButton=button(panel,"Timers: on",116,function()
        zMapDB.transportTimers=not zMapDB.transportTimers;self:RenderTransports();self:RefreshTransportPanel()
    end);self.transportTimerButton:SetPoint("LEFT",self.transportRouteButton,"RIGHT",8,0)
    self.transportPredictButton=button(panel,"Predict: on",116,function()
        zMapDB.transportPredict=not zMapDB.transportPredict;self:RenderTransports();self:RefreshTransportPanel()
    end);self.transportPredictButton:SetPoint("TOPLEFT",panel,"TOPLEFT",12,-70)
    self.transportRecordButton=button(panel,"Record: on",116,function()
        zMapDB.transportRecord=not zMapDB.transportRecord;self:RefreshTransportPanel()
    end);self.transportRecordButton:SetPoint("LEFT",self.transportPredictButton,"RIGHT",8,0)
    self.transportShareButton=button(panel,"Share: on",116,function() self:SetTransportSharing(not zMapDB.transportSharing) end)
    self.transportShareButton:SetPoint("LEFT",self.transportRecordButton,"RIGHT",8,0)
    self.transportStatusLabel=text(panel,"",12,-104,406)
    text(panel,"Bright: local. Blue +: shared. ~: estimated. Scroll services.",12,-124,406)
    self.transportRows={}
    for i=1,9 do
        local row=button(panel,"",406,function() end);row:SetHeight(39)
        row:SetPoint("TOPLEFT",panel,"TOPLEFT",12,-144-(i-1)*42)
        row.label:ClearAllPoints();row.label:SetPoint("TOPLEFT",row,"TOPLEFT",7,-5);row.label:SetWidth(392);row.label:SetJustifyH("LEFT")
        row.status=text(row,"",7,-22,392);row.status:SetTextColor(.65,.74,.8)
        row:SetScript("OnClick",function() if row.route then self:FocusTransport(row.route);panel:Hide() end end)
        row:SetScript("OnEnter",function() if row.route then self:ShowTransportTooltip(row) end end)
        row:SetScript("OnLeave",function() self:HideTransportTooltip(row) end)
        row:SetScript("OnHide",function() self:HideTransportTooltip(row) end)
        self.transportRows[i]=row
    end
    panel:SetScript("OnMouseWheel",function() self.transportOffset=(self.transportOffset or 0)-(arg1 or 0);self:RefreshTransportPanel() end)
    panel:SetScript("OnHide",function() self:HideTransportTooltip() end)
    self:LayoutTransportPanel();panel:Hide()
end
function M:ToggleTransportPanel()
    if not self.frame then self:BuildUI() end
    self.frame:Show()
    if self.transportPanel:IsShown() then self.transportPanel:Hide() else
        self.searchPanel:Hide();self.gatherPanel:Hide();self:RefreshTransportPanel();self.transportPanel:Show()
    end
end
