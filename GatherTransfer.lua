-- Explicit, acknowledged party/raid transfer. Never uses normal chat.
local M=zMap;local C=M.bulkCodec
local PREFIX="ZMapDB1";local GAP=.25;local WINDOW=8
local function number(n,limit) return type(n)=="number" and n==math.floor(n) and n>=0 and n<=limit end
local function clean(n,limit) return type(n)=="string" and string.len(n)>0 and string.len(n)<=limit and not string.find(n,"[%z\1-\32\127:|]") end
local function realm() return GetRealmName and GetRealmName() or "OctoWoW" end
local function count(t) return table.getn(t or {}) end
function M:RefreshGatherTransferRoster()
    local peers={};local channel
    local raids=GetNumRaidMembers and GetNumRaidMembers() or 0
    local party=GetNumPartyMembers and GetNumPartyMembers() or 0
    if raids>0 then channel="RAID" elseif party>0 then channel="PARTY" end
    local me=UnitName("player")
    for i=1,(raids>0 and raids or party) do
        local name=UnitName((raids>0 and "raid" or "party")..i)
        if clean(name,48) and name~=me then peers[string.lower(name)]=name end
    end
    self.bulkPeers=peers;self.bulkChannel=channel;self.bulkRosterDirty=nil
    for name in pairs(self.bulkOfferAfter) do if not peers[string.lower(name)] then self.bulkOfferAfter[name]=nil end end
    local s=self.bulkSession
    if s and (channel~=s.channel or not peers[string.lower(s.peer)]) then self:CancelGatherTransfer("Group changed") end
end
function M:GatherTransferPeer(name)
    if self.bulkRosterDirty then self:RefreshGatherTransferRoster() end
    return type(name)=="string" and self.bulkPeers[string.lower(name)]
end
function M:QueueGatherTransferControl(kind,s,body)
    local text=kind..":"..s.peer..":"..s.id..(body and ":"..body or "")
    if string.len(text)>240 then return end
    for _,p in ipairs(self.bulkControls) do
        if p.kind==kind and p.id==s.id and p.peer==s.peer then p.text=text;return end
    end
    if count(self.bulkControls)>=8 then return end
    table.insert(self.bulkControls,{kind=kind,id=s.id,peer=s.peer,channel=s.channel,text=text,expires=self:SyncNow()+30,tries=0})
    self.bulkDriver:Show()
end
function M:CancelGatherTransfer(reason,notify)
    local s=self.bulkSession
    if s then
        for i=count(self.bulkControls),1,-1 do if self.bulkControls[i].id==s.id then table.remove(self.bulkControls,i) end end
    end
    if s and notify~=false then self:QueueGatherTransferControl("C",s) end
    self.bulkSession=nil;self.bulkStatus=reason or "Transfer canceled"
    if s and s.added and s.added>0 then self.bulkStatus=self.bulkStatus.."; "..s.added.." merged locations retained";self.dirty=true end
    self:RefreshGatherTransferUI()
end
function M:StartGatherTransfer(target)
    if self.bulkSession then self:Print("Finish or cancel the current node transfer first.");return false end
    if not self.bulkInWorld then self:Print("Wait until loading finishes before transferring nodes.");return false end
    self:RefreshGatherTransferRoster()
    target=type(target)=="string" and string.gsub(target,"^%s*(.-)%s*$","%1") or ""
    target=self:GatherTransferPeer(target)
    if not target or not self.bulkChannel then self:Print("Choose someone in your party or raid for a fast node transfer.");return false end
    if type(SendAddonMessage)~="function" or not self.gatherLog then self:Print("Addon messages or the node log are unavailable.");return false end
    self.bulkSerial=self.bulkSerial+1
    local now=self:SyncNow();local id=math.mod(math.floor(now*100),1000000000).."."..math.mod(self.bulkSerial,1000)
    self.bulkSession={direction="send",phase="prepare",peer=target,id=id,channel=self.bulkChannel,
        cursor=1,last=math.min(C.limit,count(self.gatherLogNodes)),count=0,skipped=0,keys={},defs={},records={},progressAt=now}
    self.bulkStatus="Preparing node snapshot";self.bulkDriver:Show();self:RefreshGatherTransferUI();return true
