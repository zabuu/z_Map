-- Transport observations only. No predicted poses, player coordinates or GUIDs.
local M=zMap
local CHANNEL="zMapTransit15"
local function number(n) return type(n)=="number" and n==n and math.abs(n)<100000000000 end
local function period(n) return number(n) and n>=120 and n<=1800 end
local function channelID()
    local id=GetChannelName and GetChannelName(CHANNEL)
    if type(id)=="number" and id>0 then return id end
end
function M:InitializeTransportSync()
    if zMapDB.transportSharing==nil then zMapDB.transportSharing=true end
    self.transportShareSent=0;self.transportShareReceived=0;self.transportSharePeers={};self.transportShareTokens=64
    self:ResetTransportSyncSession()
end
function M:ResetTransportSyncSession()
    local now=self:TransportNow()
    self.transportShareNext=now+3;self.transportShareJoin=now+5;self.transportShareHello=0
    self.transportShareLocalSent={};self.transportShareLastPose={};self.transportShareAnchorSent={};self.transportShareHeard={}
    self.transportShareSweep=nil;self.transportShareSweepAt=nil;self.transportShareError=nil
    self:SyncIdle("transport")
end
function M:HideTransportChannel()
    if ChatFrame_RemoveChannel and getglobal then
        for i=1,(NUM_CHAT_WINDOWS or 7) do
            local frame=getglobal("ChatFrame"..i);if frame then ChatFrame_RemoveChannel(frame,CHANNEL) end
        end
    end
end
function M:SetTransportSharing(enabled)
    zMapDB.transportSharing=enabled==true;self.transportRemote={};self:ResetTransportSyncSession()
    if not enabled and LeaveChannelByName then pcall(LeaveChannelByName,CHANNEL);self.transportShareJoined=nil end
    if self.layers then self:RenderTransports() end
    if self.transportPanel then self:RefreshTransportPanel() end
end
function M:TransportSharingStatus()
    if not zMapDB.transportSharing then return "off" end
    if not zMapDB.transportsEnabled then return "paused" end
    local pause=self:SyncPauseStatus();if pause then return pause end
    if self.transportShareError then return "retrying" end
    if not self.transportClockReady then return "waiting for uptime" end
    return channelID() and "connected" or "waiting to connect"
end
function M:TransportUptime()
    if self.transportClockReady and number(self.transportLog.boot) then return self:TransportNow()-self.transportLog.boot end
end
function M:StartTransportModelSweep()
    local now=self:TransportNow()
    if self.transportShareSweep or self.transportShareSweepAt and now-self.transportShareSweepAt<900 then return end
    self.transportShareSweep={route=1,leg=1,bin=1};self.transportShareSweepAt=now
    self.transportShareAnchorSent={}
end
function M:BuildTransportAnchorPacket(up)
    local records,marks={},{};local now=self:TransportNow()
    for _,route in ipairs(self.transportRoutes) do
        local p=period(route.state.period) and route.state.period or 0
        for index=1,2 do
            local a=route.state.arrivals[index]
            if a and (a.source=="observed arrival" or a.source=="observed departure estimate") then
                local age=now-a.anchor;local key=route.entry..":"..index
                local stamp=string.format("%.2f:%.2f:%.3f",a.anchor,a.dwell,p)
                if age>=0 and age<=(p>0 and p*2 or 1800) and self.transportShareAnchorSent[key]~=stamp then
                    table.insert(records,string.format("%d,%d,%.2f,%.3f,%.2f,%s",route.entry,index,age,p,a.dwell,a.source=="observed arrival" and "a" or "d"))
                    marks[key]=stamp
                    if table.getn(records)==3 then break end
                end
            end
        end
        if table.getn(records)==3 then break end
    end
    if table.getn(records)>0 then return "ZMT1:A:"..string.format("%.2f",up)..":"..table.concat(records,";"),marks end
