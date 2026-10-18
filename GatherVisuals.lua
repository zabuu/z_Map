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
    local size=3+14*t*t*(3-2*t)
    return size,alpha,size<=4.5
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
