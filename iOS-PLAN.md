# ClawTV iOS/iPadOS — Scoping Plan

## Approach: Single Xcode project, two targets

One repo, two app targets sharing all Models + Services.  
Views get a `Shared/` layer for logic and a `tvOS/` vs `iOS/` layer for presentation.

---

## What carries over unchanged

All of `ClawTV/Services/` and `ClawTV/Models/` — pure Swift, zero platform APIs:

- `M3UParser`, `EPGService`, `ChannelEPGIndex`, `GuideCurator`
- `PlaylistStore`, `ChannelResolver`, `EntitlementStore`
- `RefreshScheduler`, `CloudSync`, `ParentalControls`
- `Channel`, `EPGChannel`, `EPGProgramme`, `Playlist`
- `Localizable.xcstrings` (all 12 languages already done)

**Zero changes needed here.**

---

## Phase 1 — Project setup (1–2 days)

- [ ] Add `ClawTV-iOS` target in Xcode (iOS 16+, universal iPhone/iPad)
- [ ] Set `TARGETED_DEVICE_FAMILY = 1,2` (iPhone + iPad)
- [ ] Add `MobileVLCKit.xcframework` to `Vendor/` alongside `TVVLCKit.xcframework`
- [ ] Wrap the VLC player in a platform shim:
  ```
  // VLCPlayerView.swift — already exists for tvOS
  // VLCPlayerView+iOS.swift — new, same public API, uses MobileVLCKit
  ```
  Use `#if os(tvOS)` / `#if os(iOS)` at the file level.
- [ ] Add iOS `Info.plist` (portrait + landscape, `NSAppTransportSecurity` same as tvOS)
- [ ] Share all Models + Services source files between both targets (no copies)

---

## Phase 2 — Core navigation shell (2–3 days)

tvOS has a flat tab bar driven by the remote. iOS needs:

**iPhone**: `TabView` with `.tabBarStyle(.automatic)` — Home, Search, Guide, Settings  
**iPad**: Same `TabView` but consider a sidebar (`NavigationSplitView`) for the Guide and channel list

Key file: a new `ContentView+iOS.swift` that mirrors `ContentView.swift` but without `onExitCommand` and focus-engine wiring.

---

## Phase 3 — Layout adaptation (1 week)

Every view needs layout variants. Pattern to follow:

```swift
// In each view file:
#if os(tvOS)
private let columns = Array(repeating: GridItem(.fixed(260), spacing: 32), count: 5)
private let hPad: CGFloat = 60
#else
private var columns: [GridItem] {
    UIDevice.current.userInterfaceIdiom == .pad
        ? Array(repeating: GridItem(.adaptive(minimum: 180)), count: 3)
        : [GridItem(.adaptive(minimum: 150))]
}
private let hPad: CGFloat = 16
#endif
```

Views needing adaptation:

| View | Change needed |
|------|--------------|
| `HomeView` | Replace 5-col fixed grid + 60pt padding. Remove `.card` button style (×4). |
| `AllChannelsView` | Same grid/padding swap. Remove `.card`. |
| `FavoritesView` | Same. Remove `.card`. |
| `SearchView` | Shrink header font (36pt → system default). Grid columns. Remove `.card`. |
| `GuideView` | Biggest change — horizontal scroll timeline works on iPad; phone needs a day-list fallback. Remove `.card` (×4). |
| `SettingsView` | Already form-based — should mostly work. Check font sizes. |
| `PaywallView` | Update copy ("beautiful tvOS player" → platform-neutral). |
| `OnboardingView` | Likely works as-is. Check button padding. |
| `ChannelPickerSheet` | Remove `.card`. |
| `MultiViewAddChannelView` | Remove `onExitCommand`. |

**`.card` button style** appears 12 times across 8 files.  
iOS replacement: `.buttonStyle(.plain)` with a custom hover/press modifier.

---

## Phase 4 — Player (3–4 days)

The player is the biggest risk.

