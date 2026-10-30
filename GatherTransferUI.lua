local M=zMap
function M:RefreshGatherTransferUI()
    local panel=self.bulkPanel
    if not panel or not panel:IsShown() then return end
    local now=self:SyncNow()
    if now<(self.bulkNextUI or 0) then return end
    self.bulkNextUI=now+.1
    local status,progress=self:GatherTransferProgress()
    if self.bulkStatusText~=status then self.bulkStatusText=status;self.bulkStatusLabel:SetText(status) end
    progress=self.Clamp(progress,0,1)
    self.bulkProgress:SetWidth(math.max(1,progress*424))
    if progress>0 then self.bulkProgress:Show() else self.bulkProgress:Hide() end
    local session=self.bulkSession
    local offered=session and session.phase=="offered"
    if session then self.bulkSendButton:Disable() else self.bulkSendButton:Enable() end
    if offered then self.bulkAcceptButton:Show();self.bulkDeclineButton:Show() else self.bulkAcceptButton:Hide();self.bulkDeclineButton:Hide() end
    if session and not offered then self.bulkCancelButton:Show() else self.bulkCancelButton:Hide() end
end
function M:ShowGatherTransferPanel(target)
    if not self.frame then self:BuildUI() end
    self:RefreshGatherTransferRoster()
    if target then self.bulkTarget:SetText(target)
    elseif self.bulkTarget:GetText()=="" then
        local current=UnitName("target");current=self:GatherTransferPeer(current)
        if not current then for _,peer in pairs(self.bulkPeers) do if not current or peer<current then current=peer end end end
        if current then self.bulkTarget:SetText(current) end
    end
    self.bulkNextUI=0;self.bulkPanel:Show();self:RefreshGatherTransferUI()
end
function M:BuildGatherTransferUI(button,text,surface)
    local panel=CreateFrame("Frame","zMapNodeTransfer",UIParent);self.bulkPanel=panel
    panel:SetWidth(460);panel:SetHeight(312);panel:SetPoint("CENTER",UIParent,"CENTER",0,0)
    panel:SetFrameStrata("DIALOG");panel:SetFrameLevel(90);panel:EnableMouse(true)
    surface(panel,.035,.045,.06);panel:SetMovable(true);panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart",function() panel:StartMoving() end)
    panel:SetScript("OnDragStop",function() panel:StopMovingOrSizing() end)
    panel:SetScript("OnHide",function() self.bulkTarget:ClearFocus() end)
    text(panel,"Node database transfer",18,-18,380,true)
    local close=button(panel,"X",24,function() panel:Hide() end);close:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-10,-10)
    local help=text(panel,"Join the same party or raid. Both players need zMap 1.10.0 or later. The recipient must accept.",18,-48,424)
    help:SetHeight(40)
    text(panel,"Send your logged locations to:",18,-99,424)
    local target=CreateFrame("EditBox",nil,panel);self.bulkTarget=target
    target:SetWidth(250);target:SetHeight(28);target:SetPoint("TOPLEFT",panel,"TOPLEFT",18,-119)
    target:SetFontObject(GameFontHighlightSmall);target:SetTextInsets(8,8,0,0);target:SetAutoFocus(false);surface(target,.055,.07,.09)
    target:SetScript("OnEscapePressed",function() target:ClearFocus() end)
    self.bulkSendButton=button(panel,"Send database",164,function() target:ClearFocus();self:StartGatherTransfer(target:GetText()) end)
    self.bulkSendButton:SetPoint("LEFT",target,"RIGHT",10,0)
    self.bulkStatusLabel=text(panel,"",18,-166,424);self.bulkStatusLabel:SetHeight(40)
    local track=panel:CreateTexture(nil,"BACKGROUND");track:SetTexture(1,1,1,.12)
    track:SetWidth(424);track:SetHeight(5);track:SetPoint("TOPLEFT",panel,"TOPLEFT",18,-213)
    local progress=panel:CreateTexture(nil,"ARTWORK");self.bulkProgress=progress;progress:SetTexture(.35,.85,.77,1)
    progress:SetHeight(5);progress:SetPoint("TOPLEFT",track,"TOPLEFT",0,0)
    self.bulkAcceptButton=button(panel,"Accept",100,function() self:AcceptGatherTransfer() end)
    self.bulkAcceptButton:SetPoint("TOPLEFT",panel,"TOPLEFT",18,-231)
    self.bulkDeclineButton=button(panel,"Decline",100,function() self:CancelGatherTransfer("Offer declined") end)
    self.bulkDeclineButton:SetPoint("LEFT",self.bulkAcceptButton,"RIGHT",10,0)
    self.bulkCancelButton=button(panel,"Cancel transfer",134,function() self:CancelGatherTransfer() end)
    self.bulkCancelButton:SetPoint("TOPLEFT",panel,"TOPLEFT",18,-231)
    text(panel,"Merges locations and estimates. Existing data and settings stay intact.",18,-276,424)
    panel:SetScript("OnUpdate",function() self:RefreshGatherTransferUI() end)
    table.insert(UISpecialFrames,"zMapNodeTransfer");panel:Hide()
end
