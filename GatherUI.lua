local M=zMap
local labels=M.gatherLabels
local order={herbs=1,ore=2,fish=3,treasure=4}
function M:LayoutGatherPanel()
    if not self.gatherPanel then return end
    local rows=self.Clamp(math.floor((self.frame:GetHeight()-262)/21),4,12)
    if self.gatherVisibleRows==rows then return end
    self.gatherVisibleRows=rows;self.gatherPanel:SetHeight(180+rows*21)
    self.gatherCountLabel:ClearAllPoints();self.gatherCountLabel:SetPoint("TOPLEFT",self.gatherPanel,"TOPLEFT",12,-137-rows*21)
    self.gatherStatusLabel:ClearAllPoints();self.gatherStatusLabel:SetPoint("TOPLEFT",self.gatherPanel,"TOPLEFT",12,-157-rows*21)
    self:RefreshGatherPanel()
end
function M:RefreshGatherPanel()
    if not self.gatherPanel then return end
    self.gatherMaster.label:SetText(zMapDB.gatherEnabled and "Live: on" or "Live: off")
    self.gatherLoggedButton.label:SetText(zMapDB.gatherShowLogged and "Logged: on" or "Logged: off")
    self.gatherShareButton.label:SetText(zMapDB.gatherSharing and "Share: on" or "Share: off")
    for category,b in pairs(self.gatherCategoryButtons) do
        b.label:SetText((zMapDB.gatherCategories[category] and "|cff59d9c5" or "|cff777777")..labels[category].."|r")
    end
    local query=string.lower(self.gatherSearch:GetText() or "")
    local list={};self.gatherEnabledTypes=0
    for _,info in pairs(self.gatherDefinitions) do
        if self:GatherEnabled(info) then self.gatherEnabledTypes=self.gatherEnabledTypes+1 end
        if query=="" or string.find(string.lower(info.name),query,1,true) or string.find(string.lower(labels[info.category]),query,1,true) then table.insert(list,info) end
    end
    table.sort(list,function(a,b) if a.category~=b.category then return order[a.category]<order[b.category] end;return a.name<b.name end)
    self.gatherFiltered=list
    local visible=self.gatherVisibleRows or 12
    self.gatherOffset=self.Clamp(self.gatherOffset or 0,0,math.max(0,table.getn(list)-visible))
    for i,row in ipairs(self.gatherRows) do
        local info=i<=visible and list[self.gatherOffset+i] or nil;row.definition=info
        if info then
            local enabled=zMapDB.gatherFilters[info.key]~=false
            row.label:SetText((enabled and "|cff59d9c5[x]|r " or "|cff777777[ ]|r ")..info.name)
            row.category:SetText(labels[info.category]);row:Show()
        else row:Hide() end
    end
    self:RenderGatherMarkers()
end
function M:ResetGatherVisibility()
    zMapDB.gatherEnabled=true;zMapDB.gatherShowLogged=true
    for id in pairs(zMapDB.gatherFilters) do zMapDB.gatherFilters[id]=nil end
    for category in pairs(labels) do zMapDB.gatherCategories[category]=true end
    if not self.frame then self:BuildUI() end
    self.frame:Show();self.searchPanel:Hide();self.gatherPanel:Show()
    self.gatherOffset=0;self.gatherSearch:SetText("");self:SampleGather();self:RefreshGatherPanel()
    self:Print("Node visibility restored; logged locations kept.")