end
function M:AcceptGatherTransfer()
    local s=self.bulkSession
    if not s or s.direction~="receive" or s.phase~="offered" then return end
    if not self.gatherLog then self:CancelGatherTransfer("Node log unavailable; cannot import");return end
    s.phase="receiving";s.chunks={};s.received=0;s.bytesReceived=0;s.progressAt=self:SyncNow()
    self:QueueGatherTransferControl("A",s);self:RefreshGatherTransferUI()
end
function M:GatherTransferProgress()
    local s=self.bulkSession
    if not s then return self.bulkStatus or "No transfer active",0 end
    local prefix=s.direction=="send" and "To " or "From "
    if s.phase=="prepare" then return "Preparing "..(s.cursor-1).." / "..s.last.." nodes",(s.cursor-1)/math.max(1,s.last) end
    if s.phase=="hash" then return "Checking outgoing snapshot",0 end
    if s.phase=="offer" then return prefix..s.peer..": waiting for acceptance",0 end
    if s.phase=="offered" then return s.peer.." offers "..s.count.." locations ("..math.ceil(s.bytes/1024).." KB)",0 end
    if s.phase=="sending" then return prefix..s.peer..": "..s.acked.." / "..s.parts.." packets confirmed",s.acked/s.parts end
    if s.phase=="receiving" then return prefix..s.peer..": "..s.received.." / "..s.parts.." packets received",s.received/s.parts end
    if s.phase=="checking" or s.phase=="decoding" then return "Validating complete snapshot from "..s.peer,1 end
    if s.phase=="import" then return "Merging "..(s.cursor-1).." / "..s.count.." locations",(s.cursor-1)/math.max(1,s.count) end
    return "Waiting for "..s.peer.." to finish importing",1
end
function M:ReceiveGatherTransfer(prefix,text,channel,sender)
    if not self.ready or not self.bulkInWorld or prefix~=PREFIX or (channel~="PARTY" and channel~="RAID") or
        type(text)~="string" or string.len(text)>240 or type(sender)~="string" then return end
    local peer=self:GatherTransferPeer(sender)
    if not peer or channel~=self.bulkChannel then return end
    local _,_,kind,target,id,body=string.find(text,"^([OADKECF]):([^:]+):([%d%.]+):?(.*)$")
    if not kind or string.len(id)>14 or not string.find(id,"^%d+%.%d+$") or
        string.lower(target)~=string.lower(UnitName("player") or "") then return end
    local now=self:SyncNow();local s=self.bulkSession
    if kind=="O" then
        local _,_,n,bytes,parts,sum,origin=string.find(body,"^(%d+):(%d+):(%d+):(%d+):(.+)$")
        n,bytes,parts,sum=tonumber(n),tonumber(bytes),tonumber(parts),tonumber(sum)
        if not number(n,C.limit) or not number(bytes,C.maxBytes) or bytes<10 or not number(sum,4294967295) or
            not number(parts,math.ceil(C.maxBytes/C.chunk)) or parts~=math.ceil(bytes/C.chunk) or origin~=realm() then return end
        if s then
            if s.direction=="receive" and s.peer==peer and s.id==id and s.phase=="receiving" then self:QueueGatherTransferControl("A",s) end
            return
        end
        if now<(self.bulkOfferAfter[peer] or 0) then return end
        self.bulkOfferAfter[peer]=now+10
        self.bulkSession={direction="receive",phase="offered",peer=peer,id=id,channel=channel,count=n,bytes=bytes,parts=parts,
            expectedChecksum=sum,deadline=now+30,progressAt=now}
        self.bulkDriver:Show();self:ShowGatherTransferPanel();return
    end
    if not s or s.peer~=peer or s.id~=id or s.channel~=channel then
        local last=self.bulkReceipt
        if kind=="E" and last and last.peer==peer and last.id==id and now<last.expires then self:QueueGatherTransferControl("F",last,last.result) end
        return
    end
    if kind=="C" then self:CancelGatherTransfer("Other player canceled the transfer",false);return end
    if s.direction=="send" then
        if kind=="A" and s.phase=="offer" then
            s.phase="sending";s.acked=0;s.nextSeq=1;s.highest=0;s.retries=0;s.progressAt=now
        elseif kind=="K" and s.phase=="sending" then
            local ack=tonumber(body)
            if number(ack,s.highest) and ack>s.acked then s.acked=ack;s.progressAt=now;s.retries=0 end
        elseif kind=="F" and s.phase=="finish" then
            local _,_,added,duplicates,skipped=string.find(body,"^(%d+):(%d+):(%d+)$")
            added,duplicates,skipped=tonumber(added),tonumber(duplicates),tonumber(skipped)
            if number(added,s.count) and number(duplicates,s.count) and number(skipped,s.count) and added+duplicates+skipped==s.count then
                self.bulkStatus=s.peer.." imported "..added.." new locations; "..duplicates.." duplicates, "..skipped.." skipped"
                self.bulkSession=nil
            end
        end
    elseif kind=="D" and s.phase=="receiving" then
        local _,_,seq,encoded=string.find(body,"^(%d+):([%w_=%-]+)$");seq=tonumber(seq)
        if not number(seq,s.parts) or seq<1 or not encoded then return end
        if seq~=s.received+1 then self:QueueGatherTransferControl("K",s,tostring(s.received));return end
        local raw=C.Decode(encoded)
        local expected=seq==s.parts and s.bytes-(seq-1)*C.chunk or C.chunk
        if not raw or string.len(raw)~=expected then self:CancelGatherTransfer("Invalid transfer packet");return end
        s.chunks[seq]=raw;s.received=seq;s.bytesReceived=s.bytesReceived+string.len(raw);s.progressAt=now
        if math.mod(seq,4)==0 or seq==s.parts then self:QueueGatherTransferControl("K",s,tostring(seq)) end
    elseif kind=="E" and s.phase=="receiving" and s.received==s.parts and s.bytesReceived==s.bytes then
        s.blob=table.concat(s.chunks);s.chunks=nil;s.phase="checking";s.hashPos=1;s.hashA=1;s.hashB=0
    end
    self:RefreshGatherTransferUI()
