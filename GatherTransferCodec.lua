-- Bounded binary node snapshots. No serialized Lua, GUIDs or live clocks.
local C={limit=20000,maxBytes=4000000,chunk=120};zMap.bulkCodec=C
local floor,mod=math.floor,math.mod
local alphabet="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local digits={};for i=1,64 do digits[string.byte(alphabet,i)]=i-1 end
local codes={herbs="h",ore="o",fish="f",treasure="t"}
local categories={h="herbs",o="ore",f="fish",t="treasure"}
local function integer(n,limit) return type(n)=="number" and n==floor(n) and n>=0 and n<=limit end
local function coordinate(n) return type(n)=="number" and n==n and math.abs(n)<100000 end
local function name(n) return type(n)=="string" and string.len(n)>0 and string.len(n)<=160 and not string.find(n,"[%z\1-\31\127|]") end
local function pack(n,count)
    local bytes={};for i=1,count do bytes[i]=string.char(mod(n,256));n=floor(n/256) end;return table.concat(bytes)
end
local function position(n) return pack(math.max(1,math.min(19999999,floor(n*100+.5)+10000000)),4) end
local function read(job,count)
    if job.pos+count-1>string.len(job.blob) then job.error="Truncated snapshot";return end
    local value,power=0,1
    for i=job.pos,job.pos+count-1 do value=value+string.byte(job.blob,i)*power;power=power*256 end
    job.pos=job.pos+count;return value
end
function C.Encode(raw)
    local out={}
    for i=1,string.len(raw),3 do
        local a,b,c=string.byte(raw,i),string.byte(raw,i+1),string.byte(raw,i+2)
        local n=a*65536+(b or 0)*256+(c or 0)
        local x,y,z,w=floor(n/262144)+1,mod(floor(n/4096),64)+1,mod(floor(n/64),64)+1,mod(n,64)+1
        table.insert(out,string.sub(alphabet,x,x)..string.sub(alphabet,y,y)..
            (b and string.sub(alphabet,z,z) or "=")..(c and string.sub(alphabet,w,w) or "="))
    end
    return table.concat(out)
end
function C.Decode(text)
    local length=string.len(text)
    if length<4 or length>160 or mod(length,4)~=0 then return end
    local out={}
    for i=1,length,4 do
        local a,b,c,d=string.byte(text,i),string.byte(text,i+1),string.byte(text,i+2),string.byte(text,i+3)
        local x,y,z,w=digits[a],digits[b],digits[c],digits[d]
        if not x or not y or c~=61 and not z or d~=61 and not w or
            c==61 and d~=61 or (c==61 or d==61) and i+3~=length or
            c==61 and mod(y,16)~=0 or d==61 and c~=61 and mod(z,4)~=0 then return end
        local n=x*262144+y*4096+(z or 0)*64+(w or 0)
        table.insert(out,string.char(floor(n/65536)))
        if c~=61 then table.insert(out,string.char(mod(floor(n/256),256))) end
        if d~=61 then table.insert(out,string.char(mod(n,256))) end
    end
    return table.concat(out)
end
function C.HashStep(job)
    local last=math.min(string.len(job.blob),job.hashPos+4095)
    for i=job.hashPos,last do
        job.hashA=mod(job.hashA+string.byte(job.blob,i),65521);job.hashB=mod(job.hashB+job.hashA,65521)
    end
    job.hashPos=last+1
    if last==string.len(job.blob) then job.checksum=job.hashB*65536+job.hashA;return true end
end
function C.BuildStep(job,nodes,maps)
    for step=1,100 do
        if job.cursor>job.last then
            job.blob="ZMNDB1"..pack(table.getn(job.defs),2)..pack(job.count,2)..table.concat(job.defs)..table.concat(job.records)
            job.defs=nil;job.records=nil;job.keys=nil;job.hashPos=1;job.hashA=1;job.hashB=0
            return true
        end
        local node=nodes[job.cursor];job.cursor=job.cursor+1;local r=node and node.record
        if r and integer(r.entry,4294967295) and r.entry>0 and integer(r.map,65535) and maps[r.map] and
            coordinate(r.worldX) and coordinate(r.worldY) and coordinate(r.worldZ) and codes[r.category] and name(r.name) then
            local key=r.entry..":"..r.category;local index=job.keys[key]
            if not index then
                index=table.getn(job.defs)+1;job.keys[key]=index
                job.defs[index]=pack(r.entry,4)..codes[r.category]..string.char(string.len(r.name))..r.name
            end
            local samples={}
            for _,sample in ipairs(type(r.respawnSamples)=="table" and r.respawnSamples or {}) do
                if table.getn(samples)>=5 then break end
                if coordinate(sample) and sample>=15 and sample<=7200 then table.insert(samples,pack(floor(sample+.5),2)) end
            end
            table.insert(job.records,pack(index,2)..pack(r.map,2)..position(r.worldX)..position(r.worldY)..position(r.worldZ)..
                string.char(table.getn(samples))..table.concat(samples))
            job.count=job.count+1
        else job.skipped=job.skipped+1 end
    end
end
function C.StartDecode(blob,expected)
    if string.len(blob)<10 or string.len(blob)>C.maxBytes or string.sub(blob,1,6)~="ZMNDB1" then return end
    local job={blob=blob,pos=7,defs={},rows={},phase="defs"}
    job.defCount=read(job,2);job.count=read(job,2)
    if job.count~=expected or job.count>C.limit or job.defCount>job.count then return end
    return job
end
function C.DecodeStep(job)
    for step=1,100 do
        if job.phase=="defs" then
            if table.getn(job.defs)==job.defCount then job.phase="rows"
            else
                local entry=read(job,4);local byte=read(job,1);local length=read(job,1)
                if job.error then return end
                local category=categories[string.char(byte)]
                local text=string.sub(job.blob,job.pos,job.pos+length-1);job.pos=job.pos+length
                if not entry or entry==0 or not category or not name(text) or string.len(text)~=length then job.error="Invalid resource definition";return end
                table.insert(job.defs,{entry,category,text})
            end
        elseif table.getn(job.rows)==job.count then
            if job.pos~=string.len(job.blob)+1 then job.error="Trailing snapshot data";return end
            job.blob=nil;return true
        else
            local index,map,x,y,z,n=read(job,2),read(job,2),read(job,4),read(job,4),read(job,4),read(job,1)
            if job.error then return end
            local def=job.defs[index]
            if not def or n>5 or x<=0 or x>=20000000 or y<=0 or y>=20000000 or z<=0 or z>=20000000 then job.error="Invalid node record";return end
            local samples={}
            for i=1,n do
                local sample=read(job,2)
                if not sample or sample<15 or sample>7200 then job.error="Invalid respawn sample";return end
                samples[i]=sample
            end
            table.insert(job.rows,{def[1],map,(x-10000000)/100,(y-10000000)/100,(z-10000000)/100,def[2],def[3],samples})
        end
    end
end
function C.Apply(row,M)
    if not M.gatherShareMaps[row[2]] then return "skipped" end
    local info=M.gatherEntries[row[1]]
    if not info then info={category=row[6],name=row[7]};M.gatherEntries[row[1]]=info end
    if info.category~=row[6] then return "skipped" end
    local definition=M.gatherDefinitions[M:AddGatherDefinition(info)]
    local node,added=M:StoreGatherLocation(row[2],row[1],definition,row[3],row[4],row[5])
    if not node then return "skipped" end
    if not added then return "duplicates" end
    node.record.shared=true
    for _,sample in ipairs(row[8]) do M:LearnGatherRespawn(node,sample) end
    return "added"
end
