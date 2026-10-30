-- Observed resting footprints, using the server's current IsResting flag only.
local M=zMap
local floor,abs,min,max=math.floor,math.abs,math.min,math.max
local CELL,BUCKET,LIMIT,DRAW=8,512,24000,256
local ART="Interface\\AddOns\\z_Map\\Media\\RestedCloud"
local NEIGHBORS={{-1,-1},{0,-1},{1,-1},{-1,0},{1,0},{-1,1},{0,1},{1,1}}
local function finite(n) return type(n)=="number" and n==n and abs(n)<100000 end
local function cellKey(x,y) return x..":"..y end
local function recordKey(r) return r[1]..":"..r[2]..":"..r[3]..":"..r[4]..":"..(r[5] and floor(r[5]/8) or "u") end
local function valid(r)
    return type(r)=="table" and finite(r[1]) and r[1]>=0 and r[1]==floor(r[1]) and
        type(r[2])=="string" and string.len(r[2])<=32 and finite(r[3]) and r[3]==floor(r[3]) and
        finite(r[4]) and r[4]==floor(r[4]) and abs(r[3])<12500 and abs(r[4])<12500 and
        (r[5]==nil or finite(r[5])) and (r[2]~="world" or r[1]==0 or r[1]==1)
end
function M:RemoveRestedCell(node)
    if node.prev then node.prev.next=node.next else self.restOldest=node.next end
    if node.next then node.next.prev=node.prev else self.restNewest=node.prev end
    node.bucket[node.key]=nil;self.restCells[node.key]=nil;self.restLog[node.key]=nil
    if not next(node.bucket) then node.grid[node.bucketKey]=nil end
    if not next(node.grid) then self.restGrid[node.record[2]]=nil end
    self.restCount=self.restCount-1;self.restRevision=self.restRevision+1
end
function M:InsertRestedCell(record)
    if self.restCount>=LIMIT then self:RemoveRestedCell(self.restOldest) end
    local origin=self.data.origins[record[1]] or {0,0}
    local x,y=origin[1]+(record[3]+.5)*CELL,origin[2]+(record[4]+.5)*CELL
    local grid=self.restGrid[record[2]]
    if not grid then grid={};self.restGrid[record[2]]=grid end
    local bucketKey=cellKey(floor(x/BUCKET),floor(y/BUCKET));local bucket=grid[bucketKey]
    if not bucket then bucket={};grid[bucketKey]=bucket end
    local key=recordKey(record)
    local node={record=record,key=key,x=x,y=y,bucket=bucket,grid=grid,bucketKey=bucketKey,prev=self.restNewest}
    if node.prev then node.prev.next=node else self.restOldest=node end
    self.restNewest=node;bucket[key]=node;self.restCells[key]=node;self.restLog[key]=record
    self.restCount=self.restCount+1;self.restRevision=self.restRevision+1
end
function M:InitializeRested()
    zMapDB.restOverlay=zMapDB.restOverlay~=false
    self.restCells={};self.restGrid={};self.restCount=0;self.restRevision=0
    self.restOldest=nil;self.restNewest=nil
    local saved=zMapDB.rested
    if type(saved)~="table" then saved={version=1,profiles={}};zMapDB.rested=saved end
    -- Preserve an unfamiliar schema instead of overwriting it.
    if saved.version~=1 then self.restUnavailable="unsupported saved-data version";return end
    if type(saved.profiles)~="table" then saved.profiles={} end
    local realm=GetRealmName and GetRealmName() or "OctoWoW"
    local faction=UnitFactionGroup and UnitFactionGroup("player") or "unknown"
    local profile=tostring(realm).." / "..tostring(faction)
    local log=saved.profiles[profile];if type(log)~="table" then log={} end
    self.restLog={};saved.profiles[profile]=self.restLog
    for _,record in pairs(log) do
        if valid(record) and self.restCount<LIMIT and not self.restCells[recordKey(record)] then self:InsertRestedCell(record) end
    end
    self.restWorld=false;self.restElapsed=0;self.restSettle=1.5
    local driver=CreateFrame("Frame");self.restDriver=driver
    for _,name in ipairs({"PLAYER_ENTERING_WORLD","PLAYER_LEAVING_WORLD","PLAYER_UPDATE_RESTING",
        "ZONE_CHANGED","ZONE_CHANGED_INDOORS","ZONE_CHANGED_NEW_AREA"}) do driver:RegisterEvent(name) end
    driver:SetScript("OnEvent",function()
        if event=="PLAYER_ENTERING_WORLD" then self.restWorld=true;self.restSettle=1.5
        elseif event=="PLAYER_LEAVING_WORLD" then self.restWorld=false
        else self.restSettle=.75 end
        self.restLastKey=nil;self.restState=nil
    end)
