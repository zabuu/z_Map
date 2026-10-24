-- All atlas art, terrain, pins and input share one physical-yard coordinate system.
-- This module deliberately uses only the Lua 5.0 subset available in Vanilla.
zMap = { version = "1.8.3", data = zMapData, interiors = zMapInteriors or {}, caves = zMapCaves or {}, interiorSpaces = zMapInteriorSpaces or {} }
local M = zMap
M.smoothFollow=true
local min, max, abs, exp = math.min, math.max, math.abs, math.exp
M.view = {x=23000,y=16000,scale=.02,width=900,height=600,space="world"}
M.byFile, M.byID, M.byArea, M.spaceBounds, M.floors = {}, {}, {}, {}, {}
for _,zone in ipairs(M.data.zones) do
    M.byFile[string.lower(zone.file)] = zone
    M.byID[zone.id] = zone
    M.byArea[zone.area] = zone
    if zone.space~="world" then
        M.floors[zone.space]=M.floors[zone.space] or {}
        table.insert(M.floors[zone.space],zone)
    end
end
for _,list in pairs(M.floors) do table.sort(list,function(a,b) return a.id<b.id end) end
for _,zone in ipairs(M.caves) do M.byID[zone.id]=zone;M.byFile[zone.file]=zone end
for _,zone in ipairs(M.data.continents) do
    M.byFile[string.lower(zone.file)] = zone
end

function M.Clamp(value, lo, hi) return max(lo,min(hi,value)) end
function M:ToScreen(x,y)
    local v=self.view
    return (x-v.x)*v.scale+v.width/2,(y-v.y)*v.scale+v.height/2
end
function M:ToWorld(x,y)
    local v=self.view
    return v.x+(x-v.width/2)/v.scale,v.y+(y-v.height/2)/v.scale
end
function M:ZonePoint(zone,x,y) return zone.x+x*zone.w,zone.y+y*zone.h end
function M:Bounds()
    if self.view.space=="world" then return unpack(self.data.bounds) end
    local cached=self.spaceBounds[self.view.space]
    if cached then return unpack(cached) end
    local l,t,r,b
    for _,z in ipairs(self.data.zones) do
        if z.space==self.view.space then
            l=min(l or z.x,z.x); t=min(t or z.y,z.y)
            r=max(r or z.x+z.w,z.x+z.w); b=max(b or z.y+z.h,z.y+z.h)
        end
    end
    cached={l or -2000,t or -2000,r or 2000,b or 2000}
    self.spaceBounds[self.view.space]=cached
    return unpack(cached)
end
function M:MinScale()
    local l,t,r,b=self:Bounds()
    return min(self.view.width/(r-l+600),self.view.height/(b-t+600))*.93
end
function M:Constrain()
    local v=self.view
    local minimum=self:MinScale()
    v.scale=self.Clamp(v.scale,minimum,4)
    local l,t,r,b=self:Bounds()
    if v.scale<=minimum*1.001 then v.x=(l+r)/2;v.y=(t+b)/2;return end
    local padX,padY=v.width/(v.scale*2),v.height/(v.scale*2)
    -- A half viewport of ocean makes cursor-centred zoom usable along the coast.
    v.x=self.Clamp(v.x,l-padX*.7,r+padX*.7)
    v.y=self.Clamp(v.y,t-padY*.7,b+padY*.7)
end
function M:Fit(l,t,r,b,space)
    local v=self.view
    v.space=space or "world"
    self.animation=nil
    v.x=(l+r)/2; v.y=(t+b)/2
    v.scale=min(v.width/max(10,r-l),v.height/max(10,b-t))*.9
    self:Constrain(); self.dirty=true
end
function M:World()
    self.focus=nil
    self:Fit(unpack(self.data.bounds))
end
function M:FocusZone(zone)
    self.focus=zone
    self:Fit(zone.x,zone.y,zone.x+zone.w,zone.y+zone.h,zone.space)
