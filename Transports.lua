-- Native route coordinates; read-only optional ZepSense/OctoBus adapters.
-- A schedule is never represented as a directly observed transport position.
local M=zMap
local function number(n) return type(n)=="number" and n==n and math.abs(n)<100000000000 end
local function period(n) return number(n) and n>=120 and n<=1800 end
local function dwell(n) return number(n) and n>=10 and n<=180 end
local function realm() local name=GetRealmName and GetRealmName();return type(name)=="string" and name~="" and name or "OctoWoW" end
local function point(map,x,y)
    local origin=M.data.origins[map];if not origin then return end
    return origin[1]-y,origin[2]-x
end
local function distance(x,y,a,b) return (x-a)^2+(y-b)^2 end
function M:TransportNow() return self:GatherTimerNow() end
function M:InitializeTransports()
    if zMapDB.transportsEnabled==nil then zMapDB.transportsEnabled=true end
    if zMapDB.transportRoutes==nil then zMapDB.transportRoutes=true end
    if zMapDB.transportTimers==nil then zMapDB.transportTimers=true end
    if type(zMapDB.transportLog)~="table" then zMapDB.transportLog={version=1,realms={}} end
    local saved=zMapDB.transportLog
    self.transportRoutes={};self.transportByEntry={};self.transportLive={};self.transportCandidates={}
    self.transportRuntime={};self.transportPollElapsed=0
    self.transportDockMarkers={};self.transportVehicleMarkers={};self.transportRouteDots={}
    self.transportWorld=false;self.transportClockReady=false;self.transportQueryAt=nil
    local log={routes={}}
    if saved.version==1 then
        if type(saved.realms)~="table" then saved.realms={} end
        local key=realm()
        if type(saved.realms[key])~="table" then saved.realms[key]={routes={}} end
        log=saved.realms[key]
        if type(log.routes)~="table" then log.routes={} end
    end
    self.transportLog=log
    local now=self:TransportNow()
    for _,data in ipairs(zMapTransportData and zMapTransportData.routes or {}) do
        local route={id=data.id,entry=data.entry,name=data.name,kind=data.kind,data=data,stops={}}
        self.transportRoutes[table.getn(self.transportRoutes)+1]=route;self.transportByEntry[route.entry]=route
        for i,stop in ipairs(data.stops) do
            local x,y=point(stop.map,stop.worldX,stop.worldY)
            route.stops[i]={name=stop.name,map=stop.map,x=x,y=y,data=stop,route=route,index=i}
        end
        local state=log.routes[route.id]
        if type(state)~="table" then state={};log.routes[route.id]=state end
        if not period(state.period) then state.period=data.period end
        if not number(state.detectedAt) or state.detectedAt>now+2 then state.detectedAt=nil end
        if type(state.arrivals)~="table" then state.arrivals={} end
        for i,value in pairs(state.arrivals) do
            if not route.stops[i] or type(value)~="table" or not number(value.anchor) or value.anchor>now+2 or
                value.anchor<now-30*86400 or not dwell(value.dwell) then state.arrivals[i]=nil
            else
                if not number(value.seenAt) or value.seenAt>now+2 then value.seenAt=0 end
                if type(value.source)~="string" or string.len(value.source)>80 then value.source="saved observation" end
            end
        end
        route.state=state;self.transportRuntime[route.id]={}
    end
    local driver=CreateFrame("Frame");self.transportDriver=driver
    for _,name in ipairs({"PLAYER_ENTERING_WORLD","PLAYER_LEAVING_WORLD","CHAT_MSG_SYSTEM"}) do driver:RegisterEvent(name) end
    driver:SetScript("OnEvent",function()
        if not M.ready then return end
        if event=="PLAYER_LEAVING_WORLD" then M.transportWorld=false;M:ClearTransportObservations()
        elseif event=="PLAYER_ENTERING_WORLD" then
            M.transportWorld=true;M.transportClockReady=false;M.transportUptimeConfirmed=false;M.transportQueryAt=M:TransportNow()+8;M:ClearTransportObservations()
        elseif event=="CHAT_MSG_SYSTEM" then
            local uptime=M:ParseTransportUptime(arg1)
            if uptime then M:OnTransportBoot(M:TransportNow()-uptime);M.transportUptimeConfirmed=true;M.transportQueryAt=nil end
        end
    end)
    driver:SetScript("OnUpdate",function() if M.ready then M:UpdateTransports(arg1 or 0) end end)
end
function M:ClearTransportObservations()
    self.transportLive={};self.transportCandidates={};self.transportProviderReady=false
    self:HideTransportTooltip()
    if self.layers then self:RenderTransports() end
end
function M:ParseTransportUptime(message)
    if type(message)~="string" then return end
    local _,_,rest=string.find(message,"^Server uptime:%s*(.+)$")
    if not rest then return end
    local total,found=0,false
    for count,unit in string.gfind(string.lower(rest),"(%d+)%s+(%a+)") do
        local scale
        if string.find(unit,"^day") then scale=86400 elseif string.find(unit,"^hour") then scale=3600
        elseif string.find(unit,"^min") then scale=60 elseif string.find(unit,"^sec") then scale=1 end
        if scale then total=total+tonumber(count)*scale;found=true end
    end
    if found and total>0 and total<31536000 then return total end