end
function M:ObserveRested(p,resting)
    if not self.restLog or not p or not p.zone or not finite(p.x) or not finite(p.y) then return end
    local map=p.zone.map;local origin=self.data.origins[map] or {0,0}
    local r={map,p.space,floor((p.x-origin[1])/CELL),floor((p.y-origin[2])/CELL),finite(p.z) and p.z or nil}
    if not valid(r) then return end
    local key=recordKey(r)
    if self.restLastKey==key and self.restLastState==resting then return end
    self.restLastKey=key;self.restLastState=resting
    local node=self.restCells[key]
    if resting then
        if not node then self:InsertRestedCell(r) end
    elseif node then self:RemoveRestedCell(node) end
    -- A later height-aware negative observation supersedes an older unknown
    -- height record in this cell, too. Unknown altitude is never a new floor.
    if not resting and r[5] then
        r[5]=nil;node=self.restCells[recordKey(r)];if node then self:RemoveRestedCell(node) end
    end
end
function M:UpdateRested(elapsed,pose)
    if not self.restLog or not self.restWorld then return end
    self.restSettle=max(0,(self.restSettle or 0)-elapsed)
    self.restElapsed=(self.restElapsed or 0)+elapsed
    if self.restElapsed<.5 then return end
    self.restElapsed=0
    if type(IsResting)~="function" then self.restUnavailable="IsResting unavailable";return end
    local ok,state=pcall(IsResting)
    if not ok or state~=nil and state~=false and state~=true and state~=0 and state~=1 then
        self.restUnavailable="resting state unavailable";return
    end
    self.restUnavailable=nil;state=state==true or state==1
    if self.restState~=state then self.restState=state;self.restSettle=.75;self.restLastKey=nil;return end
    if self.restSettle>0 or WorldMapFrame and WorldMapFrame:IsShown() or UnitOnTaxi and UnitOnTaxi("player") or
        UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return end
    if not state and self.restCount==0 then return end
    if not pose then
        if self.mapChanged or not self.player then self:SamplePlayer(true) end
        pose=self:ReadFollowPlayer()
    end
    self:ObserveRested(pose,state)
end
local function quad(list,origin,x,y,w,h,mask)
    table.insert(list,{origin[1]+x*CELL,origin[2]+y*CELL,w*CELL,h*CELL,mask})
end
function M:RestedQuads()
    local v=self.view;local p=self.player
    local band=self~=M and p and finite(p.z) and floor(p.z/8) or false
    local hw,hh=v.width/v.scale/2+CELL,v.height/v.scale/2+CELL
    local left,right=floor((v.x-hw)/BUCKET),floor((v.x+hw)/BUCKET)
    local top,bottom=floor((v.y-hh)/BUCKET),floor((v.y+hh)/BUCKET)
    local cache=rawget(self,"restCache")
    if cache and cache.revision==M.restRevision and cache.space==v.space and cache.band==band and
        cache.left==left and cache.right==right and cache.top==top and cache.bottom==bottom then return cache.quads end
    local groups={};local grid=M.restGrid[v.space] or {}
    for x=left,right do for y=top,bottom do
        for _,node in pairs(grid[cellKey(x,y)] or {}) do
            local r=node.record
            if not band or not r[5] or abs(floor(r[5]/8)-band)<=1 then
                local group=groups[r[1]]
                if not group then group={cells={},points={}};groups[r[1]]=group end
                local key=cellKey(r[3],r[4])
                if not group.cells[key] then group.cells[key]=true;table.insert(group.points,{r[3],r[4]}) end
            end
        end
    end end
    local list={}
    for map,group in pairs(groups) do
        local origin=M.data.origins[map] or {0,0};local interior={}
        table.sort(group.points,function(a,b) if a[2]==b[2] then return a[1]<b[1] end;return a[2]<b[2] end)
        for _,point in ipairs(group.points) do
            local x,y=point[1],point[2];local mask,power=0,1
            for _,offset in ipairs(NEIGHBORS) do
                if group.cells[cellKey(x+offset[1],y+offset[2])] then mask=mask+power end
                power=power*2
            end
            if mask==255 then interior[cellKey(x,y)]=true else quad(list,origin,x,y,1,1,mask) end
        end
        -- Merge solid interiors; feathered boundary cells retain their own
        -- masks. A learned city does not need a texture for every solid cell.
        for _,point in ipairs(group.points) do
            local x,y=point[1],point[2]
            if interior[cellKey(x,y)] then
                local w,h=1,1
                while interior[cellKey(x+w,y)] do w=w+1 end
                local more=true
                while more do
                    for dx=0,w-1 do if not interior[cellKey(x+dx,y+h)] then more=false;break end end
                    if more then h=h+1 end
                end
                for dx=0,w-1 do for dy=0,h-1 do interior[cellKey(x+dx,y+dy)]=nil end end
                quad(list,origin,x,y,w,h,255)
            end
        end
    end
    self.restCache={revision=M.restRevision,space=v.space,band=band,left=left,right=right,top=top,bottom=bottom,quads=list}
    return list
