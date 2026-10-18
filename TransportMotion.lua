-- Native paths plus timed observations. Predicted poses never become sightings.
local M=zMap
local BINS=64
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<100000000000 end
local function mod(n,p) local v=math.mod(n,p);if v<0 then return v+p end;return v end
local function signature(text)
    local n=0;for i=1,string.len(text) do n=math.mod(n*33+string.byte(text,i),2147483647) end;return n
end
function M:BuildTransportGeometry(route)
    local nodes=route.data.points;local starts={};local words={}
    for i,node in ipairs(nodes) do
        table.insert(words,string.format("%d,%.1f,%.1f,%.1f,%d",node[1],node[2],node[3],node[4],node[5]))
        for j,stop in ipairs(route.stops) do
            if not starts[j] and math.mod(math.floor(node[5]/2),2)==1 and node[1]==stop.map and
                (node[2]-stop.data.worldX)^2+(node[3]-stop.data.worldY)^2<1 then starts[j]=i end
        end
    end
    local geometry={signature=signature(table.concat(words,";")),legs={}}
    for index=1,2 do
        local leg={segments={},gaps={},length=0};geometry.legs[index]=leg
        local i,target=starts[index],starts[index==1 and 2 or 1]
        if i and target then
            for visits=1,table.getn(nodes) do
                local j=math.mod(i,table.getn(nodes))+1;local a,b=nodes[i],nodes[j]
                local length=math.sqrt((b[2]-a[2])^2+(b[3]-a[3])^2+(b[4]-a[4])^2)
                if a[1]==b[1] and a[5]~=1 and b[5]~=1 and length<6000 then
                    if length>.01 then
                        table.insert(leg.segments,{a=a,b=b,from=leg.length,to=leg.length+length,length=length})
                        leg.length=leg.length+length
                    end
                else table.insert(leg.gaps,leg.length) end
                i=j;if i==target then break end
            end
        end
    end
    return geometry
end
function M:InitializeTransportMotion()
    if zMapDB.transportPredict==nil then zMapDB.transportPredict=true end
    if zMapDB.transportRecord==nil then zMapDB.transportRecord=true end
    self.transportRemote={};self.transportMotionSerial=0;self.transportAnimationElapsed=0
    local now=self:TransportNow()
    for _,route in ipairs(self.transportRoutes) do
        route.geometry=self:BuildTransportGeometry(route);route.motionCurves={}
        local old=route.state.motion;local motion={version=1,signature=route.geometry.signature,legs={{samples={}},{samples={}}}}
        if type(old)=="table" and old.version==1 and old.signature==motion.signature and type(old.legs)=="table" then
            for leg=1,2 do
                local samples=type(old.legs[leg])=="table" and old.legs[leg].samples
                if type(samples)=="table" then for bin=1,BINS do
                    local s=samples[bin]
                    if type(s)=="table" then self:MergeTransportMotionSample(route,leg,bin,s.u,s.progress,s.n,s.at,s.localOrigin,motion,now) end
                end end
            end
        end
        route.state.motion=motion
    end
end
function M:ResetTransportMotionTracking()
    self.transportRemote={}
    for _,runtime in pairs(self.transportRuntime) do
        runtime.correction=nil;runtime.previousLocal=nil;runtime.previousRemote=nil
    end
end
function M:MergeTransportMotionSample(route,leg,bin,u,progress,n,at,localOrigin,target,now)
    now=now or self:TransportNow()
    if (leg~=1 and leg~=2) or not finite(bin) or bin~=math.floor(bin) or bin<1 or bin>BINS or
        not finite(u) or u<=0 or u>=1 or math.floor(u*BINS)+1~=bin or
        not finite(progress) or progress<=0 or progress>=1 or not finite(n) or n<1 or n>8 or
        not finite(at) or at>now+2 or at<now-14*86400 then return false end
    local motion=target or route.state.motion;local samples=motion.legs[leg].samples
    local old=samples[bin]
    if old and old.at<now-14*86400 then samples[bin]=nil;old=nil end
    if old and not localOrigin and (old.localOrigin or at<=old.at or (old.u==u and old.progress==progress)) then return false end
    local count=target and math.floor(n) or 1
    if localOrigin and old and not target then
        count=math.min(8,old.n+1);u=(old.u*(count-1)+u)/count;progress=(old.progress*(count-1)+progress)/count
    elseif not localOrigin then count=math.floor(n) end
    for i,s in pairs(samples) do
        if s.at<now-14*86400 then samples[i]=nil
        elseif i<bin and s.progress>progress+.025 or i>bin and s.progress<progress-.025 then return false end
    end
    samples[bin]={u=u,progress=progress,n=count,at=at,localOrigin=localOrigin==true}
    if not target then route.motionCurves[leg]=nil;self.transportMotionSerial=self.transportMotionSerial+1 end
    return true
