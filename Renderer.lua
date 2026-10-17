-- World overview, preblended art pyramids and bounded terrain tiles.
local M=zMap
local floor,ceil,min,max,abs=math.floor,math.ceil,math.min,math.max,math.abs
local PREFIX="Interface\\AddOns\\z_Map\\"
local LAYERS={"overview","art","artFine","terrain","fine","detail","caves","interior"}
M.pools={}; M.grids={}; M.serial=0
M.stats={drawn=0,loads=0,native=0,overview=0,art=0,interior=0}
local function smooth(t) t=M.Clamp(t,0,1);return t*t*(3-2*t) end
function M:SetLayer(name,alpha)
    local layer=self.layers[name]
    if alpha>.002 then layer.zWanted=self.serial end
    if layer.zAlpha==alpha then return end
    layer.zAlpha=alpha
    if alpha>.002 then layer:SetAlpha(alpha);layer:Show() else layer:Hide() end
end
function M:Texture(poolName,path,x,y,w,h,alpha,u1,u2,v1,v2)
    if not alpha or alpha<=.002 then return true end
    local sx,sy,sw,sh,ul,ur,vt,vb=self:Clip(x,y,w,h)
    if not sx then return true end
    local pool=self.pools[poolName]
    if not pool then pool={used=0,items={},byPath={},free={}};self.pools[poolName]=pool end
    local t=pool.byPath[path]
    if not t then
        if self.loadsLeft<=0 then self.pending=true;pool.pending=true;return false end
        t=table.remove(pool.free)
        if not t then t=self.layers[poolName]:CreateTexture(nil,"ARTWORK") end
        t:SetTexture(path);t.zMapPath=path;pool.byPath[path]=t
        self.loadsLeft=self.loadsLeft-1;self.stats.loads=self.stats.loads+1
    end
    if t.zSerial==self.serial then return true end
    t.zSerial=self.serial;pool.used=pool.used+1;pool.items[pool.used]=t
    if not t.zx or abs(t.zx-sx)>.001 or abs(t.zy-sy)>.001 then
        t:SetPoint("TOPLEFT",self.viewport,"TOPLEFT",sx,-sy);t.zx=sx;t.zy=sy
    end
    if t.zw~=sw then t:SetWidth(sw);t.zw=sw end
    if t.zh~=sh then t:SetHeight(sh);t.zh=sh end
    local du,dv=(u2 or 1)-(u1 or 0),(v2 or 1)-(v1 or 0)
    local a,b,c,d=(u1 or 0)+ul*du,(u1 or 0)+ur*du,(v1 or 0)+vt*dv,(v1 or 0)+vb*dv
    if t.zu1~=a or t.zu2~=b or t.zv1~=c or t.zv2~=d then
        t:SetTexCoord(a,b,c,d);t.zu1=a;t.zu2=b;t.zv1=c;t.zv2=d
    end
    if t.zAlpha~=alpha then t:SetAlpha(alpha);t.zAlpha=alpha end
    if not t.zShown then t:Show();t.zShown=true end
    self.stats.drawn=self.stats.drawn+1
    return true
end
function M:Grid(entries,step)
    local grid=self.grids[entries]
    if grid then return grid end
    grid={cells={},step=step};self.grids[entries]=grid
    for _,tile in ipairs(entries) do
        for x=floor(tile[2]/step),floor((tile[2]+tile[4]-.0001)/step) do
            for y=floor(tile[3]/step),floor((tile[3]+tile[5]-.0001)/step) do
                local key=x*2048+y;local cell=grid.cells[key]
                if not cell then cell={};grid.cells[key]=cell end
                table.insert(cell,tile)
            end
        end
    end
    return grid
end
function M:DrawGrid(name,entries,step,alpha,warm)
    self:SetLayer(name,alpha)
    if alpha<=.002 and not warm then return end
    local grid=self:Grid(entries,step);local v=self.view
    local hw,hh=v.width/v.scale/2,v.height/v.scale/2
    for x=floor((v.x-hw)/step),floor((v.x+hw)/step) do
        for y=floor((v.y-hh)/step),floor((v.y+hh)/step) do
            local cell=grid.cells[x*2048+y]
            if cell then for _,tile in ipairs(cell) do
                if tile.zSerial~=self.serial then
                    tile.zSerial=self.serial
                    self:Texture(name,PREFIX..tile[1],tile[2],tile[3],tile[4],tile[5],1,tile[6],tile[7],tile[8],tile[9])
                end
            end end
        end
    end
