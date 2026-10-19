-- Saved observations are always unknown on load. Only a fresh native snapshot
-- can mark a location live; GUIDs are deliberately not persisted.
local M=zMap
local LIMIT=20000
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<100000 end
local function integer(n) return type(n)=="number" and n==math.floor(n) and n>=0 and n<=4294967295 end
local function cell(n) return math.floor(n/8) end
local function realmName()
    local realm=GetRealmName and GetRealmName()
    if type(realm)~="string" or realm=="" then realm="OctoWoW" end
    return realm
end
function M:IndexGatherLocation(node)
    local map,key=node.record.map,node.definition.key
    local maps=self.gatherLocationIndex[map]
    if not maps then maps={};self.gatherLocationIndex[map]=maps end
    local resource=maps[key]
    if not resource then resource={};maps[key]=resource end
    local x,y=cell(node.record.worldX),cell(node.record.worldY)
    local column=resource[x]
    if not column then column={};resource[x]=column end
    local bucket=column[y]
    if not bucket then bucket={};column[y]=bucket end
    table.insert(bucket,node)
    -- A separate coarse atlas index bounds history work during map rendering.
    local spaces=self.gatherHistoryGrid[node.space]
    if not spaces then spaces={};self.gatherHistoryGrid[node.space]=spaces end
    local grid=spaces[key]
    if not grid then grid={};spaces[key]=grid end
    x=math.floor(node.x/512);y=math.floor(node.y/512)
    column=grid[x]
    if not column then column={};grid[x]=column end
    bucket=column[y]
    if not bucket then bucket={};column[y]=bucket end
    table.insert(bucket,node)
end
function M:FindGatherLocation(map,key,x,y,z)
    local maps=self.gatherLocationIndex[map]
    local resource=maps and maps[key]
    if not resource then return end
    local cx,cy=cell(x),cell(y);local best,bestDistance
    for ix=cx-1,cx+1 do
        local column=resource[ix]
        if column then for iy=cy-1,cy+1 do
            local bucket=column[iy]
            if bucket then for _,node in ipairs(bucket) do
                local record=node.record
                local dx,dy,dz=record.worldX-x,record.worldY-y,record.worldZ-z
                local distance=dx*dx+dy*dy+dz*dz
                if distance<=.5625 and (not bestDistance or distance<bestDistance) then best=node;bestDistance=distance end
            end end
        end end
    end
    return best
end
function M:MakeGatherLocation(record,definition)
    local origin=self.data.origins[record.map]
    local ox,oy=0,0
    if origin then ox=origin[1];oy=origin[2] end
    local node={id=record.id,entry=record.entry,record=record,definition=definition,
        x=ox-record.worldY,y=oy-record.worldX,z=record.worldZ,
        space=(record.map==0 or record.map==1) and "world" or tostring(record.map)}
    table.insert(self.gatherLogNodes,node)
    self:IndexGatherLocation(node)
    if self.GatherRecordHash then self.gatherLogChecksum=math.mod((self.gatherLogChecksum or 0)+self:GatherRecordHash(record),2147483647) end
    return node
end
function M:InitializeGatherLog()
    self.gatherLogNodes={};self.gatherLocationIndex={};self.gatherHistoryGrid={};self.gatherLogChecksum=0
    local saved=zMapDB.gatherLog
    if type(saved)~="table" then saved={version=1,realms={}};zMapDB.gatherLog=saved end
    -- Preserve unfamiliar future schemas rather than rewriting their data.
    if saved.version~=1 then self.gatherLog=nil;return end
    if type(saved.realms)~="table" then saved.realms={} end
    local realm=realmName();local log=saved.realms[realm]
    if type(log)~="table" then log={nextID=1,locations={}};saved.realms[realm]=log end
    if type(log.locations)~="table" then log.locations={} end
    local valid={};local ids={};local nextID=1
    for _,record in ipairs(log.locations) do
        if table.getn(valid)>=LIMIT then break end
        if type(record)=="table" and integer(record.map) and integer(record.entry) and record.entry>0 and
            finite(record.worldX) and finite(record.worldY) and finite(record.worldZ) then
            local info=self.gatherEntries[record.entry]
            if not info and self.gatherLabels[record.category] and type(record.name)=="string" and string.len(record.name)<=160 then
                info={category=record.category,name=record.name};self.gatherEntries[record.entry]=info
            end
            if info then
                local definition=self.gatherDefinitions[self:AddGatherDefinition(info)]
                if not self:FindGatherLocation(record.map,definition.key,record.worldX,record.worldY,record.worldZ) then
                    if not integer(record.id) or record.id<1 or ids[record.id] then record.id=nextID end
                    ids[record.id]=true;nextID=math.max(nextID,record.id+1)
                    record.name=definition.name;record.category=definition.category
                    record.live=nil;record.guid=nil -- Never trust persisted availability.
                    self:MakeGatherLocation(record,definition);table.insert(valid,record)
                end
            end
        end
    end
    log.locations=valid;log.nextID=nextID;self.gatherLog=log
end
function M:ResetGatherLogLive()
    for _,node in ipairs(self.gatherNodes or {}) do if node.location then node.location.live=nil end end
    self.gatherPlayerZ=nil
end
function M:StoreGatherLocation(map,entry,definition,x,y,z)
    if not self.gatherLog then return end
    local location=self:FindGatherLocation(map,definition.key,x,y,z)
    local added=false
    if not location then
        if table.getn(self.gatherLog.locations)>=LIMIT then self.gatherLogFull=true;return end
        local record={id=self.gatherLog.nextID,map=map,entry=entry,worldX=x,worldY=y,worldZ=z,
            name=definition.name,category=definition.category}
        self.gatherLog.nextID=self.gatherLog.nextID+1;table.insert(self.gatherLog.locations,record)
        location=self:MakeGatherLocation(record,definition);added=true
    end
    return location,added
end
function M:RememberGatherNode(node,map,x,y,z)
    local location,added=self:StoreGatherLocation(map,node.entry,node.definition,x,y,z)
    if not location then return end
    location.record.lastSeen=time and time() or 0
    location.record.shared=nil
    location.live=node;node.location=location
    if added and self.QueueGatherShare then self:QueueGatherShare(location) end
    return location
end
function M:VisitLoggedGatherLocations(visit)
    local v=self.view;local resources=self.gatherHistoryGrid[v.space]
    if not resources then return end
    local hw,hh=v.width/v.scale/2,v.height/v.scale/2
    if self.hud then hw=math.sqrt(hw*hw+hh*hh);hh=hw end
    local x1,x2=math.floor((v.x-hw)/512),math.floor((v.x+hw)/512)
    local y1,y2=math.floor((v.y-hh)/512),math.floor((v.y+hh)/512)
    for key,grid in pairs(resources) do
        if self:GatherEnabled(self.gatherDefinitions[key]) then
            for x,column in pairs(grid) do if x>=x1 and x<=x2 then
                for y,bucket in pairs(column) do if y>=y1 and y<=y2 then
                    for _,node in ipairs(bucket) do if not node.live and visit(node)==false then return end end
                end end
            end end
        end
    end
end