end
function M:BuildTransportSightPacket(up)
    local candidates={};local now=self:TransportNow();local name=UnitName("player") or ""
    for _,route in ipairs(self.transportRoutes) do
        local pose=self.transportLive[route.entry];local heard=self.transportShareHeard[route.entry]
        local last=self.transportShareLastPose[route.entry]
        local changed=pose and (not last or pose.map~=last.map or pose.stop~=last.stop or
            (pose.worldX-last.worldX)^2+(pose.worldY-last.worldY)^2>40^2 or math.abs(pose.z-last.z)>10)
        if pose and now-pose.at<=1.5 and now-(self.transportShareLocalSent[route.entry] or 0)>=15 and
            (changed or now-last.at>=90) and not (heard and now-heard.at<120 and heard.sender<name) then table.insert(candidates,pose) end
    end
    table.sort(candidates,function(a,b)
        local x,y=self.transportShareLocalSent[a.route.entry] or 0,self.transportShareLocalSent[b.route.entry] or 0
        if x~=y then return x<y end;return a.route.entry<b.route.entry
    end)
    local records,entries={},{}
    for i=1,math.min(3,table.getn(candidates)) do
        local p=candidates[i]
        table.insert(records,string.format("%d,%.2f,%d,%.1f,%.1f,%.1f",p.route.entry,math.max(0,now-p.at),p.map,p.worldX,p.worldY,p.z))
        table.insert(entries,p.route.entry)
    end
    if table.getn(records)>0 then return "ZMT1:S:"..string.format("%.2f",up)..":"..table.concat(records,";"),entries end
end
function M:BuildTransportModelPacket(up)
    local cursor=self.transportShareSweep;if not cursor then return end
    local c={route=cursor.route,leg=cursor.leg,bin=cursor.bin};local now=self:TransportNow()
    local records={};local selected,selectedLeg
    -- Bound work even when nearly all samples came from peers or were filtered.
    for visits=1,128 do
        local route=self.transportRoutes[c.route]
        if not route then if selected then break else self.transportShareSweep=nil;return end end
        if selected and (selected~=route or selectedLeg~=c.leg) then break end
        local sample=route.state.motion.legs[c.leg].samples[c.bin]
        if sample and sample.localOrigin and sample.at>=now-14*86400 and period(route.state.period) then
            selected=route;selectedLeg=c.leg
            local u=self.Clamp(sample.u,(c.bin-1)/64+.000001,c.bin/64-.000001)
            table.insert(records,string.format("%d,%.6f,%.6f,%d,%.0f",c.bin,u,sample.progress,sample.n,math.max(0,now-sample.at)))
        end
        c.bin=c.bin+1
        if c.bin>64 then c.bin=1;c.leg=c.leg+1 end
        if c.leg>2 then c.leg=1;c.route=c.route+1 end
        if table.getn(records)==3 then break end
    end
    if selected then
        return string.format("ZMT1:M:%.2f:%d:%d:%d:%.3f:",up,selected.entry,selected.geometry.signature,selectedLeg,selected.state.period)..table.concat(records,";"),c
    end
    self.transportShareSweep=c