end
function M:NativeArt(zone,alpha)
    self:SetLayer("detail",alpha)
    if zone.art==false or alpha<=.002 then return end
    local file=zone.file
    for row=0,2 do for col=0,3 do
        local pw,ph=min(256,1002-col*256),min(256,668-row*256)
        self:Texture("detail","Interface\\WorldMap\\"..file.."\\"..file..(row*4+col+1),
            zone.x+col*256/1002*zone.w,zone.y+row*256/668*zone.h,pw/1002*zone.w,ph/668*zone.h,1,0,pw/256,0,ph/256)
    end end
    for _,tile in ipairs(self.data.overlays[zone.id] or {}) do
        self:Texture("detail",tile[1],zone.x+tile[2]/1002*zone.w,zone.y+tile[3]/668*zone.h,
            tile[4]/1002*zone.w,tile[5]/668*zone.h,1,0,tile[6],0,tile[7])
    end
end
function M:InteriorAlpha(zone)
    local v=self.view
    if zMapDB.interiors=="surface" then return 0 end
    if v.space~=zone.space or not self:Clip(zone.x,zone.y,zone.w,zone.h) then return 0 end
    local coverage=max(zone.w*v.scale/v.width,zone.h*v.scale/v.height)
    return smooth((coverage-.20)/.20)
end
function M:DrawInterior(plan,zone,alpha,layer)
    self:SetLayer(layer,1)
    local pool=self.pools[layer]
    local start=pool and pool.used or 0
    local ready=true
    local sx,sy=zone.w,zone.h
    if zone.cave then sx=1;sy=1 end
    for _,tile in ipairs(plan.tiles) do
        if not self:Texture(layer,PREFIX..tile[1],zone.x+tile[2]*sx,zone.y+tile[3]*sy,
            tile[4]*sx,tile[5]*sy,alpha,tile[6],tile[7],tile[8],tile[9]) then ready=false end
    end
    pool=self.pools[layer]
    if not ready and pool then
        for i=start+1,pool.used do
            local texture=pool.items[i];texture:Hide();texture.zShown=false
        end
    end
end
function M:RenderCaves()
    local v=self.view
    if v.space~="world" or v.scale<=.7 or zMapDB.interiors=="surface" then return end
    local alpha=smooth((v.scale-.7)/.65)
    if zMapDB.interiors=="underground" then alpha=1 end
    if alpha<=.002 then return end
    local visible={}
    for _,cave in ipairs(self.caves) do
        if self:Clip(cave.x,cave.y,cave.w,cave.h) then table.insert(visible,cave) end
    end
    -- Whole cave plans nearest the view centre win; large viewports never
    -- flood the UI with every cave tile. Texture binds share the global budget.
    table.sort(visible,function(a,b)
        local ax,ay=a.x+a.w/2-v.x,a.y+a.h/2-v.y
        local bx,by=b.x+b.w/2-v.x,b.y+b.h/2-v.y
        return ax*ax+ay*ay<bx*bx+by*by
    end)
    local count=0
    for _,cave in ipairs(visible) do
        local n=0
        for _,t in ipairs(cave.tiles) do if self:Clip(cave.x+t[2],cave.y+t[3],t[4],t[5]) then n=n+1 end end
        if count+n<=64 then self:DrawInterior(cave,cave,alpha,"caves");count=count+n end
    end
end
function M:RenderInteriors()
    if self.view.space~="world" then return end
    for id,plan in pairs(self.interiors) do
        local zone=self.byID[id]
        if zone and zone.file==plan.file then
            local alpha=self:InteriorAlpha(zone)
            if alpha>.002 then
                self:DrawInterior(plan,zone,alpha,"interior")
            end
        end
    end
    self.stats.interior=self.pools.interior and self.pools.interior.used or 0
