-- Custom channels share the player's normal chat allowance. One budget for all
-- zMap senders, no catch-up bursts, and player chat always gets priority.
local M=zMap
local function channelName(channel)
    if type(channel)~="string" then return end
    channel=string.gsub(string.lower(channel),"^%s*%d+%.%s*","")
    return string.gsub(channel,"^%s*(.-)%s*$","%1")
end
function M:SyncChannelName(channel) return channelName(channel) end
function M:SyncEventChannel()
    local channel=channelName(arg9)
    if channel and channel~="" then return channel end
    channel=channelName(arg4)
    if channel and channel~="" then return channel end
    if type(arg8)=="number" and arg8>0 and GetChannelName then
        for _,name in ipairs({"zMapNodes31","zMapTransit15"}) do
            if GetChannelName(name)==arg8 then return string.lower(name) end
        end
    end
end
local function ownPacket(message,channel)
    if type(message)~="string" then return false end
    if type(channel)=="number" and channel>0 and GetChannelName then
        if channel==GetChannelName("zMapNodes31") then channel="zmapnodes31"
        elseif channel==GetChannelName("zMapTransit15") then channel="zmaptransit15" end
    end
    channel=channelName(channel)
    return channel=="zmapnodes31" and string.sub(message,1,5)=="ZMN1:" or
        channel=="zmaptransit15" and string.sub(message,1,5)=="ZMT1:"
end
function M:SyncNow() return GetTime and GetTime() or self.gatherShareClock or 0 end
function M:SyncChatActivity(reason)
    self.syncQuietUntil=math.max(self.syncQuietUntil or 0,self:SyncNow()+30)
    self.syncQuietReason=reason or "outgoing chat"
end
local function method(frame,name)
    local ok,value=pcall(function() return frame[name] end)
    if ok and type(value)=="function" then return value end
end
function M:WatchSyncInput()
    local edit=ChatFrameEditBox
    if self.syncEditBox==edit then return end
    self.syncEditBox=edit;self.syncEditKnown=nil;self.syncEditFocused=nil
    if not edit then return end
    self.syncEditFocus=method(edit,"HasFocus")
    self.syncEditVisible=method(edit,"IsVisible") or method(edit,"IsShown")
    self.syncEditText=method(edit,"GetText")
    if method(edit,"GetScript") and method(edit,"SetScript") then
        for _,name in ipairs({"OnEditFocusGained","OnEditFocusLost"}) do
            local focused=name=="OnEditFocusGained";local previous=edit:GetScript(name)
            edit:SetScript(name,function(...)
                if M.syncEditBox==edit then M.syncEditKnown=true;M.syncEditFocused=focused end
                if previous then return previous(unpack(arg,1,arg.n)) end
            end)
        end
    end
end
function M:SyncInputActive()
    self:WatchSyncInput()
    local edit=self.syncEditBox
    if not edit then return false end
    if self.syncEditVisible and not self.syncEditVisible(edit) then return false end
    if self.syncEditFocus then
        local ok,focused=pcall(self.syncEditFocus,edit)
        if ok then return focused and focused~=0 end
        self.syncEditFocus=nil
    end
    -- Vanilla can track focus through its native edit scripts. A skin leaving
    -- an idle box shown is not evidence that the player is composing a message.
    if self.syncEditKnown then return self.syncEditFocused end
    local text=self.syncEditText and self.syncEditText(edit)
    return type(text)=="string" and string.find(text,"%S")~=nil
end
function M:HookSyncChat()
    self:WatchSyncInput()
    if self.syncChatHook or type(SendChatMessage)~="function" then return end
    local original=SendChatMessage
    local hook=function(message,kind,language,target)
        if not M.syncSending then
            if kind=="CHANNEL" and ownPacket(message,target) then
                -- A wrapper may release an earlier packet after our send guard
                -- has ended. Count its actual send without treating it as chat.
                M.syncNext=math.max(M.syncNext,M:SyncNow()+M.syncInterval)
            else M:SyncChatActivity() end
        end
        return original(message,kind,language,target)
    end
    self.syncChatHook=hook;SendChatMessage=hook
end
function M:SyncThrottle(message)
    if type(message)~="string" then return end
    local text=string.lower(message)
    local _,_,seconds=string.find(text,"you must wait%s+(%d+)%s+seconds?%s+before speaking again")
    if not seconds and message~=ERR_CHAT_THROTTLED and text~="throttled" then return end
    local now=self:SyncNow();local wait=math.min(3600,tonumber(seconds) or 0)
    if not self.syncLastThrottle or now-self.syncLastThrottle>2 then
        if not self.syncLastThrottle or now-self.syncLastThrottle>900 then self.syncPenalty=30 end
        self.syncPenalty=math.min(600,(self.syncPenalty or 30)*2)
        self.syncInterval=math.min(120,self.syncInterval*2)
    end
    self.syncLastThrottle=now
    self.syncBlockedUntil=math.max(self.syncBlockedUntil,now+math.max(wait+30,self.syncPenalty))
    self.syncBlockReason="paused: server throttle"
    -- A normal API return is not a server acknowledgment. Put a just-rejected
    -- packet back into its owner's work, then rebuild it after the quiet period.
    local last=self.syncLastPacket
    if last and now-last.at<=5 and not last.rejected then
        last.rejected=true
        if last.sent and last.retry then last.retry() end
    end
