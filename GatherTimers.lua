-- Respawn estimates are local observations, never live server availability.
local M=zMap
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<100000000000 end
local function estimate(samples)
    if not samples or table.getn(samples)<3 then return end
    local sorted={}
    for _,value in ipairs(samples) do table.insert(sorted,value) end
    table.sort(sorted)
    local median=sorted[math.floor((table.getn(sorted)+1)/2)]
    if sorted[table.getn(sorted)]-sorted[1]<=math.max(6,median*.3) then return median end
end
function M:GatherTimerNow()
    local clock=GetTime and GetTime() or self.gatherShareClock or 0
    return (self.gatherTimerEpoch or 0)+clock-(self.gatherTimerBase or 0)
end
function M:InitializeGatherTimers()
    self.gatherTimerBase=GetTime and GetTime() or self.gatherShareClock or 0
    self.gatherTimerEpoch=time and time() or self.gatherTimerBase
    self:ResetGatherTimingWatch()
    local now=self:GatherTimerNow()
    for _,node in ipairs(self.gatherLogNodes) do
        local record=node.record;local samples={}
        if type(record.respawnSamples)=="table" then
            for _,value in ipairs(record.respawnSamples) do
                if table.getn(samples)>=5 then break end
                if finite(value) and value>=15 and value<=7200 then table.insert(samples,value) end
            end
        end
        record.respawnSamples=table.getn(samples)>0 and samples or nil
        record.respawnEstimate=estimate(samples)
        if not record.respawnEstimate or not finite(record.cooldownAt) or record.cooldownAt>now+2 or
            not finite(record.cooldownDuration) or record.cooldownDuration<15 or record.cooldownDuration>7200 or
            now>=record.cooldownAt+record.cooldownDuration then
            record.cooldownAt=nil;record.cooldownDuration=nil
        end
    end
end
function M:ResetGatherTimingWatch()
    self.gatherTimingPrevious={};self.gatherTimingWatch={};self.gatherTimingLast=nil;self.gatherTimingMap=nil
end
function M:LearnGatherRespawn(location,delay)
    local record=location.record
    record.cooldownAt=nil;record.cooldownDuration=nil
    if delay<15 or delay>7200 then return end
    local samples=record.respawnSamples or {};record.respawnSamples=samples
    table.insert(samples,math.floor(delay+.5))
    if table.getn(samples)>5 then table.remove(samples,1) end
    record.respawnEstimate=estimate(samples)
end
function M:SampleGatherTimers(map,px,py,pz)
    local now=self:GatherTimerNow()
    if self.gatherTimingMap~=map or not self.gatherTimingLast or now-self.gatherTimingLast>2 or now<self.gatherTimingLast then
        self:ResetGatherTimingWatch()
    end
    local function nearby(location)
        local record=location.record
        return record.map==map and math.abs(record.worldZ-pz)<=20 and
            (record.worldX-px)^2+(record.worldY-py)^2<=45*45
    end
    for id,watch in pairs(self.gatherTimingWatch) do
        local location=watch.location
        if not nearby(location) then self.gatherTimingWatch[id]=nil
        elseif location.live then
            self:LearnGatherRespawn(location,now-watch.start);self.gatherTimingWatch[id]=nil
        end
    end
    for _,location in ipairs(self.gatherTimingPrevious) do
        if not location.live and not self.gatherTimingWatch[location.id] and nearby(location) then
            self.gatherTimingWatch[location.id]={location=location,start=now}
            local record=location.record
            if record.respawnEstimate then record.cooldownAt=now;record.cooldownDuration=record.respawnEstimate end
        end
    end
    local previous={};local seen={}
    for _,node in ipairs(self.gatherNodes) do
        local location=node.location
        if location then
            -- Actual detection always clears prediction, including early returns.
            location.record.cooldownAt=nil;location.record.cooldownDuration=nil
            if not seen[location.id] and nearby(location) then table.insert(previous,location);seen[location.id]=true end
        end
    end
    self.gatherTimingPrevious=previous;self.gatherTimingLast=now;self.gatherTimingMap=map
end
function M:GetGatherCooldown(location,now)
    if not location or location.live then return end
    local record=location.record
    if not record.respawnEstimate or not record.cooldownAt or not record.cooldownDuration then return end
    now=now or self:GatherTimerNow()
    local remaining=record.cooldownAt+record.cooldownDuration-now
    if remaining>0 and remaining<=record.cooldownDuration then return remaining/record.cooldownDuration end
end