end
function M:TransportPhase(route,now)
    local a,p,stay,source=self:TransportSchedule(route,1);if not a then return end
    local phase=mod(now-a,p)
    local result={anchor=a,period=p,phase=phase,source=source,key=string.format("%.2f:%.3f:%.2f",a,p,stay)}
    if phase<stay then result.stop=1 end
    local b,_,otherStay=self:TransportSchedule(route,2)
    if not b then return result.stop and result or nil end
    local offset=mod(b-a,p)
    if offset<=stay+1 or p-offset<=otherStay+1 then return end
    result.offset=offset;result.stay=stay;result.otherStay=otherStay
    result.key=result.key..string.format(":%.2f:%.2f",offset,otherStay)
    if phase<stay then result.stop=1
    elseif phase<offset then result.leg=1;result.duration=offset-stay;result.u=(phase-stay)/result.duration
    elseif phase<offset+otherStay then result.stop=2
    else result.leg=2;result.duration=p-offset-otherStay;result.u=(phase-offset-otherStay)/result.duration end
    return result
end
function M:TransportMotionCurve(route,leg)
    local now=self:TransportNow();local cached=route.motionCurves[leg]
    if cached and now<cached.expires then return cached end
    local points={{u=0,progress=0}};points.expires=now+14*86400
    local samples=route.state.motion.legs[leg].samples;local previous=0
    for bin=1,BINS do
        local s=samples[bin]
        if s and s.at>=now-14*86400 and s.progress>=previous then
            table.insert(points,s);previous=s.progress;points.expires=math.min(points.expires,s.at+14*86400)
        elseif s and s.at<now-14*86400 then samples[bin]=nil
        end
    end
    table.insert(points,{u=1,progress=1});route.motionCurves[leg]=points;return points
end
function M:TransportMotionProgress(route,leg,u,duration)
    u=self.Clamp(u,0,1);local curve=self:TransportMotionCurve(route,leg)
    if table.getn(curve)==2 then
        -- A short acceleration/deceleration ramp until recordings replace it.
        local ramp=math.min(.12,6/math.max(1,duration or 100));local total=1-ramp
        if u<ramp then return u*u/(2*ramp*total),false end
        if u>1-ramp then return 1-(1-u)^2/(2*ramp*total),false end
        return (u-ramp/2)/total,false
    end
    for i=2,table.getn(curve) do
        local a,b=curve[i-1],curve[i]
        if u<=b.u then return a.progress+(b.progress-a.progress)*(u-a.u)/math.max(.000001,b.u-a.u),true end
    end
    return 1,true
end
function M:TransportPathPoint(route,legIndex,progress)
    local leg=route.geometry.legs[legIndex];if not leg or leg.length<1 then return end
    local distance=self.Clamp(progress,0,1)*leg.length
    for _,gap in ipairs(leg.gaps) do if math.abs(distance-gap)<math.min(8,leg.length*.003) then return nil,"loading transition" end end
    for _,segment in ipairs(leg.segments) do
        if distance<=segment.to then
            local t=self.Clamp((distance-segment.from)/segment.length,0,1);local a,b=segment.a,segment.b
            -- Atlas axes are (-worldY, -worldX), with screen Y increasing down.
            return {map=a[1],worldX=a[2]+(b[2]-a[2])*t,worldY=a[3]+(b[3]-a[3])*t,z=a[4]+(b[4]-a[4])*t,
                headingX=a[3]-b[3],headingY=a[2]-b[2]}
        end
    end
end
function M:ProjectTransportPath(route,legIndex,map,x,y,z)
    local leg=route.geometry.legs[legIndex];if not leg or leg.length<1 then return end
    local best,progress
    for _,s in ipairs(leg.segments) do if s.a[1]==map then
        local a,b=s.a,s.b;local dx,dy,dz=b[2]-a[2],b[3]-a[3],b[4]-a[4]
        local t=self.Clamp(((x-a[2])*dx+(y-a[3])*dy+(z-a[4])*dz)/(s.length*s.length),0,1)
        local error=(x-a[2]-dx*t)^2+(y-a[3]-dy*t)^2+(z-a[4]-dz*t)^2
        if not best or error<best then best=error;progress=(s.from+s.length*t)/leg.length end
    end end
    if best then return progress,math.sqrt(best) end
