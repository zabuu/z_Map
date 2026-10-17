-- Vanilla's dedicated custom channel reaches other users outside a group.
-- Only locations travel over it. Remote messages never assert live availability.
local M=zMap
local CHANNEL="zMapNodes31"
-- Plain chat rejects unescaped pipes as malformed color/link escapes.
local HEADER="ZMN1:"
local categories={h="herbs",o="ore",f="fish",t="treasure"}
local codes={herbs="h",ore="o",fish="f",treasure="t"}
local function hash(text)
    local value=0
    for i=1,string.len(text) do value=math.mod(value*33+string.byte(text,i),2147483647) end
    return value
end
local function integer(n) return n and n==math.floor(n) and n>=0 and n<=4294967295 end
local function coordinate(n) return n and n==n and math.abs(n)<100000 end
local function channelID()
    local id=GetChannelName and GetChannelName(CHANNEL)
    if type(id)=="number" and id>0 then return id end
end
function M:GatherWireRecord(record)
    return string.format("%.0f,%.0f,%.2f,%.2f,%.2f,%s",record.entry,record.map,
        record.worldX,record.worldY,record.worldZ,codes[record.category])
end
function M:GatherRecordHash(record) return hash(self:GatherWireRecord(record)) end
function M:GatherSharingStatus()
    if not zMapDB.gatherSharing then return "off" end
    if not self.gatherLog then return "log unavailable" end
    if self.gatherShareError then return "send failed; retrying" end
    if self.gatherShareWorld and channelID() then return "connected" end
    return "waiting to connect"
end
function M:InitializeGatherSync()
    if zMapDB.gatherSharing==nil then zMapDB.gatherSharing=true end
    self.gatherShareClock=0;self.gatherShareNext=0;self.gatherShareHello=0;self.gatherShareJoin=0
    self.gatherShareQueue={};self.gatherShareQueued={};self.gatherShareHeard={};self.gatherSharePeers={}
    self.gatherShareTokens=64;self.gatherShareSent=0;self.gatherShareReceived=0
    self.gatherShareError=nil
    self.gatherShareMaps={}
    for _,zone in ipairs(self.data.zones) do self.gatherShareMaps[zone.map]=true end
    if not self.gatherSyncFrame then
        local frame=CreateFrame("Frame");self.gatherSyncFrame=frame
        for _,name in ipairs({"PLAYER_ENTERING_WORLD","PLAYER_LEAVING_WORLD","CHAT_MSG_CHANNEL","CHAT_MSG_CHANNEL_NOTICE"}) do frame:RegisterEvent(name) end
        frame:SetScript("OnEvent",function()
            if not M.ready then return end
            if event=="PLAYER_ENTERING_WORLD" then
                M.gatherShareWorld=true;M.gatherShareJoin=M.gatherShareClock+5;M.gatherShareHello=0
            elseif event=="PLAYER_LEAVING_WORLD" then M.gatherShareWorld=false
            elseif event=="CHAT_MSG_CHANNEL" then M:ReceiveGatherShare(arg1,arg2,arg9)
            elseif event=="CHAT_MSG_CHANNEL_NOTICE" and type(arg9)=="string" and string.lower(arg9)==string.lower(CHANNEL) then
                M:HideGatherChannel()
            end
        end)
        -- This small driver stays active when the map window is closed.
        frame:SetScript("OnUpdate",function() if M.ready then M:UpdateGatherSync(arg1 or 0) end end)
    end
end
function M:HideGatherChannel()
    if ChatFrame_RemoveChannel then
        for i=1,(NUM_CHAT_WINDOWS or 7) do
            local frame=getglobal("ChatFrame"..i)
            if frame then ChatFrame_RemoveChannel(frame,CHANNEL) end
        end
    end
end
function M:SetGatherSharing(enabled)
    zMapDB.gatherSharing=enabled
    self.gatherShareQueue={};self.gatherShareQueued={};self.gatherShareSweep=nil
    self.gatherShareSweepAgain=nil;self.gatherHiddenChannel=nil;self.gatherShareError=nil
    if not enabled then
        if LeaveChannelByName then LeaveChannelByName(CHANNEL) end
    else
        self.gatherShareJoin=self.gatherShareClock;self.gatherShareHello=0
    end
    if self.gatherPanel then self:RefreshGatherPanel() end