end
function M:SendGatherTransferPacket(text,channel)
    if self:SyncNow()<self.bulkNextPacket then return end
    self.bulkNextPacket=self:SyncNow()+GAP
    local ok=pcall(SendAddonMessage,PREFIX,text,channel)
    if not ok then self.bulkNextPacket=self:SyncNow()+5;self.bulkStatus="Addon send failed; retrying" end
    return ok
end
function M:UpdateGatherTransfer(elapsed)
    local now=self:SyncNow();local s=self.bulkSession
    if not s and count(self.bulkControls)==0 then self.bulkDriver:Hide();return end
    if now<(self.syncBlockedUntil or 0) then
        if s then s.progressAt=s.progressAt+elapsed;if s.deadline then s.deadline=s.deadline+elapsed end end
        self:RefreshGatherTransferUI();return
    end
    if s and s.direction=="send" then
        if s.phase=="prepare" then
            if C.BuildStep(s,self.gatherLogNodes,self.gatherShareMaps) then s.phase="hash" end
        elseif s.phase=="hash" then
            if C.HashStep(s) then
                s.bytes=string.len(s.blob);s.parts=math.ceil(s.bytes/C.chunk);s.phase="offer";s.deadline=now+30;s.offerAt=0
            end
        elseif s.phase=="offer" then
            if now>s.deadline then self:CancelGatherTransfer("Offer timed out; recipient must update zMap and accept")
            elseif now>=s.offerAt then
                self:QueueGatherTransferControl("O",s,s.count..":"..s.bytes..":"..s.parts..":"..string.format("%.0f",s.checksum)..":"..realm())
                s.offerAt=now+5
            end
        elseif s.phase=="sending" then
            if s.acked==s.parts then s.phase="finish";s.deadline=now+180;s.offerAt=0
            elseif now-s.progressAt>30 or s.retries>=6 then self:CancelGatherTransfer("Transfer stalled; please retry")
            elseif s.highest>s.acked and now-s.progressAt>4 then s.nextSeq=s.acked+1;s.retries=s.retries+1;s.progressAt=now end
        elseif s.phase=="finish" then
            if now>s.deadline then self:CancelGatherTransfer("Recipient did not confirm the import")
            elseif now>=s.offerAt then self:QueueGatherTransferControl("E",s);s.offerAt=now+3 end
        end
    elseif s then
        if s.phase=="offered" and now>s.deadline then self:CancelGatherTransfer("Offer expired",false)
        elseif s.phase=="receiving" and now-s.progressAt>30 then self:CancelGatherTransfer("Transfer timed out")
        elseif s.phase=="checking" then
            if C.HashStep(s) then
                if s.checksum~=s.expectedChecksum then self:CancelGatherTransfer("Snapshot checksum mismatch")
                else s.decode=C.StartDecode(s.blob,s.count);s.blob=nil
                    if not s.decode then self:CancelGatherTransfer("Invalid node snapshot") else s.phase="decoding" end
                end
            end
        elseif s.phase=="decoding" then
            local done=C.DecodeStep(s.decode)
            if s.decode.error then self:CancelGatherTransfer(s.decode.error)
            elseif done then s.phase="import";s.cursor=1;s.added=0;s.duplicates=0;s.skipped=0 end
        elseif s.phase=="import" then
            for i=1,100 do
                local row=s.decode.rows[s.cursor]
                if not row then
                    local result=s.added..":"..s.duplicates..":"..s.skipped
                    self.bulkReceipt={peer=s.peer,id=s.id,channel=s.channel,result=result,expires=now+180}
                    self:QueueGatherTransferControl("F",s,result)
                    self.bulkStatus="Imported "..s.added.." new locations; "..s.duplicates.." duplicates, "..s.skipped.." skipped"
                    self.dirty=true
                    self.bulkSession=nil;self:Print(self.bulkStatus..". /reload to save.");break
                end
                local outcome=C.Apply(row,self);s[outcome]=s[outcome]+1;s.cursor=s.cursor+1
                if outcome=="added" then self.gatherShareReceived=self.gatherShareReceived+1 end
            end
        end
    end
    if now>=self.bulkNextPacket then
        local control=self.bulkControls[1]
        if control then
            if control.channel~=self.bulkChannel or not self:GatherTransferPeer(control.peer) or now>control.expires then
                table.remove(self.bulkControls,1)
            else
                local ok=self:SendGatherTransferPacket(control.text,control.channel);control.tries=control.tries+1
                if ok or control.tries>=3 then table.remove(self.bulkControls,1) end
            end
        else
            s=self.bulkSession
            if s and s.phase=="sending" and s.nextSeq<=s.parts and s.nextSeq<=s.acked+WINDOW then
                local seq=s.nextSeq;local raw=string.sub(s.blob,(seq-1)*C.chunk+1,seq*C.chunk)
                local packet="D:"..s.peer..":"..s.id..":"..seq..":"..C.Encode(raw)
                if self:SendGatherTransferPacket(packet,s.channel) then s.nextSeq=seq+1;s.highest=math.max(s.highest,seq) end
            end
        end
    end
    self:RefreshGatherTransferUI()
    if not self.bulkSession and count(self.bulkControls)==0 then self.bulkDriver:Hide() end
