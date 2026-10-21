-- Plain textures keep circular swipes free of third-party cooldown numbers.
local M=zMap
local ROOT="Interface\\AddOns\\z_Map\\Media\\GatherVisuals33\\"
local dotColors={herbs={.4,1,.5},ore={1,.73,.3},fish={.3,.8,1},treasure={1,.88,.3}}
local grayDot={.6,.6,.6}
function M:GatherPresentation()
    local view=self.view;local span=math.max(view.width,view.height)/view.scale
    if span>=18000 then return end
    local alpha=1-self.Clamp((span-12500)/5500,0,1)
    local t=self.Clamp(math.log(4500/span)/math.log(5),0,1)
    if self==M then t=t^.7 end
    local size=3+14*t*t*(3-2*t)
    return size*(self.gatherIconScale or 1),alpha,size<=4.5
end
function M:BuildGatherVisuals(marker)
    marker.rim=marker:CreateTexture(nil,"BACKGROUND");marker.rim:SetPoint("CENTER",marker,"CENTER",0,0)
    marker.rim:SetTexture(ROOT.."GoldRing");marker.rim:SetVertexColor(1,.76,.25)
    marker.rim:Hide()
end
function M:UpdateGatherSwipe(marker,now)
    local fraction=not marker.live and not marker.dot and self:GetGatherCooldown(marker.node,now)
    if not fraction then if marker.swipe then marker.swipe:Hide() end;marker.swipeFrame=nil;return end
    if not marker.swipe then
        marker.swipe=marker:CreateTexture(nil,"OVERLAY");marker.swipe:SetPoint("CENTER",marker,"CENTER",0,0)
        marker.swipe:SetTexture(ROOT.."Swipe64");marker.swipe:SetVertexColor(.7,.82,1)
    end
    local index=math.ceil(fraction*63)
    if marker.swipeFrame~=index then
        local col,row=math.mod(index,8),math.floor(index/8)
        marker.swipe:SetTexCoord(col/8,(col+1)/8,row/8,(row+1)/8);marker.swipeFrame=index
    end
    local size=marker.visualSize+3
    if marker.swipeSize~=size then marker.swipe:SetWidth(size);marker.swipe:SetHeight(size);marker.swipeSize=size end
    marker.swipe:Show()
end
function M:StyleGatherMarker(marker,node,live,size,alpha,dot)
    if marker.visualSize~=size then
        marker:SetWidth(size);marker:SetHeight(size);marker.visualSize=size
        marker.rim:SetWidth(size+2);marker.rim:SetHeight(size+2)
    end
    if marker.visualAlpha~=alpha then marker:SetAlpha(alpha);marker.visualAlpha=alpha end
    local paths=live and zMapGatherData.icons or zMapGatherData.loggedIcons
    local entry=node.entry or node.record and node.record.entry
    local item=zMapGatherData.itemIcons and zMapGatherData.itemIcons[entry]
    local path=dot and "Interface\\AddOns\\z_Map\\Media\\GroupCircle" or
        item and (live and item.live or item.logged) or paths[node.definition.category]
    if marker.path~=path then marker.texture:SetTexture(path);marker.path=path end
    local color=dot and (live and dotColors[node.definition.category] or grayDot)
    local r,g,b=1,1,1
    if color then r,g,b=unpack(color) end
    if marker.colorR~=r or marker.colorG~=g or marker.colorB~=b then
        marker.texture:SetVertexColor(r,g,b);marker.colorR=r;marker.colorG=g;marker.colorB=b
    end
    marker.dot=dot
    if live then marker.rim:Show() else marker.rim:Hide() end
    self:UpdateGatherSwipe(marker,self:GatherTimerNow())
end
function M:UpdateGatherVisuals(elapsed)
    self.gatherVisualElapsed=(self.gatherVisualElapsed or 0)+elapsed
    if self.gatherVisualElapsed<.1 then return end
    self.gatherVisualElapsed=0
    local now=self:GatherTimerNow()
    for _,marker in pairs(self.gatherMarkers) do self:UpdateGatherSwipe(marker,now) end
end

-- Project only current native observations. History/shared records never enter
-- this pool, and camera motion never triggers another object-list scan.
M.worldGatherLimit=64
function M:ClearWorldGatherIcons()
    self.worldGatherShown=0;self.worldGatherCandidates=nil;self.worldGatherEpoch=nil
    if not self.worldGatherMarkers then return end
    for guid,marker in pairs(self.worldGatherMarkers) do
        marker:Hide();marker.node=nil;self.worldGatherMarkers[guid]=nil
        table.insert(self.worldGatherFree,marker)
    end
end
function M:SetWorldGatherIcons(enabled)
    zMapDB.gatherWorldIcons=enabled==true
    self:ClearWorldGatherIcons();self.worldGatherElapsed=.5;self.gatherElapsed=.5
    self:RefreshSettingsPanel()