end
function M:HideRestedOverlay()
    if rawget(self,"restShown")==0 then return end
    for _,t in ipairs(rawget(self,"restTextures") or {}) do
        if t.zShown then t:Hide();t.zShown=false end
    end
    self.restShown=0
    local drawn=rawget(self,"restDrawn") or {}
    for i=table.getn(drawn),1,-1 do drawn[i]=nil end
end
function M:ReprojectRestedOverlay()
    for _,entry in ipairs(rawget(self,"restDrawn") or {}) do
        local q,t=entry.quad,entry.texture
        local x,y,w,h,a,b,c,d=self:Clip(q[1],q[2],q[3],q[4])
        if x then self:PositionClippedTexture(t,x,y,w,h,a,b,c,d,entry.alpha,entry.u1,entry.u2,entry.v1,entry.v2)
        elseif t.zShown then t:Hide();t.zShown=false end
    end
end
function M:RenderRestedOverlay()
    if self.hud or not self.layers.rested or not zMapDB.restOverlay or not M.restGrid or not M.restGrid[self.view.space] or self.view.scale*CELL<=.6 then
        if rawget(self,"restTextures") then self:HideRestedOverlay() end;return
    end
    local list=self:RestedQuads();local v=self.view
    local candidates=rawget(self,"restCandidates") or {};self.restCandidates=candidates
    local used=0
    for _,q in ipairs(list) do
        if self:Clip(q[1],q[2],q[3],q[4]) then used=used+1;candidates[used]=q;q.distance=(q[1]+q[3]/2-v.x)^2+(q[2]+q[4]/2-v.y)^2 end
    end
    for i=used+1,table.getn(candidates) do candidates[i]=nil end
    if used>DRAW then table.sort(candidates,function(a,b) return a.distance<b.distance end) end
    local textures=rawget(self,"restTextures") or {};self.restTextures=textures
    local drawn=rawget(self,"restDrawn") or {};self.restDrawn=drawn
    local alpha=.13*M.Clamp((v.scale*CELL-.6)/.8,0,1)
    used=min(used,DRAW)
    for i=1,used do
        local q=candidates[i];local t=textures[i]
        if not t then
            t=self.layers.rested:CreateTexture(nil,"ARTWORK");textures[i]=t
            t:SetTexture(ART);t:SetVertexColor(.22,.9,.38,1)
        end
        local column,row=math.mod(q[5],16),floor(q[5]/16)
        local entry=drawn[i] or {};drawn[i]=entry
        entry.quad=q;entry.texture=t;entry.alpha=alpha
        entry.u1=(column*32+1)/512;entry.u2=(column*32+31)/512
        entry.v1=(row*32+1)/512;entry.v2=(row*32+31)/512
    end
    for i=used+1,table.getn(textures) do if textures[i].zShown then textures[i]:Hide();textures[i].zShown=false end end
    for i=used+1,table.getn(drawn) do drawn[i]=nil end
    self.restShown=used;self:ReprojectRestedOverlay()
end
function M:SetRestedOverlay(enabled)
    zMapDB.restOverlay=enabled==true;self.dirty=true
    if self.viewport then self:RenderRestedOverlay() end
    if self.miniContext then self.miniContext:RenderRestedOverlay() end
    self:RefreshSettingsPanel()
end
function M:RestedStatus()
    local state=self.restUnavailable or (self.restState==nil and "waiting for server resting state" or
        self.restState and "resting here" or "not resting here")
    self:Print("Rested areas: "..(zMapDB.restOverlay and "on" or "off").." | "..(self.restCount or 0)..
        " observed cells | "..state..". Coverage is learned, not exact server boundaries.")
end