end
function M:OnTransportBoot(boot)
    local now=self:TransportNow()
    if not number(boot) or boot>now or boot<now-31536000 then return end
    local old=self.transportLog.boot
    if self.transportClockReady and number(old) and math.abs(old-boot)<=3 then return end
    if self.transportClockReady and number(old) and boot<old-3 then return end
    self.transportClockReady=true;self.transportLog.boot=boot
    for _,route in ipairs(self.transportRoutes) do
        for i,value in pairs(route.state.arrivals) do
            if value.anchor<boot-3 then route.state.arrivals[i]=nil end
        end
        self.transportRuntime[route.id].obAnchor=nil
    end
end
function M:ReadOctoBusSchedules()
    -- Read fields only. No OctoBus functions, defaults, metatables or writes.
    local db=OctoBusDB
    if type(db)~="table" then return end
    local now=self:TransportNow();local boot=db.boot
    if number(boot) and boot<=now and boot>now-31536000 then self:OnTransportBoot(boot) end
    for _,route in ipairs(self.transportRoutes) do
        local entry=route.entry;local anchor=type(db.anchor)=="table" and db.anchor[entry]
        local p=type(db.period)=="table" and db.period[entry]
        local seen=type(db.seenAt)=="table" and db.seenAt[entry]
        local runtime=self.transportRuntime[route.id]
        if period(p) and not runtime.observed then route.state.period=p end
        local offset=type(db.farOff)=="table" and db.farOff[entry]
        local farDwell=type(db.farDwell)=="table" and db.farDwell[entry]
        runtime.farOffset=number(offset) and offset>0 and period(p) and offset<p and offset or nil
        runtime.farDwell=dwell(farDwell) and farDwell or nil
        if period(p) and number(anchor) and anchor<=now+2 and anchor>now-30*86400 and
            (not self.transportClockReady or anchor>=self.transportLog.boot-3) and runtime.obAnchor~=anchor then
            runtime.obAnchor=anchor
            if not period(route.state.period) or not runtime.observed then route.state.period=p end
            for i,stop in ipairs(route.stops) do
                if stop.data.home then
                    local value=route.state.arrivals[i]
                    if not value or (number(seen) and seen>(value.seenAt or 0)) then
                        local stay=type(db.dwell)=="table" and db.dwell[entry]
                        route.state.arrivals[i]={anchor=anchor,dwell=dwell(stay) and stay or stop.data.dwell,seenAt=number(seen) and seen or 0,source="OctoBus schedule"}
                    end
                end
            end
        end
    end
end
function M:TransportSchedule(route,index)
    local p=route.state.period;if not period(p) then return end
    local value=route.state.arrivals[index]
    if value then
        local source=value.source or "saved observation"
        if route.state.periodLearned then source=source.." / learned cycle estimate" end
        return value.anchor,p,value.dwell,source
    end
    local stop=route.stops[index];local phase=stop.data.phase
    local runtime=self.transportRuntime[route.id]
    if not stop.data.home and number(runtime.farOffset) and runtime.farOffset>0 and runtime.farOffset<p then phase=runtime.farOffset end
    if phase~=nil then
        for j,other in ipairs(route.stops) do
            local source=route.state.arrivals[j]
            local otherPhase=other.data.phase
            if not other.data.home and number(runtime.farOffset) and runtime.farOffset>0 and runtime.farOffset<p then otherPhase=runtime.farOffset end
            if source and otherPhase~=nil then
                local stay=stop.data.dwell
                if not stop.data.home and dwell(runtime.farDwell) then stay=runtime.farDwell end
                return source.anchor+phase-otherPhase,p,stay,"route-offset estimate"
            end
        end
        if self.transportClockReady and self.transportLog.boot and number(route.data.bootPhase) then
            return self.transportLog.boot+route.data.bootPhase+phase,p,stop.data.dwell,"restart estimate"
        end
    end
end
function M:TransportStopStatus(stop,now)
    now=now or self:TransportNow()
    local live=self.transportLive[stop.route.entry]
    local observed=live and now-live.at<=1.5 and live.stop==stop.index
    local anchor,p,stay,source=self:TransportSchedule(stop.route,stop.index)
    if anchor then
        local phase=math.mod(now-anchor,p);if phase<0 then phase=phase+p end
        if phase<stay then return observed and "docked" or "expected",stay-phase,source end
        if observed then return "docked",nil,"departure not calibrated" end
        return "arriving",p-phase,source
    end
    return observed and "docked" or "unknown",nil,"awaiting a dock observation"
end
function M:ObserveTransportArrival(route,index,at)
    local old=route.state.arrivals[index];local p=route.state.period
    if old and at>old.anchor then
        local delta=at-old.anchor
        if route.state.periodLearned and period(delta) and delta<p*.95 then
            route.state.period=delta
        elseif period(p) then
            local cycles=math.floor(delta/p+.5)
            if cycles>=1 and cycles<=1000 and math.abs(delta/cycles-p)<p*.05 then route.state.period=p*.95+(delta/cycles)*.05 end
        elseif period(delta) then route.state.period=delta;route.state.periodLearned=true end
    end
    route.state.arrivals[index]={anchor=at,dwell=old and old.dwell or route.stops[index].data.dwell,seenAt=at,source="observed arrival"}
    self.transportRuntime[route.id].observed=true
