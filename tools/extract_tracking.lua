-- Offline generator: pfQuest + pfQuest-turtle meta tracking -> zMap TrackingData.lua
-- Usage: lua5.1 extract_tracking.lua MapData.lua TrackingData.lua (reads pfQuest + pfQuest-turtle from the AddOns paths at the top).
local PF="/mnt/user-data/uploads/AddOns/pfQuest/"
local PT="/mnt/user-data/uploads/AddOns/pfQuest-turtle/"
local MAPDATA=arg[1]; local OUT=arg[2]
local function run(path)
  local f=assert(io.open(path,"rb")); local s=f:read("*a"); f:close()
  s=s:gsub("^\239\187\191",""):gsub("\r","")
  assert(loadstring(s,"@"..path))()
end
run(PF.."db/init.lua")
pfDB["meta-turtle"]=pfDB["meta-turtle"] or {}
for _,f in ipairs{"units","objects","zones","meta","enUS/units","enUS/objects","enUS/zones"} do run(PF.."db/"..f..".lua") end
pfDB.units.loc=pfDB.units.enUS; pfDB.objects.loc=pfDB.objects.enUS; pfDB.zones.loc=pfDB.zones.enUS
-- icons.lua runs inside pfQuest (before the turtle patch)
pfDatabase={icons={}}; pfQuestConfig={path="Interface\\AddOns\\pfQuest"}
function pfDatabase:AddCustomIcon(id,img,root)
  root=root and root.."\\" or pfQuestConfig.path.."\\"
  local o=pfDB.objects.loc[math.abs(id)]; local u=pfDB.units.loc[math.abs(id)]
  if id<0 and o then self.icons[o]=root..img elseif id>0 and u then self.icons[u]=root..img end
end
run(PF.."icons.lua")
for _,f in ipairs{"units-turtle","objects-turtle","zones-turtle","meta-turtle","enUS/units-turtle","enUS/objects-turtle","enUS/zones-turtle"} do run(PT.."db/"..f..".lua") end
-- overwrites.lua runs before patchtable.lua: drop phantom zone names from the turtle locale
for _,z in ipairs{5600,5098,5550,5132,5138,5139,5140,5150,5161,5155,5164,5169,5170,5173,5177,5178} do pfDB.zones["enUS-turtle"][z]=nil end
local function patch(base,diff) for k,v in pairs(diff) do if v=="_" then base[k]=nil else base[k]=v end end end
for _,db in ipairs{"units","objects","zones"} do
  if pfDB[db]["data-turtle"] then patch(pfDB[db].data,pfDB[db]["data-turtle"]) end
  if pfDB[db]["enUS-turtle"] then patch(pfDB[db].enUS,pfDB[db]["enUS-turtle"]) end
end
patch(pfDB.meta,pfDB["meta-turtle"])
-- zMap zones, mirroring Engine.lua byArea and PFQuest.lua name fallback
run(MAPDATA)
local byArea={}; for _,z in ipairs(zMapData.zones) do byArea[z.area]=z end
local function zoneFor(id)
  local z=byArea[id]; if z then return z end
  local name=pfDB.zones.loc[id]
  if name then for _,z in ipairs(zMapData.zones) do if z.name==name then return z end end end
end
local B="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function enc(n,w) local t={} for i=w,1,-1 do local d=n%64; t[i]=B:sub(d+1,d+1); n=(n-d)/64 end return table.concat(t) end
local skill={herbs=true,mines=true,rares=true,chests=true}
local order={"auctioneer","banker","battlemaster","flight","innkeeper","mailbox","meetingstone","repair","spirithealer","stablemaster","vendor","rares","chests","herbs","mines","fish"}
local iconIndex,icons={}, {}
local out={"-- Generated from pfQuest 8.0.0 + pfQuest-turtle meta tracking data (MIT, see ThirdParty-pfQuest*.txt).",
  "-- Regenerate with build/extract.lua; do not edit by hand.",
  "zMapTrackingData={[\"version\"]=1,[\"categories\"]={"}
local report={}
local unmapped={}
for _,cat in ipairs(order) do
  local meta=pfDB.meta[cat]
  local ids={} for id in pairs(meta) do table.insert(ids,id) end table.sort(ids)
  local entries,nodes={}, {}
  for _,id in ipairs(ids) do
    local value=meta[id]
    local obj=id<0
    local rec=obj and pfDB.objects.data[-id] or pfDB.units.data[id]
    local name=obj and pfDB.objects.loc[-id] or pfDB.units.loc[id]
    if rec and rec.coords and name then
      local icon=pfDatabase.icons[name] or ""
      if icon~="" then icon=icon:gsub("^Interface\\AddOns\\pfQuest\\img\\tracking\\","") end
      local info=""
      if skill[cat] and cat~="rares" then info=tostring(value) elseif not obj then info=rec.lvl or "" end
      local fac=skill[cat] and "" or tostring(value)
      local respawn=0
      local list={}
      for _,c in ipairs(rec.coords) do
        local x,y,zid,rs=c[1],c[2],c[3],c[4]
        if zid and zid>0 then
          local z=zoneFor(zid)
          if not z then unmapped[zid]=(unmapped[zid] or 0)+1
          elseif x>=0 and x<=100 and y>=0 and y<=100 then
            table.insert(list,{z.id,math.floor(x*10+.5),math.floor(y*10+.5)})
            if rs and rs>respawn then respawn=rs end
          end
        end
      end
      if #list>0 then
        table.insert(entries,table.concat({name:gsub("[|\n]"," "),info,fac,icon,respawn},"|"))
        local e=#entries
        for _,n in ipairs(list) do table.insert(nodes,{n[1],n[2],n[3],e}) end
      end
    end
  end
  local ew=#entries<4096 and 2 or 3
  local buf={}
  for _,n in ipairs(nodes) do buf[#buf+1]=enc(n[1],2)..enc(n[2],2)..enc(n[3],2)..enc(n[4],ew) end
  out[#out+1]=string.format("[%q]={[\"w\"]=%d,[\"count\"]=%d,[\"e\"]=%q,[\"n\"]=%q},",cat,ew,#nodes,table.concat(entries,"\n"),table.concat(buf))
  report[#report+1]=string.format("%-13s %5d entries %6d nodes",cat,#entries,#nodes)
end
out[#out+1]="}}"
local f=assert(io.open(OUT,"wb")); f:write(table.concat(out,"\n").."\n"); f:close()
print(table.concat(report,"\n"))
local u={} for z,c in pairs(unmapped) do u[#u+1]=z.."("..(pfDB.zones.loc[z] or "?")..")="..c end
table.sort(u); print("unmapped zones: "..table.concat(u,", "))