end
function M:UpdateTransportSync(elapsed)
    self.transportShareTokens=math.min(64,self.transportShareTokens+elapsed*16)
    if not zMapDB.transportSharing or not zMapDB.transportsEnabled then
        self:SyncIdle("transport")
        if self.transportShareJoined and LeaveChannelByName then pcall(LeaveChannelByName,CHANNEL);self.transportShareJoined=nil end
        return
    end
    if not self.transportWorld or not SendChatMessage then self:SyncIdle("transport");return end
    local now=self:TransportNow();if now<self.transportShareNext then return end
    local id=channelID()
    if not id then
        if now>=self.transportShareJoin and JoinChannelByName then
            pcall(JoinChannelByName,CHANNEL);self:HideTransportChannel();self.transportShareJoin=now+30
        end
        self.transportShareNext=now+1;return
    end
    if self.transportShareJoined~=id then self:HideTransportChannel();self.transportShareJoined=id end
    local up=self:TransportUptime();if not up or up<0 or up>31536000 then return end
    if not self:CanSyncSend("transport") then return end
    local message,kind,marks
    if now>=self.transportShareHello then message=string.format("ZMT1:H:%.2f",up);kind="hello"
    else
        message,marks=self:BuildTransportAnchorPacket(up);kind="anchor"
        if not message then message,marks=self:BuildTransportSightPacket(up);kind="sight" end
        if not message then message,marks=self:BuildTransportModelPacket(up);kind="model" end
    end
    if not message then self.transportShareNext=now+.25;self:SyncIdle("transport");return end
    if string.len(message)>230 then self.transportShareNext=now+1;return end
    local cursor=self.transportShareSweep
    local ok=self:SendSyncMessage("transport",message,"CHANNEL",id,function()
        if kind=="hello" then self.transportShareHello=0
        elseif kind=="anchor" then for k,v in pairs(marks) do if self.transportShareAnchorSent[k]==v then self.transportShareAnchorSent[k]=nil end end
        elseif kind=="sight" then for _,entry in ipairs(marks) do self.transportShareLocalSent[entry]=nil;self.transportShareLastPose[entry]=nil end
        elseif kind=="model" and zMapDB.transportSharing then self.transportShareSweep=cursor end
    end)
    if ok==nil then return end
    self.transportShareError=not ok;self.transportShareNext=now+(ok and .25 or 30)
    if not ok then return end
    self.transportShareSent=self.transportShareSent+1
    if kind=="hello" then self.transportShareHello=now+900
    elseif kind=="anchor" then for k,v in pairs(marks) do self.transportShareAnchorSent[k]=v end
    elseif kind=="sight" then for _,entry in ipairs(marks) do
        self.transportShareLocalSent[entry]=now;local p=self.transportLive[entry]
        self.transportShareLastPose[entry]={map=p.map,worldX=p.worldX,worldY=p.worldY,z=p.z,stop=p.stop,at=now}
    end
    elseif kind=="model" then self.transportShareSweep=marks end