end
function M:InitializeGatherTransfer()
    self.bulkControls={};self.bulkPeers={};self.bulkOfferAfter={};self.bulkRosterDirty=true;self.bulkNextPacket=0;self.bulkSerial=0
    local f=CreateFrame("Frame");self.bulkDriver=f;f:Hide()
    for _,eventName in ipairs({"CHAT_MSG_ADDON","PARTY_MEMBERS_CHANGED","RAID_ROSTER_UPDATE","PLAYER_ENTERING_WORLD","PLAYER_LEAVING_WORLD"}) do f:RegisterEvent(eventName) end
    f:SetScript("OnEvent",function()
        if not M.ready then return end
        if event=="CHAT_MSG_ADDON" then M:ReceiveGatherTransfer(arg1,arg2,arg3,arg4)
        elseif event=="PLAYER_LEAVING_WORLD" then
            M.bulkInWorld=nil;M:CancelGatherTransfer("Transfer interrupted by loading",false);M.bulkControls={};f:Hide();M.bulkRosterDirty=true
        else
            if event=="PLAYER_ENTERING_WORLD" then M.bulkInWorld=true end
            M.bulkRosterDirty=true;M:RefreshGatherTransferRoster()
        end
    end)
    f:SetScript("OnUpdate",function() M:UpdateGatherTransfer(arg1 or 0) end)
end