end
function M:QueueGatherShare(location)
    if not zMapDB.gatherSharing or self.gatherShareQueued[location.id] then return end
    self.gatherShareQueued[location.id]=self.gatherShareClock;table.insert(self.gatherShareQueue,location)
end
function M:StartGatherShareSweep()
    -- Concurrent requests coalesce, and hearing a location suppresses duplicate
    -- broadcasts from the other peers responding to that request.
    if self.gatherShareSweep then self.gatherShareSweepAgain=true;return end
    self.gatherShareSweep={cursor=1,last=table.getn(self.gatherLogNodes),since=self.gatherShareClock}
    local name=UnitName("player") or ""
    self.gatherShareNext=math.max(self.gatherShareNext,self.gatherShareClock+.3+math.mod(hash(name),170)/100)
end
function M:TakeGatherShareRecord()
    for i=1,128 do
        if table.getn(self.gatherShareQueue)==0 then break end
        local node=table.remove(self.gatherShareQueue) -- Bound by the 20,000-location log.
        local queued=self.gatherShareQueued[node.id]
        self.gatherShareQueued[node.id]=nil
        if (self.gatherShareHeard[node.id] or -1)<queued then return node end
    end
    if table.getn(self.gatherShareQueue)>0 then return end
    local sweep=self.gatherShareSweep
    if not sweep then return end
    -- A fully duplicated log must not become a full-log walk in one frame.
    for i=1,128 do
        if sweep.cursor>sweep.last then
            self.gatherShareSweep=nil
            if self.gatherShareSweepAgain then self.gatherShareSweepAgain=nil;self:StartGatherShareSweep() end
            return
        end
        local node=self.gatherLogNodes[sweep.cursor];sweep.cursor=sweep.cursor+1
        if node and (self.gatherShareHeard[node.id] or -1)<sweep.since then return node end
    end
end
function M:SendGatherShare(message,id)
    local ok=pcall(SendChatMessage,message,"CHANNEL",nil,id)
    self.gatherShareError=not ok
    if ok then self.gatherShareSent=self.gatherShareSent+1 end
    self.gatherShareNext=self.gatherShareClock+(ok and 1 or 30)
    return ok
end
function M:UpdateGatherSync(elapsed)
    self.gatherShareClock=self.gatherShareClock+elapsed
    self.gatherShareTokens=math.min(64,self.gatherShareTokens+elapsed*16)
    if not zMapDB.gatherSharing or not self.gatherShareWorld or not self.gatherLog or not SendChatMessage then return end
    local now=self.gatherShareClock
    if now<self.gatherShareNext then return end
    local id=channelID()
    if not id then
        if now>=self.gatherShareJoin and JoinChannelByName then
            JoinChannelByName(CHANNEL);self:HideGatherChannel();self.gatherShareJoin=now+30
        end
        self.gatherShareNext=now+1;return
    end
    if self.gatherHiddenChannel~=id then self:HideGatherChannel();self.gatherHiddenChannel=id end
    if now>=self.gatherShareHello then
        local message=HEADER.."H:"..table.getn(self.gatherLogNodes)..":"..(self.gatherLogChecksum or 0)
        local ok=self:SendGatherShare(message,id)
        self.gatherShareHello=now+(ok and 180 or 30);return
    end
    local records={};local nodes={};local packed={};local length=string.len(HEADER)+2
    for i=1,3 do
        local node=self:TakeGatherShareRecord()
        if not node then break end
        if not packed[node.id] then
            local wire=self:GatherWireRecord(node.record)
            if length+string.len(wire)+1>230 then self:QueueGatherShare(node);break end
            packed[node.id]=true;table.insert(records,wire);table.insert(nodes,node);length=length+string.len(wire)+1
        end
    end
    if table.getn(records)==0 then self.gatherShareNext=now+.25;return end
    local ok=self:SendGatherShare(HEADER.."D:"..table.concat(records,";"),id)
    if ok then
        for _,node in ipairs(nodes) do self.gatherShareHeard[node.id]=now end
    else for _,node in ipairs(nodes) do self:QueueGatherShare(node) end end
