-- Custom channels share the player's normal chat allowance. One budget for all
-- zMap senders, no catch-up bursts, and player chat always gets priority.
local M=zMap
local function ownPacket(message,channel)
    if type(message)~="string" or type(channel)~="string" then return false end
    channel=string.lower(channel)
    return channel=="zmapnodes31" and string.sub(message,1,5)=="ZMN1:" or
        channel=="zmaptransit15" and string.sub(message,1,5)=="ZMT1:"
end
function M:SyncNow() return GetTime and GetTime() or self.gatherShareClock or 0 end
function M:SyncChatActivity()
    self.syncQuietUntil=math.max(self.syncQuietUntil or 0,self:SyncNow()+30)
end
function M:HookSyncChat()
    if self.syncChatHook or type(SendChatMessage)~="function" then return end
    local original=SendChatMessage
    local hook=function(message,kind,language,target)
        if not M.syncSending then M:SyncChatActivity() end
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
        elseif arg2==UnitName("player") and not ownPacket(arg1,arg9) then M:SyncChatActivity() end
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
    if ChatFrameEditBox and ChatFrameEditBox.IsShown and ChatFrameEditBox:IsShown() then self:SyncChatActivity() end
    if not self.syncWorld or now<self.syncNext or self:SyncPauseStatus() then return false end
    -- Oldest waiting sender wins. Idle/disabled senders expire rather than
    -- reserving slots indefinitely; a full node history cannot starve transit.
    for name,other in pairs(self.syncPending) do
        if name~=owner and now-other.last<=2 and
            (other.since<pending.since or other.since==pending.since and name<owner) then return false end
    end
    return true
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