end
function M:CycleLayer()
    self.animation=nil
    if self.view.space=="world" then
        local nextMode={auto="surface",surface="underground",underground="auto"}
        zMapDB.interiors=nextMode[zMapDB.interiors] or "auto"
    else
        local list=self.floors[self.view.space] or {}
        if table.getn(list)>1 then
            local index=0
            for i,zone in ipairs(list) do if zone==self.focus then index=i end end
            zMapDB.follow=false;self:FocusZone(list[math.mod(index,table.getn(list))+1])
        else zMapDB.floorArt=not zMapDB.floorArt end
    end
    self.dirty=true
end
function M:UpdateLayerButton()
    if not self.layerButton then return end
    local available=self.view.space=="world" or self.interiorSpaces[self.view.space] or table.getn(self.floors[self.view.space] or {})>1
    if available then self.layerButton:Show() else self.layerButton:Hide() end
    local label="Layer: "..(zMapDB.interiors or "auto")
    if self.view.space~="world" then
        local list=self.floors[self.view.space] or {}
        if table.getn(list)>1 then
            local index=1
            for i,zone in ipairs(list) do if zone==self.focus then index=i end end
            label="Floor: "..index.."/"..table.getn(list)
        else label=zMapDB.floorArt and "Layer: plan" or "Layer: geometry" end
    end
    if self.layerLabel~=label then self.layerButton.label:SetText(label);self.layerLabel=label end
end
function M:Continent(mapID)
    self.focus=nil
    local l,t,r,b
    for _,z in ipairs(self.data.zones) do
        if z.map==mapID then
            l=min(l or z.x,z.x); t=min(t or z.y,z.y)
            r=max(r or z.x+z.w,z.x+z.w); b=max(b or z.y+z.h,z.y+z.h)
        end
    end
    if l then self:Fit(l,t,r,b,"world") end
end
function M:Zoom(delta,screenX,screenY)
    local v=self.view
    local target=self.animation and self.animation.target or v.scale
    target=self.Clamp(target*exp(delta*.24),self:MinScale(),4)
    local wx,wy=self:ToWorld(screenX,screenY)
    self.animation={target=target,x=wx,y=wy,sx=screenX,sy=screenY}
    if zMapDB then zMapDB.follow=false end
end
function M:Animate(elapsed)
    local a,v=self.animation,self.view
    if not a then return false end
    local scale=v.scale+(a.target-v.scale)*(1-exp(-18*min(elapsed,.1)))
    local done=abs(scale-a.target)<max(.000001,a.target*.0005)
    if done then scale=a.target end
    v.scale=scale
    v.x=a.x-(a.sx-v.width/2)/scale
    v.y=a.y-(a.sy-v.height/2)/scale
    self:Constrain()
    if done then self.animation=nil end
    self.dirty=true
    return true
end
function M:ZoneAt(x,y)
    local best,area
    for _,z in ipairs(self.data.zones) do
        if z.space==self.view.space and x>=z.x and y>=z.y and x<=z.x+z.w and y<=z.y+z.h then
            local size=z.w*z.h
            if not area or size<area then best=z; area=size end
        end
    end
    return best
end
function M:Search(query)
    query=string.lower(query or "")
    local results={}
    for _,z in ipairs(self.data.zones) do
        if query~="" and (string.find(string.lower(z.name),query,1,true) or
            string.find(string.lower(z.file),query,1,true)) then
            table.insert(results,z)
        end
    end
    for _,z in ipairs(self.caves) do
        if query~="" and string.find(string.lower(z.name),query,1,true) then table.insert(results,z) end
    end
    table.sort(results,function(a,b)
        if a.space=="world" and b.space~="world" then return true end
        if a.space~="world" and b.space=="world" then return false end
        if a.name==b.name then return tostring(a.id)<tostring(b.id) end
        return a.name<b.name
    end)
    return results
end
function M:Clip(x,y,w,h)
    local sx,sy=self:ToScreen(x,y)
    local sw,sh=w*self.view.scale,h*self.view.scale
    local left,top=max(0,sx),max(0,sy)
    local right,bottom=min(self.view.width,sx+sw),min(self.view.height,sy+sh)
    if right<=left or bottom<=top then return end
    return left,top,right-left,bottom-top,(left-sx)/sw,(right-sx)/sw,(top-sy)/sh,(bottom-sy)/sh
end
function M:Print(message)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cff59d9c5zMap|r "..message) end
end
