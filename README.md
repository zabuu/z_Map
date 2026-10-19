# zMap 1.7.6

Standalone seamless atlas for the installed OctoWoW 1.12 client, with zSuite's dark window, mint branding, `z_Map` folder, `zMapDB` settings and zSuite keybinding group.

Part of the [zSuite addons by Zab](https://github.com/zabuu). Public repository: [zabuu/z_Map](https://github.com/zabuu/z_Map).

## Installation

1. Download [the latest source ZIP](https://github.com/zabuu/z_Map/archive/refs/heads/main.zip) and extract it into your OctoWoW `Interface\AddOns` folder.
2. Rename the extracted `z_Map-main` folder to **`z_Map`**. The TOC must be at `Interface\AddOns\z_Map\z_Map.toc`.
3. Fully exit and restart WoW so it discovers the bundled map and marker textures. Enable **zMap** in the AddOns list.

Alternatively, run `git clone https://github.com/zabuu/z_Map.git z_Map` from `Interface\AddOns`.

The map works without other addons or native extensions. Live gathering is optional and requires **zAPI 2.4 or later**, installed separately in the game directory; this repository does not install a DLL. Without it, the atlas and saved/shared locations still work. Artwork ownership and the source-code license are explained in [NOTICE.md](NOTICE.md) and [LICENSE](LICENSE).

Enable **zMap** in the character selection AddOns list after restarting the client. Press **M**, `/zmap`, or `/zm` to open it. The world map microbutton also opens zMap.

Version 1.7.6 adds **Settings → HUD position**, with horizontal and vertical sliders from **−3000 to +3000** UI units. The small position panel closes the full map and enables the HUD so adjustments preview live. Drag for large moves, or use the mouse wheel over either slider for one-unit adjustments. Positive values move right/up. Offsets save automatically and remain applied after camera/feet realignment. **Reset offsets** returns to automatic alignment. `/zmap hud position` opens the same panel. **`/reload` applies this update.**

Version 1.7.5 gives the HUD a **circular fade**, with equal reach ahead, behind and to both sides. Walls and icons share the same radius, and wall segments clip to the circle. The HUD now recalibrates its feet-height offset **once after camera zoom or tilt settles**, then holds still. Walking, horizontal turning and small camera noise do not continuously recenter it.

Version 1.7.4 removes the player arrow from the **HUD only**, leaving walls and resource icons around your character. The minimap and full-map arrows remain visible.

Version 1.7.3 centers the HUD directly on the **game viewport**, correcting horizontal offsets with scaled UIs. On its first display it measures your character's **feet height once** using zAPI, saves that vertical offset and holds it steady. The HUD center stays fixed while the world scrolls and rotates around it. **Align HUD to feet** in Settings or `/zmap hud align` takes an immediate fresh measurement. If the large map is open, alignment happens once you close it. Without a valid projection the HUD keeps its saved height, or a 43%-from-bottom default.

Version 1.7.1 makes the large map's **Follow**, minimap following and HUD movement/turning update every rendered frame. Cached tiles, walls and existing icons move together while terrain loading, node scans and wall queries keep their previous limits. Follow keeps the current zoom. Movement uses current native positions; teleports snap and unavailable positions do not coast. **Shift+M toggles the HUD**, with a matching **HUD: on/off** button beside **Settings** on the main map. The shortcut is installed once; later changes in Key Bindings are preserved. HUD range, opacity and optional quests remain in Settings.

Version 1.7.0 adds an experimental **HUD automap**: `/zmap hud` toggles a transparent, click-through overlay of nearby walls and gathering icons. It follows your position and turns with your character, keeping forward up and icons upright. There is no window, filled terrain, map text or route clutter. pfQuest icons start off; `/zmap hud quests` enables them. **Settings** controls HUD range, wall opacity and quests; a **Toggle zMap HUD** keybinding is available in the zSuite group. The HUD pauses while either large map is open and resumes afterward. **Fully restart WoW** to load the new modules, geometry data and line texture.

Full-map gathering icons now retain more size at intermediate zooms; minimap icon sizing and the continent cutoff stay the same. The atlas minimap adds **two extra zoom-out steps** using its wheel and zoom controls, showing up to 69% more width beyond the native minimum. It keeps atlas rendering indoors, using available zAPI world positions when the normal map position becomes unavailable. Its native indoor zoom scale takes priority over saved outdoor/indoor zoom guesses. Caverns of Time's painted tunnels and cave geometry now wait until a closer zoom, and the full-map player arrow receives the same top-layer priority as the minimap arrow.

HUD walls come from this client's placed WMO building, city, cave and instance geometry, with height filtering when zAPI supplies a matching player elevation. They are approximate wall traces, not a navigation mesh: terrain cliffs, trees, small M2 scenery and unsupported tilted placements are omitted. Without native elevation, multiple levels can overlap. Logged/live icons keep their existing resource filters, grayscale/color distinction and gold rims; live scanning still needs zAPI. Range is measured from the player (120–360 yards), and the HUD has separate pools and orientation from both other maps. `/zmap status` reports its wall count. The first pass is capped at 512 wall segments and 128 node icons; dense areas may omit farther detail. Visual previews and tests are offline; in-game appearance and performance still need validation.

Version 1.6.3 keeps the player arrow above every atlas minimap layer, including terrain, interiors, nodes, quests and group markers. Both native and fallback arrows receive the correct frame strata and a level above the map's marker children. Ordering is checked after UI updates, and the native arrow's previous strata/level return when the atlas is disabled.

Version 1.6.2 fixes the remaining double minimap player arrow: this client's native model can render while its `IsShown()` returns nil, so zMap now reuses the detected model without drawing a second arrow. Party/raid circles use the same **65%–100% minimap zoom multiplier** as gathering icons; they retain their full size and remain visible at continent/world zoom on the large map. Distant group members use the client's world-map position reports, sampled together at most once every two seconds without extra chat or another player's addon. Undercity's southwest passages also have a wider, softly blended footprint. **Fully exit and restart WoW** to refresh those four changed interior textures.

Version 1.6.1 fixes the blank atlas minimap and repeated `Couldn't find CVar named 'rotateMinimap'` errors on the 1.12 client. Vanilla never queries that later-client setting. Missing minimap settings use safe defaults.

Version 1.5.1 gives all zMap background messages one shared chat budget: **at most one packet every 15 seconds across gathering, transit and the uptime query**, with no catch-up bursts. Typing or sending normal chat pauses syncing for 30 seconds. A server chat-throttle notice pauses both senders for at least a minute and reduces their subsequent rate; repeated notices extend the pause. Pending work resumes gradually. Summaries are normally fifteen minutes apart, peer requests coalesce, and unchanged docked vehicles send only occasional heartbeats. Local detection, recordings and the animated map keep their normal cadence. Existing 1.5.0 peers remain compatible. Restart WoW to load the new modules and item textures.

Known gathering nodes now use their harvested item's native icon, with circular corners, grayscale logged state, the live gold border and the existing cooldown swipe. The bundle maps 100 object identities to 54 item icons, including the common herbs, ores and named fish pools. Unidentified resources and containers without a single known item retain a circular category icon. Your player marker uses the native minimap arrow and follows live facing.

Version 1.6.0 integrates **pfQuest** with both the large atlas and the optional atlas minimap. Active quest givers, turn-ins, objectives, clusters and database search results use pfQuest's artwork, colors, tooltips and click actions. Its selected quest paths are projected into zMap, with the player-to-target path on the minimap. Quest-log and database map links open the matching atlas area when zMap replaces the regular map. The integration follows pfQuest's spawn, cluster and route filters; **Settings → pfQuest** turns it off. Both addons remain independently usable. Fully restart WoW once to load the new integration module.

The atlas minimap raises and reuses the client's actual player arrow, hiding zMap's duplicate even when the model reports a false/nil shown flag. Its original frame level returns when the atlas closes or falls back to the native view. A projected arrow remains available when no usable native model is found or the native minimap rotates. Minimap gathering and group icons scale from **65% at full zoom out to 100% at full zoom in**. The large map keeps its existing scaling.

Open **Settings** or `/zmap settings` and choose **Minimap: zMap** to use an optional square, north-up atlas in the minimap. It follows your position, uses the native minimap zoom controls, and shows zMap nodes, group members, pins and transit. **Look** chooses the large map's style, terrain or painted art. Interiors/caves use the same atlas layers. This view has its own position, zoom and texture pools, so browsing the large map does not move it. It also keeps gathering scans active with the large map closed. Where a usable player position is unavailable, or while browsing the original world map, the native minimap remains visible. The option defaults off; switching back restores the native view and widget levels.

Version 1.5.0 adds **animated transport estimates outside detection range**, persistent route recordings and multi-client transport sharing. Open **Transit** in the header or `/zmap transit`. Terminal icons sit at the client's actual berths/piers; hover for both ends' arrival/departure estimates and their sources. The scrolling service list also centers the map on a terminal. Transit, routes, timer labels, **Predict**, **Record** and **Share** have separate saved switches.

With the separately installed **ZepSense** reader (`ZepTransports()`), bright vehicle icons show local sightings of loaded transports, including docking and departure. **Blue icons with `+`** use fresh sightings from another updated zMap client. **Muted icons with `~`** are model estimates. Local sightings take priority; shared reports expire after five seconds, then known services continue along their timed native paths. Estimates work alone, without another player online or a live reader. No native update is installed by zMap. zAPI's gathering snapshot does not supply global transport positions.

**Predict** animates estimates from known departure/arrival timing and native route geometry. It keeps the vehicle stationary during dwell and moves it along the correct leg afterward. It skips teleport/loading gaps rather than drawing a physical flight across a schematic ocean connection. Both ends need enough timing information; unknown offsets or cycles do not get invented positions. Fresh sightings can correct the model phase. Visible movement updates up to 20 times per second, using existing marker frames without repainting map tiles or route dots. Local/shared positions are smoothed between samples.

Zeppelin icons turn to face their direction of travel. Local and shared sightings use measured movement; estimates use the current native path segment. A stationary zeppelin keeps its last heading. Hover targets and status badges stay upright.

**Record** learns the speed along each leg from actual timed sightings. Up to 64 normalized time/progress measurements per direction (128 per service) save per realm. Recordings expire after 14 days or a geometry mismatch. Predictions are never recorded as observations. Watching departures or riding a round trip helps fill the profile; repeat sightings improve it. Disabling Record retains existing profiles. A server restart clears current sightings/corrections and old arrival anchors while retaining reusable route profiles.

**Share** defaults on and exchanges transport sightings, dock events and recorded speed samples over the dedicated `zMapTransit15` channel. Other players need zMap 1.5.0 or later. It works with the map closed and can supply reports to a client without ZepSense. Shared partial dock observations can establish an unmeasured cycle together. Transfers use server uptime and sample age rather than trusting matching PC clocks. Messages contain only transport data: no player positions or transport GUIDs. Messages are limited to 230 bytes, batch up to three records and use the shared 15-second send budget. Dock/movement changes take priority over speed-profile backfill, with fewer repeated observations and one preferred observer per route. API errors retry after 30 seconds; server throttles trigger the longer shared backoff. Peer reports and predictions are not relayed as firsthand sightings. Turning Share off leaves the channel and retains learned data. Normal server channel/faction restrictions apply; gathering sharing has its own switch but shares this send budget.

The catalogue contains 13 native client routes / 26 terminals, including Kargath, Thunder Bluff, Sparkwater–Revantusk and Alah'Thalas. Ten identities are present in this installation's object cache; three additional classic boat services have client paths but remain **Service unconfirmed** until observed on this server. Client route assets alone do not prove that a service is running.

Seven services have measured cycle/dwell seeds from the installed OctoBus: the five zeppelin routes, Sparkwater–Revantusk and Ratchet–Booty Bay. zMap reads an already loaded `OctoBusDB` without modifying it, and otherwise requests server uptime once after entering the world with `.server info` to anchor restart estimates. Fresh dock sightings improve local anchors and dwell; repeated arrivals at the same terminal can learn an unseeded cycle estimate. Seeing a ship already docked does not invent its arrival time. Schedules save per realm, and a detected restart invalidates older arrival anchors. Timers need no open map.

**All `~` times and muted vehicle positions are estimates**, including OctoBus-derived schedules. Restart phases can drift; fresh local sightings take priority. Unmeasured services or terminal offsets show **Awaiting sync**, rather than an assumed half-cycle timer. In particular, the unmeasured Undercity end of Grom'gol–Undercity needs observation or a calibrated OctoBus offset. Unknown cycles need repeated observations of the same dock; a missed visit can initially produce a multiple-cycle estimate. The new prediction/sharing behavior has offline multi-client coverage; its live server accuracy still needs in-game validation.

At wide zoom, faint dotted lines show schematic service connections across loading boundaries. At closer zoom, they follow the native client paths and skip teleport edges. These links are not predicted live vehicle positions. Nearby berth icons cluster at low zoom; their hover lists every service. Route dots are pooled, clipped and capped at 384; stationary timer refreshes reuse the route drawing.

Version 1.3.3 adds a thin gold rim to currently detected nodes. Resource icons shrink smoothly from 17px to 3px dots at zone level, then fade away before continent/world view. Group and player markers retain their normal behavior.

Respawn swipes use **learned estimates**, with that label on hover. A site needs at least three consistent respawn intervals, observed while you remain within 45 yards and 20 vertical yards with the map and live scans running continuously. Gaps over two seconds, loading, leaving range, scan errors and a hidden map cancel the learning observation. A subsequent disappearance near you starts the learned swipe. Unknown/variable sites stay untimed. The circular ring has no numbers, hides at dot zoom, clears on actual detection and disappears at the estimated end without turning the node colorful. Learned samples and an unexpired estimate save across sessions, while all locations still start unknown after login. Shared locations do not transfer timing estimates or live state.

Version 1.3.2 fixes the invalid chat escape errors from node sharing. Messages use plain colon separators so WoW accepts them through pfUI and other chat wrappers. Failed sends back off for 30 seconds and leave markers/logs intact. If toggles have hidden everything, `/zmap nodes reset` enables Live, Logged and all resources without clearing locations or changing Share. The panel also explains when filters or display switches hide nodes. Restart WoW if the new circular textures have not yet loaded; otherwise this Lua fix can load with `/reload`.

Version 1.2.1 blends underground city and tunnel plans into the exterior and adds 284 cave/mining/crypt interiors from the installed client. Zooming into Ironforge or a supported cave reveals its interior above the surface; separate native floor plans stay visible at maximum zoom. Use the header's Layer/Floor control to change views. Fully exit and restart WoW to discover the new textures. Existing settings, pins and views are retained.

Open **Nodes** in the toolbar or type `/zmap nodes` for gathering. Choose individual resources or use the Herbs/Ore/Fishing/Treasure switches. Herbs, ore and fishing pools start enabled; treasure starts off. Choices save per resource name. Hover a resource for its name, availability, distance and height difference.

Version 1.3.1 uses circular resource icons with transparent corners. **Full color means your client currently detects the node. Grayscale means a logged location whose availability is unknown.** An observed location saves across sessions; when the node disappears, leaves detection range, or a scan fails, its marker becomes gray. Only detecting the same resource at that specific world position restores its color. Height separates nodes on different cave floors. Every saved location starts gray after login, regardless of its last observation. A learned estimate never proves current availability or depletion.

**Live** controls local scans through optional zAPI 2.4. They update twice per second while zMap is open and cover only objects loaded around your character. **Logged** controls grayscale history; turning Live off leaves history visible. Resource and category filters apply to both states. The catalogue contains 285 object identities / 198 resource names, including cached custom resources; unknown entries get explicit numbered names and their own toggles. The log stores up to 20,000 observed locations per realm; at its limit, additional detections remain live only. At most 512 icons display at once, with current detections taking priority. The panel reports these limits.

**Share** defaults on and automatically exchanges logged locations with other updated zMap users through the dedicated `zMapNodes31` background channel. This works outside parties and guilds, including with the map closed or without zAPI. Normal server channel/faction restrictions still apply. Shared locations start gray and remain unknown until your own client detects the node. Existing logs reconcile gradually, new locations are announced, and duplicates merge. Transfers batch up to three locations and share the single 15-second budget with transit; large logs take longer to reconcile, especially while chatting. Turning Share off leaves the channel and stops sending/receiving while preserving the locations already saved. No live availability, GUIDs, player coordinates or respawn schedules are shared.

Live gathering requires a separately installed zAPI 2.4 or later DLL. Fully exit and restart WoW after installing new textures or a native update. The atlas, history and sharing work without zAPI or any other addon. The resource catalogue is bundled and does not require pfQuest at runtime.

## Navigation

- Mouse wheel: animated zoom toward the cursor, continuously from both continents down to terrain and buildings.
- Left drag: pan freely across zone borders.
- Middle click or **Find me**: center on your character.
- Right click: zoom out.
- **World**, **Kalimdor**, **Eastern K.**: fit the selected extent.
- **Search maps...**: find classic/custom zones, cities, approaches, battlegrounds and available instance floors. Enter chooses the first result.
- **Look**: cycle hybrid, painted and terrain views. Hybrid transitions to full minimap terrain at close zoom, with underground plans above it.
- **Follow**: center on and track your character at the current zoom. Panning or zooming releases follow.
- Ctrl-click: save a pin. Right-click the pin to remove it. Up to 100 pins are saved.
- Drag the title to move the window, the bottom-right grip to resize, and **[ ]** for full screen. Escape closes it.

Window position, size, view, style and pins save automatically. Your player marker is the native directional minimap arrow; party and raid markers are circles with a dark rim and the client's class colors. Hover a group marker to see the member's name and class. On the large map, player/group markers keep their screen size while gathering icons scale with zoom. On the minimap, group markers share gathering's zoom multiplier. Marker hover targets allow normal dragging, scrolling and Ctrl-click pin placement.

Group positions can span both continents when the native client reports them. zMap briefly selects the hidden stock world map for one batched query, restores its previous selection and skips queries while the original map is open. Cached distant positions expire after five seconds; offline/departed members are removed. No peer sync or zAPI update is required, and unavailable positions are not guessed.

## Commands

| Command | Action |
| --- | --- |
| `/zmap` or `/zm` | Toggle zMap |
| `/zmap nodes` | Open gathering, history, sharing and individual resource filters |
| `/zmap nodes reset` | Restore Live, Logged and all resource visibility; keep the location log and sharing preference |
| `/zmap transit` | Open boat/zeppelin services, routes and dock arrival/departure estimates |
| `/zmap settings` | Configure the optional atlas minimap and its look |
| `/zmap hud` | Toggle the transparent, heading-up wall/node overlay |
| `/zmap hud quests` | Toggle optional pfQuest icons on the HUD |
| `/zmap hud align` | Measure feet height once and lock the HUD's vertical offset |
| `/zmap hud position` | Open live HUD horizontal/vertical offset sliders |
| `/zmap blizzard` | Open the original map, including other addons' normal map integrations |
| `/zmap replace` | Toggle which map M opens |
| `/zmap player` | Center on the player each time zMap opens |
| `/zmap last` | Reopen the saved view (default) |
| `/zmap reset` | Fit the whole world |
| `/zmap status` | Show version, atlas date and recent texture counts |
| `/zmap help` | Show controls and commands |

There are no required addons, libraries or injected DLLs. OptionalDeps ensure the toggle wrapper loads after common installed map/UI addons. The map runs using native 1.12 frames, textures and player map positions. zMap has its own rendering window; quest, gathering and flight markers from other addons remain on the original map (`/zmap blizzard`).

## Map data and coverage

The atlas is built from this installation's actual `WorldMapArea.dbc`, `WorldMapOverlay.dbc`, `AreaTable.dbc`, ADT terrain chunks and minimap translation table. The generated dataset contains 128 named map areas/floors and 2,487 verified minimap tiles across 34 map spaces, including 1,755 tiles in Eastern Kingdoms and Kalimdor. Custom world areas share the same continuous surface as their continent: Gilneas, Alah'Thalas, Thalassian Highlands, Tel'Abim, Blackstone Island, Hyjal, Balor, Northwind, Grim Reaches, Moonwhisper and the other named areas in the client data.

The native world overview preserves the original continental composition, without added continent labels or zone/level overlays. Zone paintings use physical map bounds and terrain area IDs. Their borders blend into one opaque atlas at several resolutions. Geometry tiles, player positions and pins share the same 533 1/3 yard ADT grid and native continent projection. Coarse terrain hands over to original full resolution minimap textures when fewer than 64 native tiles cover the view. Closest zoom is 4 UI pixels per world yard.

Close-up geometry is the client's top-down minimap rendering, including terrain and buildings. It has the resolution and age of those source textures. Underground locations can show the surface in those renders, so 13 georeferenced plans sit above that layer: Ironforge, Undercity, Blackrock Mountain, Caverns of Time, Timbermaw Tunnels and mapped cave/instance entrances. Shaped masks retain the usable floor and fade empty parchment into the exterior. The layer appears automatically as a plan grows large enough to read and stays visible through deep zoom in all three Look modes.

Version 1.2.1 also includes 284 placed cave, mine, crypt and tunnel interiors, assembled from the client's separate WMO minimap textures. Examples include Echo Ridge, Fargodeep, Jasperlode, Skull Rock, Frostmane Hold and Shadowthread Cave. Their native rotation, position and transparent footprint place them over the surface as you zoom in. Named caves are searchable. The header's Layer control cycles auto, surface and underground views. Where the client provides multiple floor plans, this control becomes a Floor selector. Separate underground spaces such as Frostmane Hollow retain their selected plan at deep zoom, and Follow updates it when the native map changes.

Painted maps are stylized drawings and may differ locally from terrain. Isolated instances use their own coordinate spaces and available floor art. Cave coverage follows the installed assets: 30 tilted placements and 14 placements with missing/unsupported minimaps are omitted rather than assigned guessed positions. WMO geometry is a top-down composite; distinct floor selection is available where the client supplies separate floor plans. The atlas reveals map art regardless of character exploration.

After a client content update, rebuild the generated assets to pick up changed bounds, artwork and tile names. See [SOURCE.md](SOURCE.md) and the maintenance folder alongside the addon.

## Validation

The 231-test offline suite covers map/marker/cave rendering, gathering history and item art, node timing/LOD, transport schedules/motion/sharing, marker caching, headings, the combined chat budget, Follow, the optional minimap, cross-continent group reports, HUD transforms/height/click-through, indoor positions, extra zoom, frame-rate following, circular HUD fading, camera-settle alignment, offset sliders/persistence, the HUD shortcut and pfQuest integration. The baseline uses a stock API stub without external addon dependencies. Integration tests load the installed pfQuest map and route modules and the installed pfUI chat wrapper. Tests include saved-state round trips, precise respawns and cave heights, native RGB and circular alpha, a 20,000-location history, duplicate suppression, delayed joins, malformed messages, throttling, failed-send backoff/retry, visibility recovery, sharing with the map closed, quest tooltips/clicks, route projection, player-arrow strata/level priority and independent viewports. The main map loads at most four textures per render; the miniature loads at most one, with independent caches. These checks do not measure live FPS, verify every minimap skin, confirm live cross-continent server reports, or confirm delivery through OctoWoW's live channel service.

The maintenance scripts and offline preview PNGs referenced in SOURCE.md belong to the local atlas-generation workspace (`../_zMapMaintenance`) and are not part of this runtime addon repository. Generated map assets, the complete addon Lua source and artwork notices are included. No account settings, saved node history or client archives are included.