end
function M:Terrain(mix)
    if mix<=.002 then self:SetLayer("terrain",0);self:SetLayer("fine",0);return 0 end
    local v=self.view;local hw,hh=v.width/v.scale/2,v.height/v.scale/2
    local size=self.data.tileSize
    self.selections=self.selections or {};local selections=self.selections
    local used,count=0,0
    for mapID,entries in pairs(self.data.tiles) do
        local origin=self.data.origins[mapID]
        if (v.space=="world" and origin) or v.space==tostring(mapID) then
            local ox,oy=origin and origin[1] or 0,origin and origin[2] or 0
            local x1,x2=max(0,floor((v.x-hw-ox)/size+32)),min(63,floor((v.x+hw-ox)/size+32))
            local y1,y2=max(0,floor((v.y-hh-oy)/size+32)),min(63,floor((v.y+hh-oy)/size+32))
            used=used+1;local s=selections[used] or {};selections[used]=s
            s[1]=entries;s[2]=ox;s[3]=oy;s[4]=x1;s[5]=x2;s[6]=y1;s[7]=y2
            for x=x1,x2 do
                if count>=64 then break end
                for y=y1,y2 do
                    if entries[x*64+y] then count=count+1 end
                    if count>=64 then break end
                end
            end
        end
    end
    local native=smooth((64-count)/28)
    if count==0 then native=0 end
    local high=mix*native
    local low=high<.999 and mix*(1-native)/(1-high) or 0
    -- Keep a coarse fallback resident until every visible fine tile is ready.
    if v.space=="world" then self:DrawGrid("terrain",self.data.lod,size*8,low,true) end
    self:SetLayer("fine",high)
    if high>.002 then
        local total=0
        for i=1,used do
            local s=selections[i]
            for x=s[4],s[5] do for y=s[6],s[7] do
                local path=s[1][x*64+y]
                if path and total<64 then
                    self:Texture("fine",path,s[2]+(x-32)*size,s[3]+(y-32)*size,size,size,1)
                    total=total+1
                end
            end end
        end
        local pool=self.pools.fine
        if pool and pool.pending then
            self:SetLayer("fine",0)
            if v.space=="world" then self:SetLayer("terrain",mix) end
            high=0
        end
    end
    self.stats.native=self.pools.fine and self.pools.fine.used or 0
    return v.space=="world" and mix or high
end
function M:Render()
    if not self.viewport then return end
    self.serial=self.serial+1;self.loadsLeft=4;self.pending=false
    local st=self.stats;st.drawn=0;st.loads=0;st.native=0;st.art=0;st.overview=0;st.interior=0
    for _,pool in pairs(self.pools) do pool.used=0;pool.pending=false end
    local v=self.view
    local terrain=smooth((v.scale-.20)/.44)
    if zMapDB.style=="painted" then terrain=0 elseif zMapDB.style=="terrain" then terrain=1 end
    if v.space=="world" then
        self:SetLayer("overview",1)
        for _,t in ipairs(self.data.overview) do
            self:Texture("overview",PREFIX..t[1],t[2],t[3],t[4],t[5],1,t[6],t[7],t[8],t[9])
        end
        st.overview=self.pools.overview and self.pools.overview.used or 0
        self:RenderInteriors()
        self:RenderCaves()
        local zoom=v.scale/self:MinScale()
        local near=smooth((zoom-1.7)/2.3)
        local terrainMix=terrain
        terrain=terrainMix*near
        local art=terrain<.999 and near*(1-terrainMix)/(1-terrain) or 0
        if art>.002 then
            local levels=self.data.artLevels;local hi=1;local blend=0
            for i=2,table.getn(levels) do
                if v.scale>levels[i-1].px*1.2 then
                    hi=i;blend=smooth((v.scale/levels[i-1].px-1.2)/.6)
                end
            end
            -- Large viewports use a coarser pyramid level instead of flooding
            -- the UI with fine tiles. Each participating level stays below 64.
            local bounds=self.data.bounds
            local spanX=min(v.width/v.scale,bounds[3]-bounds[1])
            local spanY=min(v.height/v.scale,bounds[4]-bounds[2])
            while hi>1 and (ceil(spanX/levels[hi].step)+1)*(ceil(spanY/levels[hi].step)+1)>64 do
                hi=hi-1;blend=1
            end
            local lo=max(1,hi-1)
            if hi==1 then blend=0 end
            local high=art*blend;local low=high<.999 and art*(1-blend)/(1-high) or 0
            if lo==hi then low=art end
            self:DrawGrid("art",levels[lo].tiles,levels[lo].step,low,true)
            if hi~=lo then self:DrawGrid("artFine",levels[hi].tiles,levels[hi].step,high) end
            local pool=self.pools.artFine
            if hi~=lo and pool and pool.pending then self:SetLayer("artFine",0);self:SetLayer("art",art) end
            st.art=(self.pools.art and self.pools.art.used or 0)+(self.pools.artFine and self.pools.artFine.used or 0)
        end
        self:Terrain(terrain)
        if self.focus and self.focus.detail and not self.interiors[self.focus.id] then self:NativeArt(self.focus,1-terrain) end
    else
        -- Load the small floor painting before requesting close-up resources.
        -- It remains the fallback while a native tile set is being filled.
        if self.focus and self.focus.space==v.space then self:NativeArt(self.focus,1) end
        local actual=self:Terrain(terrain)
        local plan=(zMapDB.floorArt or table.getn(self.floors[v.space] or {})>1) and self.interiorSpaces[v.space]
        self:SetLayer("detail",plan and 1 or 1-actual)
    end
    for _,name in ipairs(LAYERS) do
        if self.layers[name].zWanted~=self.serial then self:SetLayer(name,0) end
    end
    for _,pool in pairs(self.pools) do
        for path,t in pairs(pool.byPath) do
            if t.zSerial~=self.serial then
                if t.zShown then t:Hide();t.zShown=false end
                t:ClearAllPoints();t:SetTexture(nil);t.zMapPath=nil
                t.zx=nil;t.zy=nil;t.zw=nil;t.zh=nil;t.zu1=nil;t.zAlpha=nil
                pool.byPath[path]=nil;table.insert(pool.free,t)
            end
        end
        for i=pool.used+1,pool.lastUsed or 0 do pool.items[i]=nil end
        pool.lastUsed=pool.used
    end
    self.stats.caves=self.pools.caves and self.pools.caves.used or 0
    self:UpdateLayerButton();self:RenderMarkers();self.dirty=self.pending