**Option A — MobileVLCKit everywhere (iOS too)**  
- Same code path, same codec support  
- `MobileVLCKit.xcframework` is ~85 MB → ~40 MB after thinning  
- App Store limit is 4 GB, so size isn't a hard blocker but it's heavy  

**Option B — AVPlayer primary, VLC fallback (recommended)**  
- Use `AVPlayer` for HLS/MP4 (most IPTV streams today)  
- Fall back to VLC for TS/RTMP/other  
- Lighter, better battery, AirPlay works natively  
- More code to write (~3 days for the AVPlayer wrapper + fallback logic)  

Recommendation: **Option B** for iOS. The tvOS target keeps TVVLCKit unchanged.

New files:
- `AVPlayerView.swift` — iOS AVPlayer wrapper (SwiftUI `UIViewRepresentable`)
- `PlayerCoordinator.swift` — decides AVPlayer vs VLC based on stream URL scheme/extension
- `VLCPlayerView+iOS.swift` — fallback, wraps MobileVLCKit

`PlayerView.swift`:
- Remove `onExitCommand` (iOS back button handles dismiss)
- Remove `.focusable(true)` / `@FocusState`
- Add standard transport controls (AVKit's `VideoPlayer` gives these free if using AVPlayer)

---

## Phase 5 — Platform-specific features (2–3 days)

**Features to skip on iOS v1:**
- Multi-View (4-up layout) — skip entirely on iPhone; iPad-only stretch goal
- Top Shelf extension — tvOS only, no equivalent
- Remote-control gestures (swipe left/right on Siri Remote)

**Features that need iOS variants:**
- PiP — AVKit on iOS has native PiP support; wire up `AVPictureInPictureController`
- `onExitCommand` (×3 files) → remove; iOS uses navigation stack back button
- `focusable(true)` (×3 files) → remove; not meaningful on touch
- Context menus — `.contextMenu` works on iOS (long press), no changes needed

**New iOS-only features to consider:**
- Share sheet for stream URL  
- Shortcuts/Siri integration (stretch)  
- Lock screen / Control Center now-playing (free with AVPlayer)

---

## Phase 6 — App Store setup (1 day)

- New bundle ID: `com.clawtv.player.ios` (or `com.clawtv.ios`)
- Separate App Store listing vs. Universal Purchase?
  - **Recommendation: Universal Purchase** — one purchase unlocks both tvOS and iOS. Set up in App Store Connect as a separate app but link them under the same IAP product IDs.
- New screenshots: iPhone 6.7", iPad 12.9"
- Same privacy policy / support URL (already live)

---

## Summary of files to create

```
ClawTV-iOS/
  App/
    ClawTVApp+iOS.swift        # iOS app entry point
  Views/
    ContentView+iOS.swift      # tab shell without tvOS focus wiring
    HomeView+iOS.swift         # or #if blocks in HomeView.swift
    GuideView+iOS.swift        # phone layout for guide
    PlayerView+iOS.swift       # AVPlayer-based player
  Player/
    AVPlayerView.swift         # UIViewRepresentable for AVPlayer
    PlayerCoordinator.swift    # AVPlayer vs VLC routing
    VLCPlayerView+iOS.swift    # MobileVLCKit fallback
```

All Services + Models shared, no duplication.

---

## Total estimate

| Phase | Work |
|-------|------|
| Project setup | 1–2 days |
| Navigation shell | 2–3 days |
| Layout adaptation | ~1 week |
| Player | 3–4 days |
| Platform features | 2–3 days |
| App Store setup | 1 day |
| **Total** | **~4–5 weeks** |

Most of that is layout work and the player rewrite. The services are free.

---

## Recommended order to start

1. Get the iOS target building (even if UI is broken) — validates the services compile cleanly
2. Swap out `.card` button styles across all views (mechanical, low risk)
3. Build the AVPlayer wrapper
4. Adapt `HomeView` as the template, then repeat the pattern for other views
