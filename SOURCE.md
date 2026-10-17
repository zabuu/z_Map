# Atlas provenance

This public repository contains the runtime addon and its generated assets. Maintenance tools, build caches and validation artifacts referenced below were used in the local `../_zMapMaintenance` workspace; they are not bundled with the addon. The game client archives and personal SavedVariables are also excluded.

Research and extraction date: **October 16, 2026**.

The official [OctoLauncher repository](https://octowow.st/git/OctoWoW/OctoLauncher) describes a WoW **1.12.1** client and manifest-based updates. The [client guide](https://octowow.st/forum/viewtopic.php?t=831) and [addon compatibility thread](https://octowow.st/forum/viewtopic.php?t=139) document the Vanilla environment and Octo-specific data. The [download page](https://forge.octowow.st/) advertised client **2026.10.06** when checked. This installation's active archives are the authority for the atlas.

## OpenMap reference

Rechecked [OpenMap's source](https://github.com/jiforever/wowforever-openmap/tree/cfebcd308c4bd57dd0247d049c68476a227f605d) for 1.1.0, especially `OpenMap/Map/Stitch.lua`, `OpenMap/Map/Close.lua`, `ARCHITECTURE.md`, and `tools/map-preview/render.py`.

Its relevant techniques are an overview layer, baked map compositions at several resolutions, spatial culling, stable texture assignments, a visible native-tile threshold of 64 with a 36–64 handover, and compensated source-over opacity. zMap adapts those ideas to native Vanilla frames and Lua 5.0. It also limits new map texture bindings to four per render and retains a coarse fallback while a finer set loads. No OpenMap source or assets are bundled in the addon; reference downloads remain in the development folder.

## Client extraction and placement

`../_zMapMaintenance/build_maps.py` opens archives read-only through the existing local StormLib DLL. Priority is base archives, `patch.MPQ`, then numbered/lettered active patches. Backup archives are excluded. All six map/area/overlay/translation tables currently resolve to **patch-4.mpq**. Hashes and read counts are in `../_zMapMaintenance/build-manifest.json`.

- `WorldMapArea`: physical bounds, map space and artwork filename.
- `WorldMapContinent`: continent projection offsets and scale.
- `Map` and `AreaTable`: directories, names and area parent relationships.
- `WorldMapOverlay`: explored artwork fragments and source dimensions.
- `Textures\Minimap\md5translate.trs`: actual minimap texture filenames.
- `World\Maps\...\*.adt`: 16×16 MCNK area IDs per terrain tile.
- `Interface\WorldMap\...`: original world/zone paintings and overlays.
- `Textures\Minimap\...`: original terrain and building renders.

The native world overview uses `Interface\WorldMap\World\World1..12`, assembled at **1002×668** and packed into four opaque tiles. Addon continent labels and zone/level overlays are absent; lettering already painted into client artwork remains.

The world projection was verified against the installed executable's read-only map-coordinate routine at `0x004a7393`. For world coordinates `(worldX, worldY)` and `WorldMapContinent` offsets:

```
pixelX = 501 + 16*offsetX - .03*scale*worldY
pixelY = 334 + 16*offsetY - .03*scale*worldX
```

Both main continents have scale `.75`. Choosing `1/(.03*.75)` atlas yards per overview pixel preserves the physical scale within each continent. Origins are approximately **(32577.778, 9866.667)** for Eastern Kingdoms and **(8755.556, 14615.113)** for Kalimdor. Relative placement follows the client's world projection. No executable or game archive is modified. Paintings remain stylized and can differ locally from terrain.

## Composition and texture format

ADT area cells select the zone paintings. Ownership weights blur over approximately 96 yards; map frames also fade over 128 yards. Overlapping RGB contributions are normalized and composited **before export**. This removes the old per-zone compressed alpha edges and their visible bands. Since 1.1.1 the ocean uses a deterministic multiscale noise field spanning the entire atlas in a subdued blue-grey palette. It has no repeated or mirrored swatches. Version 1.1.2 darkens its palette by approximately 20%. A native minimap background retains unpainted ground rather than treating every gap as ocean; a dark-blue/empty-pixel mask selects water and preserves bright snow and ice.

In 1.1.2 that land mask also controls painted sea coverage. A roughly 64-yard coastal buffer and 128-yard feather retain nearby strokes, then suppress offshore artwork independently of ADT area ownership. Land pixels and small islands retain full coverage. Sea decorations and frames therefore fade before their rectangular map boundary. This mask is composited offline into opaque RGB map blocks, adding no runtime map layers or textures. Cached 64px minimap copies are reused when building terrain LODs to avoid decoding the same sources twice.

The painted pyramid has **6, 24, 88 and 330** tiles at **1/32, 1/16, 1/8 and 1/4 pixels per yard**. Each 512px block includes neighbour gutters. Spatial grids select only viewport intersections. Large viewports step down a resolution if a participating level would exceed 64 tiles. Whole-layer fades use source-over compensation to retain brightness.

The 45 coarse terrain tiles each cover an 8×8 group of native terrain textures. Missing cells use binary transparency rather than black. Full resolution terrain uses original client paths at runtime, with at most 64 visible native tiles. File assignments remain stable while a tile stays visible; textures leaving the view are hidden, unanchored and unbound.

All **497 generated map blocks** use BLP2 DXT1, matching native `Interface\WorldMap\World\World1.blp`: `(type=1, encoding=2, alphaDepth=1, alphaEncoding=0)`. They contain complete mip chains. Opaque painted blocks avoid the DXT3 alpha quantization from 1.0.1. World and terrain paths use `Media\Atlas11`; 1.1.2 paintings use `Media\Atlas13` to avoid cached older water. Previous builds remain backed up outside the addon.

`Media\GroupCircle.tga` is a separate 64×64 uncompressed 32-bit RGBA texture generated from concentric vector circles at eight times the final resolution. Transparent corners, a black circular rim and a white center allow native vertex coloring for every class. Group marker frames have no square backdrop. Hover and input forwarding are unchanged.

Saved main-world pins migrate from the old atlas origins once. The obsolete main-world camera resets to World; other preferences and isolated-space pins remain. Old pins did not record a continent, so their former x coordinate selects the old continent partition during migration.

## Rebuilding and checking

### Live gathering in 1.3.0

`GatherData.lua` contains resource identities only: 285 entries grouped into 198 resource names. `build_gather_catalog.py` reads the active OctoWoW `WDB/gameobjectcache.wdb` templates and native `Lock.dbc`. Herbalism/mining lock cases classify cached resources; GO type 25 identifies fishing pools. Installed MIT-licensed pfQuest/pfQuest-turtle metadata fills uncached entry names and categories. Current server cache names take precedence. No spawn coordinates or respawn schedules are imported. The original notices are included with the addon.

Optional zAPI 2.4 exposes `gatherBufferVersion=1` and `gatherObjectsInto(privateBuffer)`, returning count and player world XYZ. Each object occupies ten flat entries: GUID string, object entry, XYZ, display ID, GO type, state, flags and dynamic flags. The native reader uses the public [1.12.1 update fields](https://github.com/vmangos/core/blob/development/src/game/Objects/UpdateFields_1_12_1.h) and [GO type/state/flag definitions](https://github.com/vmangos/core/blob/development/src/game/Objects/GameObjectDefines.h). It checks loaded-object type, descriptor range and GUID, position finiteness and world/player readiness; it omits traps, bobbers, used containers and explicitly noninteractive objects. It adds no hook, action or network query.

Snapshots cover objects loaded by the client, not the server's entire world. Lua transforms physical `(worldX,worldY)` to `(originX-worldY,originY-worldX)` and verifies the native player snapshot against the current native map sample before assigning a coordinate space. Failed/mismatched snapshots and loading events clear current detections. Updates run every 0.5 seconds only while the map and live feature are enabled. Version 1.3.1 retains observed positions as unknown grayscale markers, as described below.

Unknown entries are classified only by GO type or an unambiguous known herb/ore display. Their names explicitly contain the object ID rather than guessing a plant/ore name. They receive individual filter rows on discovery. Category switches and individual resource filters are independent, with an overall Live toggle. Up to 512 resource markers display per viewport, with a visible overflow count. Native snapshots remain complete. The catalogue and map remain usable without pfQuest; unsupported/absent zAPI disables live gathering while leaving the atlas working.

Native scratch vectors, flat Lua output, live records, icon frames and stable anchors are reused. The native side retains at most 4,096 records of scratch capacity and leaves failed-call output unchanged. `test_native_gather.py` executes the production reader/query against x86 descriptor fixtures; `test_gather.py` covers actual addon snapshot/filter/lifecycle logic. These are offline checks, not a live-client spawn/alignment or FPS measurement.

```powershell
python _zMapMaintenance\build_gather_catalog.py
python _zMapMaintenance\test_gather.py
python _zMapMaintenance\test_native_gather.py
```

### Circular icons, observation history and sharing in 1.3.1

`build_gather_icons.py` reads the four native inventory icons and packages eight 64×64 RGBA TGA textures in `Media\GatherIcons31`. A supersampled circular coverage mask multiplies source alpha; RGB remains byte-identical to the resized native icon. The grayscale partner uses identical alpha and equal RGB channels. This requires no modern texture-mask or desaturation API. The catalogue builder also invokes this pipeline.

`GatherLog.lua` saves map ID, resource identity and native world XYZ under `zMapDB.gatherLog.realms[GetRealmName()]`. It stores observed positions only, never GUIDs, active flags, predictions or imported spawn coordinates. Every reload begins unknown. Fresh local snapshots alone give a runtime location a live reference. Matching requires the same resource name/category, map and a three-dimensional distance of at most 0.75 yards; different elevations remain separate. An eight-yard location index avoids scanning history for each detection. A second 512-yard atlas grid culls logged markers by viewport and active filters. The 20,000-location cap never evicts existing observations; excess detections still display live. At the 512-icon display cap, live detections precede history and sit above it.

`GatherSync.lua` independently uses Vanilla's `JoinChannelByName`, `SendChatMessage` and `CHAT_MSG_CHANNEL` with the dedicated `zMapNodes31` channel. This also reaches users outside a group; delivery follows the server's realm/channel/faction rules. Removing the channel from chat windows hides its data from normal chat. Installed AceComm's custom-channel transport provided a local compatibility reference; the separately authored protocol has no library dependency. The primary [vMaNGOS chat handler](https://github.com/vmangos/core/blob/development/src/game/Handlers/ChatHandler.cpp) documents channel routing and language validation; OctoWoW's actual server delivery remains a live acceptance check.

The versioned `ZMN1` protocol shares only map ID, object entry, XYZ rounded to 0.01 yard and category. Since 1.3.2, outbound packets use `ZMN1:H:count:checksum` and `ZMN1:D:records`, with colon separators. The old raw pipe separators were interpreted as malformed chat escapes by WoW; the installed pfUI wrapper forwarded them unchanged. The receiver can still read the former pipe format, but never transmits it. Other users need the fixed version to exchange messages through normal client chat. Names resolve from the local catalogue; unknown IDs keep explicit numbered names. Records never carry live state or player coordinates. Summaries compare count and an order-independent checksum; differing peers schedule paced background sweeps and reply with their own summary to reconcile both directions. Received locations suppress redundant broadcasts in an ongoing sweep and are not immediately echoed. Per-peer hello cooldowns coalesce requests. Native discoveries enter a priority queue once. Summaries repeat every 180 seconds for recovery and new peers; three records fit a packet of at most 230 bytes, with no more than one outgoing message per second. Failed sends wait 30 seconds before retrying, retain queued records and leave markers/history alone. Duplicate-only sweeps inspect at most 128 stored records per iterator call. Numeric/category/map checks, per-peer/global receive token limits and a 128-peer session table bound incoming work. No message is executed as Lua.

Sharing runs on its own small frame while the map is hidden and needs no zAPI. The default-on Share control leaves the dedicated channel and stops send/receive when disabled. Remote records enter the same realm-scoped location index, always gray; they cannot activate or deactivate a local observation. Resource and category filters affect both states, Logged hides unknown locations, and Live controls only local native scans. A remote site becomes colorful only after a matching local snapshot.

`test_gather_history.py` verifies saved-state round trips, corruption/duplicate handling, realm and cave-space separation, new-GUID/site-specific respawns, exact icon RGB/alpha/grayscale, filters and a 20,000-record log. `test_gather_sync.py` runs independent real Lua addon instances through the actual channel event/protocol, including two- and three-peer union merges, delayed joins, hidden maps, no native API, throttled 600-location transfers, malformed packets and sharing controls.

```powershell
python _zMapMaintenance\build_gather_icons.py
python -m unittest discover -s _zMapMaintenance -p 'test_gather*.py' -v
```

### Node presentation and learned timing in 1.3.3

`GatherVisuals.lua` scales marker size by physical viewport span, independently of window resolution. Icons are 17px near 900 yards across, smoothly become 3px dots by 4,500 yards, fade between 12,500 and 18,000 yards and are completely absent at continent/world scale. The hidden case releases frames and skips logged-location traversal. Player/group markers are unaffected. Live dots retain category colors and a thin gold rim; unknown dots are gray. Marker frames, texture assignments and anchors remain reusable.

`build_gather_visuals.py` produces two native-compatible RGBA TGA files in `Media/GatherVisuals33`: a neutral 64px antialiased ring tinted gold behind current icons, and a 512px atlas with 64 transparent ring-progress cells. The circular swipe sits outside a logged icon, has no text or cooldown model, and therefore never invokes pfUI/OmniCC number hooks. Its cached texture coordinates change only when the remaining fraction crosses a cell boundary; displayed markers update at most every 0.1 seconds. `preview_gather.py` composites the real Lua size, color, texture and UV commands for visual review.

The current zAPI gather tuple contains no server respawn time. The primary [vMaNGOS game-object implementation](https://github.com/vmangos/core/blob/development/src/game/Objects/GameObject.cpp) keeps respawn scheduling on the server and supports random/dynamic timings; it is not an authoritative OctoWoW schedule. Old vanilla/pfQuest respawn defaults are not imported as OctoWoW truth. The user chose locally learned estimates.

`GatherTimers.lua` learns each saved physical site independently. A live-to-missing observation can begin a watch only within 45 horizontal yards and 20 vertical yards, on the same map, after a valid preceding sample. A respawn counts only if all intervening successful samples stay nearby, with no gap over two seconds. Native failures, loading, a hidden map and leaving range drop that observation. Samples must last 15–7,200 seconds. The most recent five intervals are retained; at least three are required, with total spread at most max(6 seconds, 30% of the median). Their median becomes a labeled estimate. These conditions reduce visibility/range artifacts but do not prove a server timer.

Once an estimate exists, the next nearby disappearance starts a grayscale swipe. Timer expiry removes the swipe and leaves availability unknown; only a fresh native detection restores color/gold. Reappearance clears any estimate in progress immediately, even if earlier than predicted. Saved samples are validated and estimates recomputed on load; unexpired countdown metadata resumes while availability still starts unknown. Shared protocol records contain no timing/availability fields, so remote reports neither train local samples nor start swipes.

Checks: `python _zMapMaintenance/test_gather_visuals.py`, `python _zMapMaintenance/build_gather_visuals.py`, and `python _zMapMaintenance/preview_gather.py`. The preview and tests are offline, not an in-game acceptance capture.

### Underground plans in 1.2.0

`../_zMapMaintenance/build_interiors.py` reads native WorldMapArea and WorldMapOverlay records and assembles 13 main-world plans from the installed client's art. The catalogue uses native filenames, including Ironforge, Undercity, Blackrock Mountain, Caverns of Time, Timbermaw Tunnels and mapped entrances. These locations cannot be inferred reliably from terrain ownership: underground WMO areas often have no corresponding ADT area cells, and their normal minimap tiles show the roof or exterior. The existing OpenMap reference likewise retains the underground city plans above its minimap layer.

`InteriorData.lua` stores plan IDs and normalized tile rectangles. The runtime resolves them against the existing WorldMapArea-derived zone bounds; it does not introduce new offsets or change any map, marker or pin coordinates. Separate instance map spaces are not projected onto the continent by guessing.

The extra layer lies above terrain/detail art and below markers. It fades in between 20% and 40% viewport coverage and remains fully visible at deeper zoom, regardless of Look mode. It works while browsing without needing the player to stand inside or select the native map. Only intersecting textures load, within the shared four-texture budget. A partially loaded plan stays hidden until its visible pieces are ready.

The 156 additional 256px tiles in `Media\Interiors20` use uncompressed 32-bit RGBA TGA. Native paintings/overlays are assembled at 1002×668 and split with neighbour gutters. Version 1.2.1 uses native-art footprint polygons/corridor paths, a roughly 72px soft falloff and a 96px outer-edge feather, preserving a full-opacity core. This removes empty parchment and ornament without changing the physical rectangle. Full alpha avoids compressed border-alpha bands. Exact plan filenames/counts are recorded in `interior-manifest.json`.

### Placed cave geometry and floors in 1.2.1

`build_caves.py` reads the active client's WMO entries in `md5translate.trs`, main-world ADT `MWMO`/`MWID`/`MODF` placements, WMO `MOHD`/`MOGI` bounds, and `WMOAreaTable` namesets. It assembles native group textures at two pixels per local yard, with bottom-up tile rows and transparent power-of-two padding. WMO group placement is also described in the primary [World of MapCraft extraction source](https://github.com/iamcal/World-of-MapCraft/blob/master/build/wmo_build.php); nameset/area fields follow the [WoWDBDefs WMOAreaTable schema](https://github.com/wowdev/WoWDBDefs/blob/master/definitions/WMOAreaTable.dbd). The assets and resulting transforms come from this OctoWoW installation.

For zero-pitch/roll placements, local WMO `(x,y,z)` maps to ADT `(y,z,x)`, then rotates by MODF yaw. With `s=sin(yaw)` and `c=cos(yaw)`, horizontal ADT coordinates are `(posX+s*x+c*y, posZ+c*x-s*y)`. ADT coordinates then enter the unchanged continent projection. Native cave images rotate offline into atlas axes, retain their actual transparent outline, and soften inward before TGA export. A duplicate placement with an identical transform is removed.

`CaveData.lua` describes **284 cave placements / 704 TGA tiles** in `Media\Caves21`. Their bounds are checked independently against MODF's world AABB with an eight-yard gutter allowance. AABB checks do not replace live marker/entrance validation. Thirty nonzero-pitch/roll placements, thirteen missing minimaps and one unsupported model are omitted; the generator does not invent transforms for these. The inventory and per-location coverage are recorded in `cave-placements.json` / `cave-manifest.json`.

Caves render above surface/detail and below painted interior plans and markers. Auto mode fades them in between scale .7 and 1.35; Surface hides them and Underground uses full opacity at close zoom. Only intersecting tiles participate, with a 64-tile cave cap, stable bindings, shared four-load budget and whole-plan readiness. No cave geometry is loaded at World zoom.

Isolated floor spaces remain separate from continent coordinates. Global-WMO spaces, multi-plan spaces and the client's named cave/crypt spaces retain their selected painting above exterior minimaps at deep zoom. Multiple native plans get a floor selector; Follow updates the selected plan from native GetMapInfo. WMO cave groups are composed top-down in height order, so overlapping levels without separate client floor plans remain a composite rather than invented floors. No injected position API or other addon is required.

From `Interface\AddOns`:

```powershell
python _zMapMaintenance\build_maps.py
python _zMapMaintenance\build_interiors.py
python _zMapMaintenance\build_caves.py
python _zMapMaintenance\test_zmap.py
python _zMapMaintenance\preview.py
python _zMapMaintenance\benchmark.py
```

Build dependencies are Python, Pillow, NumPy and the existing local StormLib at `_OctoGraphicsDev\tools\stormlib\x64\StormLib.dll`. Tests use `lupa.lua51`; addon code stays in the Lua 5.0 subset. These are development dependencies only.

The full map build invokes both interior builds. Run `build_interiors.py` alone for painted-plan edge changes, or `build_caves.py` for cave placement/art changes. The cave builder uses `lupa.lua51` to read the generated Lua map coordinates.

`VALIDATION.md`, `visual-qa.png` and `render-workload.json` record offline checks. The preview uses the actual Lua renderer's clipped texture commands. The workload comparison measures UI commands rather than GPU time or live FPS.

Fully restart WoW after adding these texture paths. Check World, the Moonglade–Winterspring border, classic/custom zones, close-up geometry, player/pin placement and rapid zooming with other map addons disabled. `/zmap status` reports version and recent texture counts.

### Experimental transports in 1.4.0

`TransportData.lua` is generated from this installation's active `DBFilesClient\\TaxiPathNode.dbc` in `patch-5.mpq`, inspected October 17, 2026. Stop flag 2 and native XYZ coordinates identify each actual pier/berth. Gameobject cache type 15 records associate ten transport entries with their taxi path IDs; three additional classic identities have native paths but are explicitly unconfirmed on the server. The 13-route catalogue includes custom Kargath, Thunder Bluff, Sparkwater–Revantusk and Alah'Thalas services. Mere presence in client assets is not proof of an active service. TransportAnimation elevator/tram tracks are not used for ships.

Seven measured cycle, home arrival restart phase, dwell and known opposite-end offset seed sets were inspected read-only in the installed [OctoBus by Phridgey](https://github.com/Phridgey/OctoBus). They are factual timing data, not copied addon implementation. No OctoBus source, artwork or personal SavedVariables are distributed. OctoBus files and native binaries remain untouched; a local before/after SHA256 inventory verifies the files. Development extraction/audit scripts remain outside this public addon repository.

The independent `Transports.lua` adapter reads only public `OctoBusDB` schedule fields when available. Optional `ZepTransports()` returns nearby native object transforms, decoded from its documented semicolon records while retaining GUIDs as strings. Route proximity resolves main-world map IDs without changing the stock map selection. Vehicle pins always represent fresh observations, never interpolation along a schedule. Native scans are limited to two per second and stop while disabled/loading. No DLL is bundled or replaced, and zMap works without OctoBus.

Restart estimates use a single `.server info` uptime query after entering the world, coalesced when another addon already obtained the reply. Saved anchors are realm-scoped and invalidated when older than the observed restart. Arrival qualification requires .75s at the stop; initially visible docked ships do not get a fabricated arrival. Departure observations refine dwell, and repeated arrivals can refine/learn a cycle. Missing scans cancel the transition observation. An unseeded learned period can span missed visits, so all countdowns retain the estimate marker and source on hover. The opposite terminal is timed only with an observed anchor or known measured offset; it is never assumed to be halfway around the cycle.

Far views show faint dotted schematic terminal connections. Near views use native same-map segments, skipping teleport flags/map changes and large discontinuities. Atlas projection is unchanged: `(originX-worldY, originY-worldX)`. Dots are clipped, pooled, capped at 384 and cached for a stationary view; markers cluster at low zoom. The new layers are below existing player/group markers and do not consume the map tile loading budget.