end
function M:ReceiveGatherShare(message,sender,channel)
    if not self.ready or not zMapDB.gatherSharing or not self.gatherShareWorld or not self.gatherLog or
        type(channel)~="string" or string.lower(channel)~=string.lower(CHANNEL) or
        type(message)~="string" or string.len(message)>230 or
        (string.sub(message,1,5)~=HEADER and string.sub(message,1,5)~="ZMN1|") or
        type(sender)~="string" or string.len(sender)>64 or sender==UnitName("player") then return end
    -- Read legacy packets if a transport supplied one; never send that format.
    if string.sub(message,1,5)=="ZMN1|" then message=string.gsub(message,"|",":") end
    local now=self.gatherShareClock;local peer=self.gatherSharePeers[sender]
    if not peer then
        local count=0
        for name,other in pairs(self.gatherSharePeers) do
            if now-other.seen>600 then self.gatherSharePeers[name]=nil else count=count+1 end
        end
        if count>=128 then return end
        peer={seen=now,tokens=8};self.gatherSharePeers[sender]=peer
    end
    peer.tokens=math.min(8,peer.tokens+now-peer.seen);peer.seen=now
    if peer.tokens<1 or self.gatherShareTokens<1 then return end
    peer.tokens=peer.tokens-1;self.gatherShareTokens=self.gatherShareTokens-1
    if string.sub(message,6,7)=="H:" then
        local _,_,count,sum=string.find(message,"^ZMN1:H:(%d+):(%d+)$")
        count=tonumber(count);sum=tonumber(sum)
        if not count or count>20000 or not sum or sum>=2147483647 then return end
        if count~=table.getn(self.gatherLogNodes) or sum~=(self.gatherLogChecksum or 0) then
            -- One response per peer per minute, even if a peer repeats requests.
            if not peer.hello or now-peer.hello>=60 then
                peer.hello=now;self:StartGatherShareSweep()
                -- Reply with our summary too: the joining peer may own records
                -- we lack. The per-peer cooldown prevents a hello/reply loop.
                local delay=2+math.mod(hash(UnitName("player") or ""),200)/100
                self.gatherShareHello=math.min(self.gatherShareHello,now+delay)
            end
        end
        return
    end
    if string.sub(message,6,7)~="D:" then return end
    local changed=false;local records=0
    for wire in string.gfind(string.sub(message,8),"[^;]+") do
        records=records+1;if records>3 then break end
        local _,_,entry,map,x,y,z,code=string.find(wire,"^(%d+),(%d+),([%d%.%-]+),([%d%.%-]+),([%d%.%-]+),([hoft])$")
        entry=tonumber(entry);map=tonumber(map);x=tonumber(x);y=tonumber(y);z=tonumber(z)
        local category=categories[code]
        if integer(entry) and entry>0 and integer(map) and self.gatherShareMaps[map] and
            coordinate(x) and coordinate(y) and coordinate(z) and category then
            local info=self.gatherEntries[entry]
            if not info and table.getn(self.gatherLogNodes)<20000 then
                local title=category=="herbs" and "Herb" or category=="ore" and "Ore" or category=="fish" and "Fishing pool" or "Container"
                info={name=title.." #"..entry,category=category};self.gatherEntries[entry]=info
            end
            if info and info.category==category then
                local definition=self.gatherDefinitions[self:AddGatherDefinition(info)]
                local node,added=self:StoreGatherLocation(map,entry,definition,x,y,z)
                if node then
                    self.gatherShareHeard[node.id]=now
                    if added then node.record.shared=true;changed=true;self.gatherShareReceived=self.gatherShareReceived+1 end
                end
            end
        end
    end
    if changed then
        if self.gatherPanel and self.gatherPanel:IsShown() then self:RefreshGatherPanel() else self:RenderGatherMarkers() end
    end
end
