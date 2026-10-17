# zMap 1.4.0

Standalone seamless atlas for the installed OctoWoW 1.12 client, with zSuite's dark window, mint branding, `z_Map` folder, `zMapDB` settings and zSuite keybinding group.

Part of the [zSuite addons by Zab](https://github.com/zabuu). Public repository: [zabuu/z_Map](https://github.com/zabuu/z_Map).

## Installation

1. Download [the latest source ZIP](https://github.com/zabuu/z_Map/archive/refs/heads/main.zip) and extract it into your OctoWoW `Interface\AddOns` folder.
2. Rename the extracted `z_Map-main` folder to **`z_Map`**. The TOC must be at `Interface\AddOns\z_Map\z_Map.toc`.
3. Fully exit and restart WoW so it discovers the bundled map and marker textures. Enable **zMap** in the AddOns list.

Alternatively, run `git clone https://github.com/zabuu/z_Map.git z_Map` from `Interface\AddOns`.

The map works without other addons or native extensions. Live gathering is optional and requires **zAPI 2.4 or later**, installed separately in the game directory; this repository does not install a DLL. Without it, the atlas and saved/shared locations still work. Artwork ownership and the source-code license are explained in [NOTICE.md](NOTICE.md) and [LICENSE](LICENSE).

Enable **zMap** in the character selection AddOns list after restarting the client. Press **M**, `/zmap`, or `/zm` to open it. The world map microbutton also opens zMap.


Version 1.4.0 adds **experimental zeppelin and boat tracking**. Open **Transit** in the header or `/zmap transit`. Terminal icons sit at the client's actual berths/piers; hover for both ends' arrival/departure estimates and their sources. The scrolling service list also centers the map on a terminal. Transit, route lines and map timer labels have separate saved switches. Fully exit and restart WoW for the new boat/zeppelin textures.

With the separately installed **ZepSense** reader (`ZepTransports()`), brighter moving vehicle icons show the actual positions of transports loaded by your client, including docking and departure. They update twice per second, even with the map closed, and disappear when the client stops detecting them. No native update is installed by zMap. The atlas, route geometry and dock schedules work without that reader or any other addon. zAPI's gathering snapshot does not supply global transport positions.

The catalogue contains 13 native client routes / 26 terminals, including Kargath, Thunder Bluff, Sparkwater–Revantusk and Alah'Thalas. Ten identities are present in this installation's object cache; three additional classic boat services have client paths but remain **Service unconfirmed** until observed on this server. Client route assets alone do not prove that a service is running.

Seven services have measured cycle/dwell seeds from the installed OctoBus: the five zeppelin routes, Sparkwater–Revantusk and Ratchet–Booty Bay. zMap reads an already loaded `OctoBusDB` without modifying it, and otherwise requests server uptime once after entering the world with `.server info` to anchor restart estimates. Fresh dock sightings improve local anchors and dwell; repeated arrivals at the same terminal can learn an unseeded cycle estimate. Seeing a ship already docked does not invent its arrival time. Schedules save per realm, and a detected restart invalidates older arrival anchors. Timers need no open map. No new chat channel is joined for transport tracking.

**All `~` times are estimates**, including OctoBus-derived schedules. Restart phases can drift; fresh local sightings take priority. Unmeasured services or terminal offsets show **Awaiting sync**, rather than an assumed half-cycle timer. In particular, the unmeasured Undercity end of Grom'gol–Undercity needs observation or a calibrated OctoBus offset. Unknown cycles need repeated visits to the same dock; a missed visit can initially produce a multiple-cycle estimate. This experimental build needs in-game timing checks.

At wide zoom, faint dotted lines show schematic service connections across loading boundaries. At closer zoom, they follow the native client paths and skip teleport edges. These links are not predicted live vehicle positions. Nearby berth icons cluster at low zoom; their hover lists every service. Route dots are pooled, clipped and capped at 384; stationary timer refreshes reuse the route drawing.

Version 1.3.3 adds a thin gold rim to currently detected nodes. Resource icons shrink smoothly from 17px to 3px dots at zone level, then fade away before continent/world view. Group and player markers retain their normal behavior.

Respawn swipes use **learned estimates**, with that label on hover. A site needs at least three consistent respawn intervals, observed while you remain within 45 yards and 20 vertical yards with the map and live scans running continuously. Gaps over two seconds, loading, leaving range, scan errors and a hidden map cancel the learning observation. A subsequent disappearance near you starts the learned swipe. Unknown/variable sites stay untimed. The circular ring has no numbers, hides at dot zoom, clears on actual detection and disappears at the estimated end without turning the node colorful. Learned samples and an unexpired estimate save across sessions, while all locations still start unknown after login. Shared locations do not transfer timing estimates or live state.

Version 1.3.2 fixes the invalid chat escape errors from node sharing. Messages use plain colon separators so WoW accepts them through pfUI and other chat wrappers. Failed sends back off for 30 seconds and leave markers/logs intact. If toggles have hidden everything, `/zmap nodes reset` enables Live, Logged and all resources without clearing locations or changing Share. The panel also explains when filters or display switches hide nodes. Restart WoW if the new circular textures have not yet loaded; otherwise this Lua fix can load with `/reload`.

Version 1.2.1 blends underground city and tunnel plans into the exterior and adds 284 cave/mining/crypt interiors from the installed client. Zooming into Ironforge or a supported cave reveals its interior above the surface; separate native floor plans stay visible at maximum zoom. Use the header's Layer/Floor control to change views. Fully exit and restart WoW to discover the new textures. Existing settings, pins and views are retained.

Open **Nodes** in the toolbar or type `/zmap nodes` for gathering. Choose individual resources or use the Herbs/Ore/Fishing/Treasure switches. Herbs, ore and fishing pools start enabled; treasure starts off. Choices save per resource name. Hover a resource for its name, availability, distance and height difference.

Version 1.3.1 uses circular resource icons with transparent corners. **Full color means your client currently detects the node. Grayscale means a logged location whose availability is unknown.** An observed location saves across sessions; when the node disappears, leaves detection range, or a scan fails, its marker becomes gray. Only detecting the same resource at that specific world position restores its color. Height separates nodes on different cave floors. Every saved location starts gray after login, regardless of its last observation. A learned estimate never proves current availability or depletion.

**Live** controls local scans through optional zAPI 2.4. They update twice per second while zMap is open and cover only objects loaded around your character. **Logged** controls grayscale history; turning Live off leaves history visible. Resource and category filters apply to both states. The catalogue contains 285 object identities / 198 resource names, including cached custom resources; unknown entries get explicit numbered names and their own toggles. The log stores up to 20,000 observed locations per realm; at its limit, additional detections remain live only. At most 512 icons display at once, with current detections taking priority. The panel reports these limits.

**Share** defaults on and automatically exchanges logged locations with other updated zMap users through the dedicated `zMapNodes31` background channel. This works outside parties and guilds, including with the map closed or without zAPI. Normal server channel/faction restrictions still apply. Shared locations start gray and remain unknown until your own client detects the node. Existing logs reconcile gradually, new locations are announced, and duplicates merge. Transfers use batches of up to three locations, at most one message per second per client; large logs take time. Turning Share off leaves the channel and stops sending/receiving while preserving the locations already saved. No live availability, GUIDs, player coordinates or respawn schedules are shared.

Live gathering requires a separately installed zAPI 2.4 or later DLL. Fully exit and restart WoW after installing new textures or a native update. The atlas, history and sharing work without zAPI or any other addon. The resource catalogue is bundled and does not require pfQuest at runtime.

## Navigation

- Mouse wheel: animated zoom toward the cursor, continuously from both continents down to terrain and buildings.
- Left drag: pan freely across zone borders.
- Middle click or **Find me**: center on your character.
- Right click: zoom out.
- **World**, **Kalimdor**, **Eastern K.**: fit the selected extent.
- **Search maps...**: find classic/custom zones, cities, approaches, battlegrounds and available instance floors. Enter chooses the first result.
- **Look**: cycle hybrid, painted and terrain views. Hybrid transitions to full minimap terrain at close zoom, with underground plans above it.
- **Follow**: keep the map centered on your character. Panning or zooming releases follow.
- Ctrl-click: save a pin. Right-click the pin to remove it. Up to 100 pins are saved.
- Drag the title to move the window, the bottom-right grip to resize, and **[ ]** for full screen. Escape closes it.

Window position, size, view, style and pins save automatically. Your player marker is mint; party and raid markers are circles with a dark rim and the client's class colors. Hover a group marker to see the member's name and class. Player/group markers keep their screen size; gathering icons scale with zoom. Marker hover targets allow normal dragging, scrolling and Ctrl-click pin placement.

## Commands

| Command | Action |
| --- | --- |
| `/zmap` or `/zm` | Toggle zMap |
| `/zmap nodes` | Open gathering, history, sharing and individual resource filters |
| `/zmap nodes reset` | Restore Live, Logged and all resource visibility; keep the location log and sharing preference |
| `/zmap transit` | Open boat/zeppelin services, routes and dock arrival/departure estimates |
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

All 70 offline regressions pass: 37 map/marker/cave tests, nine live gathering tests, seven history/icon tests, nine multi-client sharing tests and eight node presentation/timing tests. The baseline uses a stock API stub without external addon dependencies. The chat regression also loads the installed pfUI macrotweak wrapper over a native-like validator that rejects raw pipe escapes. Tests include saved-state round trips, precise respawns and cave heights, native RGB and circular alpha, a 20,000-location history, duplicate suppression, delayed joins, malformed messages, throttling, failed-send backoff/retry, visibility recovery and sharing with the map closed. The overview still draws four textures; new map loads remain limited to four per render, and at most 64 cave tiles participate. These checks do not measure live FPS or confirm delivery through OctoWoW's live channel service.

The maintenance scripts and offline preview PNGs referenced in SOURCE.md belong to the local atlas-generation workspace (`../_zMapMaintenance`) and are not part of this runtime addon repository. Generated map assets, the complete addon Lua source and artwork notices are included. No account settings, saved node history or client archives are included.