end
function M:ReceiveTransportShare(message,sender,channel)
    if not self.ready or not self.transportWorld or not zMapDB.transportsEnabled or not zMapDB.transportSharing or
        type(channel)~="string" or string.lower(channel)~=string.lower(CHANNEL) or
        type(message)~="string" or string.len(message)>230 or string.sub(message,1,5)~="ZMT1:" or
        type(sender)~="string" or sender==UnitName("player") or string.len(sender)<1 or string.len(sender)>64 then return end
    local now=self:TransportNow();local up=self:TransportUptime();if not up then return end
    local _,_,kind,wireUp,body=string.find(message,"^ZMT1:([SAM]):([%d%.]+):(.*)$")
    if not kind then _,_,wireUp=string.find(message,"^ZMT1:H:([%d%.]+)$");kind=wireUp and "H" end
    wireUp=tonumber(wireUp)
    if not kind or not number(wireUp) or wireUp<0 or wireUp>31536000 or math.abs(up-wireUp)>8 then return end
    local peer=self.transportSharePeers[sender]
    if not peer then
        local count=0;for name,p in pairs(self.transportSharePeers) do
            if now-p.seen>600 then self.transportSharePeers[name]=nil else count=count+1 end
        end
        if count>=128 then return end;peer={tokens=8,seen=now};self.transportSharePeers[sender]=peer
    end
    peer.tokens=math.min(8,peer.tokens+math.max(0,now-peer.seen));peer.seen=now
    if peer.tokens<1 or self.transportShareTokens<1 then return end
    peer.tokens=peer.tokens-1;self.transportShareTokens=self.transportShareTokens-1
    local delay=math.max(0,up-wireUp);local accepted=false
    if kind=="H" then
        if not peer.hello or now-peer.hello>=900 then
            peer.hello=now;self:StartTransportModelSweep()
            -- A late joiner may own recordings we do not have. Request them too;
            -- the per-peer cooldown prevents hello/reply loops.
            if not peer.replied then peer.replied=true;self.transportShareHello=math.min(self.transportShareHello,now+15) end
        end
        return
    end
    if kind=="M" then
        local _,_,entry,sig,leg,p,records=string.find(body,"^(%d+):(%d+):(%d+):([%d%.]+):(.*)$")
        entry=tonumber(entry);sig=tonumber(sig);leg=tonumber(leg);p=tonumber(p)
        local route=entry and self.transportByEntry[entry]
        if not route or sig~=route.geometry.signature or (leg~=1 and leg~=2) or not period(p) or
            period(route.state.period) and math.abs(p-route.state.period)>route.state.period*.05 then return end
        local count=0
        for record in string.gfind(records,"[^;]+") do
            count=count+1;if count>3 then break end
            local _,_,bin,u,progress,n,age=string.find(record,"^(%d+),([%d%.]+),([%d%.]+),(%d+),(%d+)$")
            bin=tonumber(bin);u=tonumber(u);progress=tonumber(progress);n=tonumber(n);age=tonumber(age)
            if number(age) and age>=0 and age<=14*86400 and zMapDB.transportRecord and
                self:MergeTransportMotionSample(route,leg,bin,u,progress,n,now-age-delay,false) then accepted=true end
        end
    else
        local count=0
        for record in string.gfind(body,"[^;]+") do
            count=count+1;if count>3 then break end
            if kind=="S" then
                local _,_,entry,age,map,x,y,z=string.find(record,"^(%d+),([%d%.]+),(%d+),([%d%.%-]+),([%d%.%-]+),([%d%.%-]+)$")
                entry=tonumber(entry);age=tonumber(age);map=tonumber(map);x=tonumber(x);y=tonumber(y);z=tonumber(z)
                local route=entry and self.transportByEntry[entry]
                if route and number(age) and age>=0 and age+delay<=5 and (map==0 or map==1) and
                    number(x) and number(y) and number(z) and math.abs(x)<100000 and math.abs(y)<100000 and math.abs(z)<100000 then
                    local valid=false
                    for leg=1,2 do local _,error=self:ProjectTransportPath(route,leg,map,x,y,z);if error and error<=120 then valid=true end end
                    local stopIndex
                    for i,stop in ipairs(route.stops) do if stop.map==map and (x-stop.data.worldX)^2+(y-stop.data.worldY)^2<=4 and math.abs(z-stop.data.worldZ)<10 then stopIndex=i;valid=true end end
                    local prior=self.transportRemote[entry];local at=now-age-delay
                    if valid and (not prior or at>prior.at+.01) then
                        local origin=self.data.origins[map]
                        local pose={route=route,map=map,x=origin[1]-y,y=origin[2]-x,worldX=x,worldY=y,z=z,at=at,stop=stopIndex,sender=sender}
                        self:RecordTransportSighting(pose,true);self.transportRemote[entry]=pose
                        route.state.detectedAt=math.max(route.state.detectedAt or 0,at)
                        self.transportShareHeard[entry]={at=at,sender=sender};accepted=true
                    end
                end
            elseif kind=="A" then
                local _,_,entry,index,age,p,stay,how=string.find(record,"^(%d+),(%d+),([%d%.]+),([%d%.]+),([%d%.]+),([ad])$")
                entry=tonumber(entry);index=tonumber(index);age=tonumber(age);p=tonumber(p);stay=tonumber(stay)
                local route=entry and self.transportByEntry[entry]
                if route and (index==1 or index==2) and (p==0 or period(p)) and number(age) and age>=0 and age+delay<=(p==0 and 1800 or p*2) and
                    number(stay) and stay>=10 and stay<=180 and (p==0 or not period(route.state.period) or
                    math.abs(p-route.state.period)<=route.state.period*.05 or route.state.periodLearned) then
                    local old=route.state.arrivals[index];local anchor=now-age-delay
                    if anchor>=self.transportLog.boot-3 then
                        local runtime=self.transportRuntime[route.id]
                        if not period(route.state.period) and how=="a" and old and
                            (old.source=="observed arrival" or old.source=="shared arrival") then
                            local delta=math.abs(anchor-old.anchor)
                            if period(delta) then route.state.period=delta;route.state.periodLearned=true;accepted=true end
                        end
                        if period(p) and (not period(route.state.period) or not runtime.observed or route.state.periodLearned) then
                            route.state.period=p;route.state.periodLearned=not route.data.period
                        end
                        if not old or anchor>old.anchor+2 then
                            route.state.arrivals[index]={anchor=anchor,dwell=stay,seenAt=anchor,source=how=="a" and "shared arrival" or "shared departure estimate"}
                            accepted=true
                        end
                        route.state.detectedAt=math.max(route.state.detectedAt or 0,anchor);accepted=true
                    end
                end
            end
        end
    end
    if accepted then self.transportShareReceived=self.transportShareReceived+1 end
end
