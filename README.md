# ClawTV

A tvOS IPTV player. Bring your own M3U and XMLTV; ClawTV plays them beautifully on Apple TV.

This is the public/App Store fork. The personal/development fork lives at `clawtv` and contains MLB integration, DVR, CloudKit sync, and other features that don't ship in the public release.

## Build

Requires Xcode 15+ and a macOS host with the tvOS Simulator installed.

```bash
# 1. Fetch the TVVLCKit binary framework (~570 MB; not committed to git)
./scripts/fetch-vendor.sh

# 2. Generate the Xcode project from project.yml
xcodegen generate

# 3. Build for the tvOS Simulator
xcodebuild \
  -project ClawTV.xcodeproj \
  -scheme ClawTV \
  -destination 'platform=tvOS Simulator,name=Apple TV' \
  build
```

To run on a physical Apple TV, open `ClawTV.xcodeproj` in Xcode and select your device.

## Bundle / signing

- Bundle ID: `com.clawtv.player`
- Team: `6U9864P624` (paid Apple Developer Program)

If you need to change either, edit `project.yml` and re-run `xcodegen generate`.

## What's in the fork

- **Pure BYOC** — no bundled playlists, no default EPG sources, no demo content.
- **No iCloud / CloudKit** — entitlements file is empty. Zero personal data leaves the device.
- **No DVR / Recordings** — server-side recording isn't viable without iCloud and added App Review heat.
- **No Sports tab** — content-aware tabs invite review pushback for an IPTV app.
- **StoreKit 2 paywall** — 7-day free trial on first launch, then a one-time $9.99 non-consumable IAP unlock.
- **Privacy manifest** — declares zero tracking and only required-reason API usage.

## Trial & purchase

The 7-day trial timer starts on first launch (`EntitlementStore.swift`). After expiry the app shows `PaywallView` and gates everything behind the IAP unlock. Restore Purchase is always reachable from Settings.

For local testing, the bundled `Configuration.storekit` defines the `com.clawtv.player.unlock` non-consumable so you can exercise the purchase flow in the simulator without a sandbox account.

## Layout

```
ClawTV/
  App/                # ClawTVApp + RootView
  Models/             # M3U, EPG, channel, playlist models
  Services/           # Playlist + EPG parsers, EntitlementStore, etc.
  Views/              # Live, Guide, Multi-View, Settings, Paywall, Onboarding
  Resources/          # Localized strings, JSON seeds
  Assets.xcassets/    # Icon + colors + images
  Configuration.storekit
  PrivacyInfo.xcprivacy
  ClawTV.entitlements # empty — no iCloud, no special caps
  Info.plist
docs/
  privacy.md          # ships at clawtv.app/privacy
  support.md          # ships at clawtv.app/support
  appstore-listing.md # title/subtitle/description copy for App Store Connect
scripts/
  fetch-vendor.sh     # downloads TVVLCKit
project.yml           # xcodegen spec
```

## Releasing

1. Bump version + build in `project.yml`, regenerate.
2. Archive in Xcode (`Product → Archive`).
3. Upload via Xcode Organizer to App Store Connect.
4. Submit for review using the listing copy in `docs/appstore-listing.md` and the screenshots from `out/screenshots/`.

## License

Proprietary. All rights reserved. The TVVLCKit framework is distributed by VideoLAN under LGPL — see `Vendor/TVVLCKit-binary/COPYING.txt` after running `fetch-vendor.sh`.