end

function M:PlaceMarker(marker,x,y,space)
    if space~=self.view.space then marker:Hide(); return end
    local sx,sy=self:ToScreen(x,y)
    if sx<10 or sy<10 or sx>self.view.width-10 or sy>self.view.height-10 then marker:Hide(); return end
    marker:ClearAllPoints(); marker:SetPoint("CENTER",self.viewport,"TOPLEFT",sx,-sy); marker:Show()
end
function M:RenderMarkers()
    if not self.playerMarker then return end
    self:RenderGatherMarkers()
    local p=self.player
    if p then
        self:PlaceMarker(self.playerMarker,p.x,p.y,p.space)
        -- The stock minimap arrow is a 3D model. A familiar unrotated map dot
        -- remains correct without any binary extension or facing API.
    else self.playerMarker:Hide() end
    for i,marker in ipairs(self.groupMarkers) do
        local member=self.group and self.group[i]
        marker.member=member
        if member then
            local r,g,b=self:ClassColor(member.class)
            if marker.r~=r or marker.g~=g or marker.b~=b then
                marker.texture:SetVertexColor(r,g,b);marker.r=r;marker.g=g;marker.b=b
            end
            self:PlaceMarker(marker,member.x,member.y,member.space)
            if self.hoveredGroupMarker==marker then self:ShowGroupTooltip(marker) end
        else marker:Hide() end
    end
    for i,pin in ipairs(zMapDB.pins) do
        local marker=self.pinMarkers[i]
        if not marker then
            marker=self:MakeMarker(1,.75,.22,12)
            marker:EnableMouse(true)
            local index=i
            marker:SetScript("OnEnter",function()
                GameTooltip:SetOwner(marker,"ANCHOR_RIGHT"); GameTooltip:SetText("zMap pin "..index)
                GameTooltip:AddLine("Right-click to remove",.65,.72,.8); GameTooltip:Show()
            end)
            marker:SetScript("OnLeave",function() GameTooltip:Hide() end)
            marker:SetScript("OnMouseUp",function()
                if arg1=="RightButton" then table.remove(zMapDB.pins,index); self.dirty=true; GameTooltip:Hide() end
            end)
            self.pinMarkers[i]=marker
        end
        self:PlaceMarker(marker,pin.x,pin.y,pin.space)
    end
    for i=table.getn(zMapDB.pins)+1,table.getn(self.pinMarkers) do self.pinMarkers[i]:Hide() end
end
