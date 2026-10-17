# Changelog

## 1.3.3 — October 17, 2026

- Added a thin gold circular rim only to locally detected resource markers.
- Added smooth 17px-to-3px icon scaling, category-colored live dots and gray logged dots at zone zoom. Markers fade away before continent/world view; hidden overviews skip history traversal.
- Added number-free circular respawn swipes using local learned estimates. A spot needs at least three consistent nearby, continuously observed cycles. Range loss, scan errors, map hiding/loading and gaps do not teach a respawn. Estimates are labeled on hover, survive relogs, clear on actual detection and never turn a predicted node live.
- Used a transparent 64-frame ring atlas rather than native cooldown frames, preventing third-party cooldown numbers. Swipes hide at dot zoom and update only on displayed markers.
- Preserved the 1.3.2 chat-escape fix and visibility-recovery command. Added eight presentation/timing regressions; all 70 offline checks pass. Fully restart WoW to discover the new ring textures.

## 1.3.2 — October 17, 2026

- Fixed repeated Invalid escape code in chat message errors: gathering sharing packets now use plain colon separators instead of raw pipes. The error surfaced through pfUI's forwarding wrapper; pfUI itself is unchanged.
- Failed sharing sends back off for 30 seconds and retry queued observations without hiding markers or erasing history. Sharing status reports the retry state.
- Added `/zmap nodes reset` to restore Live, Logged and resource visibility while preserving the location log and Share preference. The panel explains when display switches or filters hide everything.
- Reproduced the failure with a chat escape validator, then verified corrected summary/data messages through the installed pfUI wrapper. Added visibility-recovery and transport-failure coverage; all 62 offline regressions pass.

## 1.3.1 — October 17, 2026

- Cropped every gathering category icon to an antialiased circle. Current detections retain native full color; saved locations use matching grayscale textures.
- Added a persistent per-realm observation log. Resource identity and physical XYZ match respawns to their saved marker, including a new GUID, while keeping different cave heights separate. Missing or unverified nodes stay gray with an Availability unknown tooltip.
- Added a Logged toggle. Resource/category filters apply to current and logged nodes; stopping Live scans leaves history visible. History uses viewport spatial indices, a 20,000-location cap and the existing 512-icon cap, with live detections first.
- Added automatic location sharing with other updated users through a dedicated background channel, plus a Share toggle. Shared records are gray until locally detected. Batches, pacing, summaries, duplicate suppression and validation bound transfer work; sharing continues with the map closed.
- Added 14 history/icon/multi-client sharing regressions; all 60 offline tests pass. The map workload remains unchanged and zAPI stays at 2.4. Fully restart WoW for the new icon textures.

## 1.3.0 — October 17, 2026

- Added live herb, ore, fishing-pool and treasure markers through zAPI 2.4, with a Nodes panel, individual resource toggles, category switches, name filtering and saved preferences.
- Added 285 bundled resource identities representing 198 names. Positions come exclusively from current native snapshots. No saved or predicted spawn database is drawn.
- Live markers update at 0.5-second intervals while the window and feature are enabled. Despawns, map transitions and failures clear old state. Hover shows name, distance and height difference; map input still passes through.
- Reused native/Lua buffers, node records, icon frames and stable anchors. The panel adapts to the minimum window height; at most 512 resource icons are shown.
- The standalone atlas remains available without zAPI. Existing map geometry, city/cave artwork and party markers are unchanged. Fully restart WoW after the native update.

## 1.2.1 — October 16, 2026

- Replaced rectangular underground-plan fades with shaped city/corridor footprints, wider falloffs and full 8-bit alpha. Empty parchment and corner ornaments now fade into the exterior.
- Added 284 placed cave, mine, crypt and tunnel interiors from native WMO minimaps, including classic and custom assets. Native MODF placement controls alignment; transparent padding is cropped and cave edges soften inward.
- Added searchable cave names and a Layer control for auto/surface/underground. It becomes a Floor selector for areas with multiple native plans. Selected interior plans remain above exterior terrain at maximum zoom; Follow selects the player's native floor.
- Shared the existing four-new-texture budget, hid incomplete cave plans and limited participating cave tiles to 64. The four-tile World view is unchanged.
- Excluded tilted or unavailable cave minimaps; see README/SOURCE for coverage limits. All 37 offline regressions pass.

Fully restart WoW. `/zmap status` reports 1.2.1 and separate interior/cave texture counts.

## 1.2.0 — October 16, 2026

- Added an automatic underground-plan layer above exterior geometry. Ironforge and Undercity remain visible at deep zoom, including when browsing from the surrounding zone.
- Included 11 other georeferenced cave, tunnel and entrance plans from the installed client. Open-air cities retain their existing terrain rendering; isolated instance spaces keep their existing map context.
- Interior art fades in as its projected size grows, has smooth full-alpha edges, and waits for all visible pieces before appearing. Player/group markers and pins remain above it in the same coordinates.
- Retained viewport culling, stable texture reuse and the four-new-texture budget. Existing world, water, terrain, settings and pins are unchanged.

Fully restart WoW after updating. `/zmap status` reports 1.2.0 and an interior texture count.

## 1.1.2 — October 16, 2026

- All party/raid classes now use antialiased circular markers with a dark rim. The neutral white texture preserves class colors and hover behavior.
- Darkened the continuous ocean material by approximately 20%.
- Added coastline-based fading to painted sea areas. Land, snow and small islands remain visible; offshore frames, sea labels and decorations fade away before the map rectangle ends.
- New painting paths avoid cached old water. The overview, physical projection, native geometry paths, pins and texture-loading budgets are unchanged.

Fully restart WoW after updating. `/zmap status` reports 1.1.2.

## 1.1.1 — October 16, 2026

- Party and raid markers use class colors and show the member's name and class on hover. Roster changes refresh an open tooltip; hidden or removed members clear it. Raid markers omit the player to retain the distinct mint player marker.
- Marker hover targets pass map dragging, wheel zoom and pin placement through to the viewport.
- Replaced the small mirrored ocean swatch with a continuous blue-grey texture with subtle variation across the full atlas. New painting paths avoid cached old water. World art, projection and native geometry paths remain unchanged.

Fully restart WoW after updating. `/zmap status` reports 1.1.1.

## 1.1.0 — October 16, 2026

- Replaced the full-world zone patchwork with the native Azeroth overview, without added continent labels or zone/level overlays.
- Registered both continents using the installed client's WorldMapContinent projection; migrated existing main-world pins and reset the obsolete camera.
- Blended neighbouring zone paintings before export and switched opaque art to native-format DXT1, removing the DXT3 border-alpha bands.
- Added four painted resolutions, spatial culling, stable texture bindings, coarse fallbacks, a four-map-texture loading budget per render, and a 64-native-tile cap. Rechecked current OpenMap source for these rendering techniques.
- Added projection, migration, culling and loading regressions plus an actual Lua workload comparison against 1.0.1. The world overview now draws four textures instead of 177.

Fully restart WoW to load the new texture paths. `/zmap status` reports 1.1.0 and recent texture counts.

## 1.0.1 — October 16, 2026

Fixed corrupt striped textures at world and medium zoom by regenerating the painted atlas and terrain overview as DXT3 BLP2, matching native client map overlays. The initial palette encoder wrote an incompatible alpha selector that the offline decoder did not reject. New texture paths avoid reusing the old texture cache keys. Map coordinates, zoom, and original close-up geometry tiles are unchanged.

Added checks against a real client texture header and independent BLP/DDS decoders. Fully restart WoW after updating.