end
function M:BuildGatherUI(anchor,button,text,surface)
    local panel=CreateFrame("Frame",nil,self.frame);self.gatherPanel=panel
    panel:SetWidth(390);panel:SetHeight(432);panel:SetPoint("TOPRIGHT",anchor,"BOTTOMRIGHT",0,-5)
    panel:SetFrameLevel(self.frame:GetFrameLevel()+40);surface(panel,.035,.045,.06);panel:EnableMouse(true);panel:EnableMouseWheel(true)
    text(panel,"Gathering nodes",12,-12,270,true)
    local close=button(panel,"X",24,function() panel:Hide() end);close:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-8,-8)
    self.gatherMaster=button(panel,"Live: on",76,function()
        zMapDB.gatherEnabled=not zMapDB.gatherEnabled
        if zMapDB.gatherEnabled then self:SampleGather() else self:ClearGather("Live gathering is off") end
        self:RefreshGatherPanel()
    end);self.gatherMaster:SetPoint("TOPLEFT",panel,"TOPLEFT",12,-40)
    local all=button(panel,"All",44,function()
        for id in pairs(self.gatherDefinitions) do zMapDB.gatherFilters[id]=nil end
        for category in pairs(labels) do zMapDB.gatherCategories[category]=true end
        self:RefreshGatherPanel()
    end);all:SetPoint("LEFT",self.gatherMaster,"RIGHT",8,0)
    local none=button(panel,"None",48,function()
        for id in pairs(self.gatherDefinitions) do zMapDB.gatherFilters[id]=false end
        for category in pairs(labels) do zMapDB.gatherCategories[category]=false end
        self:RefreshGatherPanel()
    end);none:SetPoint("LEFT",all,"RIGHT",5,0)
    self.gatherLoggedButton=button(panel,"Logged: on",100,function()
        zMapDB.gatherShowLogged=not zMapDB.gatherShowLogged;self:RefreshGatherPanel()
    end);self.gatherLoggedButton:SetPoint("LEFT",none,"RIGHT",8,0)
    self.gatherShareButton=button(panel,"Share: on",68,function() self:SetGatherSharing(not zMapDB.gatherSharing) end)
    self.gatherShareButton:SetPoint("LEFT",self.gatherLoggedButton,"RIGHT",8,0)
    self.gatherShareButton:SetScript("OnEnter",function()
        self.gatherShareTooltip=true
        GameTooltip:SetOwner(self.gatherShareButton,"ANCHOR_RIGHT");GameTooltip:SetText("Shared node locations")
        GameTooltip:AddLine("Sharing: "..self:GatherSharingStatus(),.7,.76,.82)
        GameTooltip:AddLine("Shared sites stay gray until you detect them.",.7,.76,.82);GameTooltip:Show()
    end)
    self.gatherShareButton:SetScript("OnLeave",function() self.gatherShareTooltip=nil;GameTooltip:Hide() end)
    self.gatherShareButton:SetScript("OnHide",function() if self.gatherShareTooltip then self.gatherShareTooltip=nil;GameTooltip:Hide() end end)
    self.gatherCategoryButtons={}
    local previous
    for _,category in ipairs({"herbs","ore","fish","treasure"}) do
        local name=category
        local b=button(panel,labels[category],86,function()
            zMapDB.gatherCategories[name]=not zMapDB.gatherCategories[name];self:RefreshGatherPanel()
        end)
        self.gatherCategoryButtons[category]=b
        if previous then b:SetPoint("LEFT",previous,"RIGHT",6,0) else b:SetPoint("TOPLEFT",panel,"TOPLEFT",12,-70) end
        previous=b
    end
    local search=CreateFrame("EditBox",nil,panel);self.gatherSearch=search
    search:SetWidth(366);search:SetHeight(24);search:SetPoint("TOPLEFT",panel,"TOPLEFT",12,-101)
    search:SetFontObject(GameFontHighlightSmall);search:SetTextInsets(8,8,0,0);search:SetAutoFocus(false);surface(search,.055,.07,.09)
    local hint=text(search,"Filter resources...",8,-7,320)
    search:SetScript("OnTextChanged",function()
        if search:GetText()=="" then hint:Show() else hint:Hide() end
        self.gatherOffset=0;self:RefreshGatherPanel()
    end)
    search:SetScript("OnEscapePressed",function() search:ClearFocus();panel:Hide() end)
    self.gatherRows={}
    for i=1,12 do
        local row=button(panel,"",366,function() end);row:SetHeight(20)
        row:SetPoint("TOPLEFT",panel,"TOPLEFT",12,-132-(i-1)*21)
        row.label:ClearAllPoints();row.label:SetPoint("LEFT",row,"LEFT",5,0);row.label:SetWidth(270);row.label:SetHeight(14);row.label:SetJustifyH("LEFT")
        row.category=text(row,"",0,0,78);row.category:ClearAllPoints();row.category:SetPoint("RIGHT",row,"RIGHT",-5,0);row.category:SetJustifyH("RIGHT")
        row:SetScript("OnClick",function()
            local info=row.definition
            if info then
                local enabled=zMapDB.gatherFilters[info.key]==false
                zMapDB.gatherFilters[info.key]=enabled
                if enabled then zMapDB.gatherCategories[info.category]=true end
                self:RefreshGatherPanel()
            end
        end)
        self.gatherRows[i]=row
    end
    panel:SetScript("OnMouseWheel",function()
        self.gatherOffset=(self.gatherOffset or 0)-(arg1 or 0)*3;self:RefreshGatherPanel()
    end)
    panel:SetScript("OnHide",function() search:ClearFocus() end)
    self.gatherCountLabel=text(panel,"",12,-389,366)
    self.gatherStatusLabel=text(panel,"",12,-409,366)
    self:LayoutGatherPanel()
    panel:Hide()
end
function M:ToggleGatherPanel()
    if not self.frame then self:BuildUI() end
    if not self.frame:IsShown() then self.frame:Show() end
    if self.gatherPanel:IsShown() then self.gatherPanel:Hide() else
        self.searchPanel:Hide();self:RefreshGatherPanel();self.gatherPanel:Show()
    end
end