end
function M:RecordTransportSighting(pose,shared)
    if pose.source=="estimated" then return end
    local route=pose.route;local runtime=self.transportRuntime[route.id]
    if shared then runtime.previousRemote=self.transportRemote[route.entry]
    else runtime.previousLocal=self.transportLive[route.entry] end
    local direct=self.transportLive[route.entry]
    if shared and direct and self:TransportNow()-direct.at<=1.5 then return end
    if pose.stop then return end
    local phase=self:TransportPhase(route,pose.at);if not phase or not phase.leg then return end
    local progress,error=self:ProjectTransportPath(route,phase.leg,pose.map,pose.worldX,pose.worldY,pose.z)
    if not progress or error>120 then return end
    local fresh=false
    for _,arrival in pairs(route.state.arrivals) do
        if arrival.seenAt and pose.at-arrival.seenAt<2*phase.period and
            (arrival.source=="observed arrival" or arrival.source=="shared arrival" or
            arrival.source=="OctoBus schedule" and self.transportClockReady and arrival.seenAt>self.transportLog.boot) then fresh=true end
    end
    if zMapDB.transportRecord and fresh and phase.u>.003 and phase.u<.997 and progress>.003 and progress<.997 then
        self:MergeTransportMotionSample(route,phase.leg,math.floor(phase.u*BINS)+1,phase.u,progress,1,pose.at,not shared)
    end
    -- Correct phase from a real sighting; never learn a curve from our prediction.
    local lo,hi=0,1
    for i=1,18 do
        local mid=(lo+hi)/2;local p=self:TransportMotionProgress(route,phase.leg,mid,phase.duration)
        if p<progress then lo=mid else hi=mid end
    end
    local delta=((lo+hi)/2-phase.u)*phase.duration
    if math.abs(delta)<=math.min(45,phase.duration*.35) then
        runtime.correction={key=phase.key,delta=delta,at=pose.at,source=shared and "shared sighting" or "local sighting"}
    end
end
function M:EstimateTransportPosition(route,now)
    local phase=self:TransportPhase(route,now);if not phase then return end
    local correction=self.transportRuntime[route.id].correction
    if correction and correction.key==phase.key then phase=self:TransportPhase(route,now+correction.delta) end
    if not phase then return end
    local pose,method
    if phase.stop then
        local stop=route.stops[phase.stop]
        pose={map=stop.map,worldX=stop.data.worldX,worldY=stop.data.worldY,z=stop.data.worldZ,stop=phase.stop};method="dock schedule"
    else
        local progress,learned=self:TransportMotionProgress(route,phase.leg,phase.u,phase.duration)
        pose=self:TransportPathPoint(route,phase.leg,progress);method=learned and "recorded speed profile" or "timed native path"
    end
    if not pose then return end
    local origin=self.data.origins[pose.map];if not origin then return end
    pose.x=origin[1]-pose.worldY;pose.y=origin[2]-pose.worldX
    pose.route=route;pose.source="estimated";pose.method=method;pose.at=now
    if correction and correction.key==phase.key then pose.correctedAt=correction.at;pose.correctionSource=correction.source end
    return pose
end
function M:TransportVehiclePose(route,now)
    now=now or self:TransportNow()
    local pose=self.transportLive[route.entry];local previous=self.transportRuntime[route.id].previousLocal
    local source="local"
    if not pose or now-pose.at>1.5 then
        pose=self.transportRemote[route.entry];previous=self.transportRuntime[route.id].previousRemote;source="shared"
        if not zMapDB.transportSharing or not pose or now-pose.at>5 then pose=nil end
    end
    if pose then
        local display={};for k,v in pairs(pose) do display[k]=v end;display.source=source;display.age=math.max(0,now-pose.at)
        if previous and previous.map==pose.map and previous.stop==pose.stop and
            (not previous.guid or previous.guid==pose.guid) and pose.at>previous.at and pose.at-previous.at<=5 and
            (pose.x-previous.x)^2+(pose.y-previous.y)^2<600^2 then
            local t=self.Clamp((now-pose.at)/(pose.at-previous.at),0,1)
            display.x=previous.x+(pose.x-previous.x)*t;display.y=previous.y+(pose.y-previous.y)*t
            if not pose.stop and previous.sender==pose.sender then
                display.headingX=pose.x-previous.x;display.headingY=pose.y-previous.y
            end
        end
        return display
    end
    if zMapDB.transportPredict and self.transportWorld then return self:EstimateTransportPosition(route,now) end
end
function M:AnimateTransportMarkers(elapsed)
    self.transportAnimationElapsed=self.transportAnimationElapsed+elapsed
    if self.transportAnimationElapsed<.05 then return end
    self.transportAnimationElapsed=0
    if not self.transportWorld or not self.frame or not self.frame:IsShown() or not zMapDB.transportsEnabled then return end
    if self.view.space~="world" then return end
    self:RenderTransportVehicles()
end