end
local function finite(value) return type(value)=="number" and value==value and math.abs(value)<10000000 end
function M:UpdateWorldGatherIcons(elapsed)
    if not zMapDB.gatherWorldIcons or not zMapDB.gatherEnabled or not self.miniWorld or
        type(zAPI)~="function" or self.frame and self.frame:IsShown() or
        WorldMapFrame and WorldMapFrame:IsShown() then self:ClearWorldGatherIcons();return end
    local mini=self.miniContext and self.miniContext.frame:IsShown()
    local hud=self.hudContext and self.hudContext.frame:IsShown()
    if self.mapChanged then self:ClearWorldGatherIcons();self.worldGatherElapsed=.5 end
    if not mini and not hud then
        self.worldGatherElapsed=(self.worldGatherElapsed or .5)+elapsed
        if self.worldGatherElapsed>=.5 then
            self.worldGatherElapsed=0;self:SamplePlayer();self:SampleGather()
        end
    else self.worldGatherElapsed=0 end
    local now=GetTime and GetTime() or 0
    if not self.player or self.mapChanged or not self.gatherLiveAt or now-self.gatherLiveAt>.75 then
        self:ClearWorldGatherIcons();return
    end
    if self.worldGatherEpoch~=self.gatherEpoch then
        local list={}
        for _,node in ipairs(self.gatherNodes) do
            if self:GatherEnabled(node.definition) then table.insert(list,node) end
        end
        table.sort(list,function(a,b)
            if a.distance~=b.distance then return a.distance<b.distance end
            return a.guid<b.guid
        end)
        for i=table.getn(list),self.worldGatherLimit+1,-1 do list[i]=nil end
        self.worldGatherCandidates=list;self.worldGatherEpoch=self.gatherEpoch
    end
    self.worldGatherMarkers=self.worldGatherMarkers or {};self.worldGatherFree=self.worldGatherFree or {}
    self.worldGatherSerial=(self.worldGatherSerial or 0)+1
    local epoch=self.worldGatherSerial;local shown=0
    local width,height=UIParent:GetWidth(),UIParent:GetHeight()
    local worldScale=WorldFrame and WorldFrame:GetEffectiveScale() or UIParent:GetEffectiveScale()
    local uiScale=UIParent:GetEffectiveScale();local factor=uiScale>0 and worldScale/uiScale or 1
    for _,node in ipairs(self.worldGatherCandidates or {}) do
        local guid=node.guid;local marker=self.worldGatherMarkers[guid]
        local live=self.gatherByGUID[guid]==node and node.epoch==self.gatherEpoch and
            node.space==self.player.space and self:GatherEnabled(node.definition)
        if live and finite(node.worldX) and finite(node.worldY) and finite(node.z) then
            if marker then marker.worldEpoch=epoch end
            local ok,x,y,depth=pcall(zAPI,"worldToScreen",node.worldX,node.worldY,node.z+.35)
            if finite(x) and finite(y) then x=x*factor;y=y*factor end
            if ok and finite(x) and finite(y) and finite(depth) and depth>0 and x>=0 and x<=1 and y>=0 and y<=1 then
                if not marker then
                    marker=table.remove(self.worldGatherFree)
                    if not marker then
                        marker=CreateFrame("Frame",nil,UIParent);marker:SetFrameStrata("HIGH");marker:SetFrameLevel(30)
                        marker:EnableMouse(false);marker:EnableMouseWheel(false)
                        marker.texture=marker:CreateTexture(nil,"ARTWORK");marker.texture:SetAllPoints(marker)
                        self:BuildGatherVisuals(marker)
                    end
                    self.worldGatherMarkers[guid]=marker
                end
                if marker.node~=node or marker.worldEntry~=node.entry then
                    marker.node=node;marker.live=true;marker.worldEntry=node.entry
                    self:StyleGatherMarker(marker,node,true,22,.9,false)
                end
                local sx,sy=x*width,y*height
                if marker.worldX~=sx or marker.worldY~=sy then
                    marker:ClearAllPoints();marker:SetPoint("BOTTOM",UIParent,"BOTTOMLEFT",sx,sy)
                    marker.worldX=sx;marker.worldY=sy
                end
                marker.worldEpoch=epoch
                if not marker:IsShown() then marker:Show() end
                shown=shown+1
            elseif marker then marker:Hide() end
        end
    end
    for guid,marker in pairs(self.worldGatherMarkers) do
        if marker.worldEpoch~=epoch then
            marker:Hide();marker.node=nil;self.worldGatherMarkers[guid]=nil;table.insert(self.worldGatherFree,marker)
        end
    end
    self.worldGatherShown=shown
end