end
function M:InferTransportMap(route,x,y)
    local best,bestDistance
    local nodes=route.data.points
    for i,node in ipairs(nodes) do
        local d=distance(x,y,node[2],node[3])
        if not bestDistance or d<bestDistance then bestDistance=d;best=node[1] end
        local nextNode=nodes[i+1]
        if nextNode and node[1]==nextNode[1] and node[5]~=1 and nextNode[5]~=1 then
            local dx,dy=nextNode[2]-node[2],nextNode[3]-node[3];local length=dx*dx+dy*dy
            if length>0 and length<6000*6000 then
                local t=self.Clamp(((x-node[2])*dx+(y-node[3])*dy)/length,0,1)
                d=distance(x,y,node[2]+dx*t,node[3]+dy*t)
                if d<bestDistance then bestDistance=d;best=node[1] end
            end
        end
    end
    if bestDistance and bestDistance<=1000*1000 then return best end
end
function M:SampleTransports()
    local now=self:TransportNow()
    if not self.transportWorld or not zMapDB.transportsEnabled or type(ZepTransports)~="function" then
        self.transportProviderReady=false;self.transportLive={};self.transportCandidates={};return
    end
    local ok,raw=pcall(ZepTransports)
    if not ok or type(raw)~="string" or string.len(raw)>16384 then
        self.transportProviderReady=false;self.transportLive={};self.transportCandidates={};return
    end
    self.transportProviderReady=true
    local present={};local count=0
    for record in string.gfind(raw,"([^;]+);") do
        count=count+1;if count>128 then break end
        local _,_,guid,tag,ge,entry,x,y,z=string.find(record,"^(%x+),(%x+),(%d+),(%d+),([%d%.%-]+),([%d%.%-]+),([%d%.%-]+)$")
        entry=tonumber(entry);x=tonumber(x);y=tonumber(y);z=tonumber(z)
        local route=entry and self.transportByEntry[entry]
        if route and type(guid)=="string" and string.len(guid)==16 and number(x) and number(y) and number(z) and math.abs(x)<100000 and math.abs(y)<100000 and math.abs(z)<100000 then
            local map=self:InferTransportMap(route,x,y)
            if map then
                route.state.detectedAt=now
                local ax,ay=point(map,x,y);local stopIndex
                for i,stop in ipairs(route.stops) do if stop.map==map and distance(x,y,stop.data.worldX,stop.data.worldY)<=4 then stopIndex=i end end
                local candidate=self.transportCandidates[entry]
                if candidate and now-candidate.at>2 then candidate=nil end
                if not candidate or candidate.guid~=guid then candidate={guid=guid,initial=true};self.transportCandidates[entry]=candidate end
                local before=candidate.stop
                if stopIndex~=before then
                    if before and candidate.docked then
                        local previous=route.state.arrivals[before]
                        if candidate.arrival and previous then
                            local stay=now-candidate.arrival
                            if dwell(stay) then previous.dwell=stay end
                        elseif dwell(route.stops[before].data.dwell) then
                            route.state.arrivals[before]={anchor=now-route.stops[before].data.dwell,dwell=route.stops[before].data.dwell,seenAt=now,source="observed departure estimate"}
                        end
                    end
                    candidate.stop=stopIndex;candidate.since=now;candidate.docked=false;candidate.arrival=nil
                    candidate.canArrive=not candidate.initial
                end
                if stopIndex and not candidate.docked and now-(candidate.since or now)>=.75 then
                    candidate.docked=true
                    if candidate.canArrive then candidate.arrival=candidate.since;self:ObserveTransportArrival(route,stopIndex,candidate.arrival) end
                end
                candidate.initial=false;candidate.at=now
                self.transportLive[entry]={guid=guid,route=route,map=map,x=ax,y=ay,worldX=x,worldY=y,z=z,at=now,stop=stopIndex}
                present[entry]=true
            end
        end
    end
    for entry in pairs(self.transportLive) do if not present[entry] then self.transportLive[entry]=nil;self.transportCandidates[entry]=nil end end
end
function M:UpdateTransports(elapsed)
    if not self.transportWorld then return end
    local now=self:TransportNow()
    if self.transportQueryAt and now>=self.transportQueryAt then
        self.transportQueryAt=nil
        if zMapDB.transportsEnabled and not self.transportUptimeConfirmed and type(SendChatMessage)=="function" then
            pcall(SendChatMessage,".server info","SAY")
        end
    end
    self.transportPollElapsed=self.transportPollElapsed+elapsed
    if self.transportPollElapsed>=.5 then
        self.transportPollElapsed=0;self:ReadOctoBusSchedules();self:SampleTransports()
        if self.frame and self.frame:IsShown() then self:RenderTransports() end
        if self.transportPanel and self.transportPanel:IsShown() then self:RefreshTransportPanel() end
    end
end
