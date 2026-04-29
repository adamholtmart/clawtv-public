# ClawTV Roadmap

## v1.0 — Shipped (April 2026)
BYOC tvOS player. Free download + 7-day trial + $9.99 one-time IAP unlock.

- M3U / M3U8 playlist loader
- Xtream Codes API support
- XMLTV EPG (full guide + now/next)
- Multi-View (up to 4 simultaneous streams)
- Favorites
- Search (channel, group, EPG title)
- Playlist groups + filtering
- Resume / last-watched
- Top Shelf integration
- Zero data collection (privacy manifest declares none)

## v1.1 — Next

### Feature parity gaps vs competitors
- **Catch-up / time-shift playback** — Xtream `catch-up` API (Smarters Pro's flagship feature)
- **VOD + Series sections** — Xtream movies/series endpoints; full catalog browse + playback
- **External subtitle file support** — `.srt` / `.vtt` sidecar files
- **Parental PIN / channel locks** — table stakes for family installs
- **Playlist auto-refresh schedule** — cron-style EPG/M3U refresh (TiviMate parity)

### Cross-device sync
- **iCloud Key-Value Store** (`NSUbiquitousKeyValueStore`)
  - Sync M3U URL, Xtream server/user/pass, XMLTV EPG URL, favorites, group/filter prefs
  - Do NOT sync M3U contents (re-fetch per device) or EPG cache
  - IAP/trial state already syncs via Apple ID receipt (StoreKit)
  - Default on; opt-out toggle in Settings
  - ~2 hours of work — wrap settings store in KVS-backed shim + first-launch loading indicator
  - Marketing angle: family-shareable IAP + iCloud sync = "buy once, configure once, works on every Apple TV in the house"

## Deliberately out of scope
- DVR / cloud recording (positioning conflict — pushes toward subscription model)
- HDHomeRun / OTA tuner integration (niche; brand fragmentation)
- Multi-profile users (feature creep for $9.99 single-purchase)
- Bundled playlists or any third-party content (App Review red line)
- Picture-in-Picture (Multi-View covers the use case — up to 4 simultaneous streams beats single-PiP)