end
function M:InitializeSync()
    local now=self:SyncNow()
    self.syncInterval=15;self.syncNext=now+20;self.syncQuietUntil=0;self.syncBlockedUntil=0
    self.syncPending={};self.syncWorld=false
    local frame=CreateFrame("Frame");self.syncFrame=frame
    for _,name in ipairs({"PLAYER_ENTERING_WORLD","PLAYER_LEAVING_WORLD","UI_ERROR_MESSAGE","CHAT_MSG_SYSTEM","CHAT_MSG_CHANNEL_NOTICE",
        "CHAT_MSG_SAY","CHAT_MSG_YELL","CHAT_MSG_EMOTE","CHAT_MSG_TEXT_EMOTE","CHAT_MSG_PARTY","CHAT_MSG_RAID",
        "CHAT_MSG_RAID_LEADER","CHAT_MSG_GUILD","CHAT_MSG_OFFICER","CHAT_MSG_WHISPER_INFORM","CHAT_MSG_CHANNEL"}) do frame:RegisterEvent(name) end
    frame:SetScript("OnEvent",function()
        if not M.ready then return end
        if event=="PLAYER_ENTERING_WORLD" then
            M.syncWorld=true;M.syncNext=math.max(M.syncNext,M:SyncNow()+20);M.syncPending={};M:HookSyncChat()
        elseif event=="PLAYER_LEAVING_WORLD" then M.syncWorld=false;M.syncPending={}
        elseif event=="UI_ERROR_MESSAGE" or event=="CHAT_MSG_SYSTEM" or event=="CHAT_MSG_CHANNEL_NOTICE" then M:SyncThrottle(arg1)
        elseif arg2==UnitName("player") and not ownPacket(arg1,M:SyncEventChannel()) then M:SyncChatActivity("own chat echo") end
    end)
    self:HookSyncChat()
end
function M:SyncIdle(owner) self.syncPending[owner]=nil end
function M:SyncPauseStatus()
    local now=self:SyncNow()
    if now<self.syncBlockedUntil then return self.syncBlockReason end
    if now<self.syncQuietUntil then return "paused for chat" end
end
function M:CanSyncSend(owner)
    local now=self:SyncNow();local pending=self.syncPending[owner]
    if not pending or now-pending.last>2 then pending={since=now};self.syncPending[owner]=pending end
    pending.last=now
    if self:SyncInputActive() then self:SyncChatActivity("typing in chat") end
    if not self.syncWorld or now<self.syncNext or self:SyncPauseStatus() then return false end
    -- Oldest waiting sender wins. Idle/disabled senders expire rather than
    -- reserving slots indefinitely; a full node history cannot starve transit.
    for name,other in pairs(self.syncPending) do
        if name~=owner and now-other.last<=2 and
            (other.since<pending.since or other.since==pending.since and name<owner) then return false end
    end
    return true
end
function M:SyncWaitText()
    local now=self:SyncNow()
    if not self.syncWorld then return "Waiting to enter the world." end
    if now<self.syncBlockedUntil then return (self.syncBlockReason or "server backoff").." ("..math.ceil(self.syncBlockedUntil-now).."s)." end
    if self:SyncInputActive() then return "Typing in chat; outbound sharing waits." end
    if now<self.syncQuietUntil then return "Chat quiet period: "..math.ceil(self.syncQuietUntil-now).."s ("..(self.syncQuietReason or "chat")..")." end
    if now<self.syncNext then return "Next shared send slot in "..math.ceil(self.syncNext-now).."s." end
    return "Outbound send budget ready."
end
function M:SyncStatus()
    self:Print("Node sharing: "..self:GatherSharingStatus().." | channel "..tostring(GetChannelName and GetChannelName("zMapNodes31") or 0)..
        " | "..self:GatherSharePeerCount().." peers heard recently.")
    self:Print(self:SyncWaitText().." "..self:GatherShareReceiveText())
    self:Print("Node packets: "..(self.gatherShareSent or 0).." sent via API, "..(self.gatherSharePacketsReceived or 0)..
        " received | "..(self.gatherShareReceived or 0).." new locations received | "..self:GatherShareBacklog()..".")
end
function M:SendSyncMessage(owner,message,kind,target,retry)
    if not self:CanSyncSend(owner) then return end
    local now=self:SyncNow();self.syncNext=now+self.syncInterval;self:SyncIdle(owner)
    local packet={at=now,retry=retry};self.syncLastPacket=packet
    self.syncSending=true
    local ok=pcall(SendChatMessage,message,kind,nil,target)
    self.syncSending=nil
    if not ok then
        self.syncBlockedUntil=math.max(self.syncBlockedUntil,now+30);self.syncBlockReason="send failed; retrying"
    end
    if not ok or packet.rejected then return false end
    packet.sent=true;return true
end
