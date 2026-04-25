# ClawTV Support

ClawTV is a tvOS player for IPTV streams that you supply yourself. This page covers the most common questions.

## Getting started

1. Launch ClawTV on your Apple TV.
2. Tick the rights-attestation checkbox to confirm you have the right to access the streams you'll be loading.
3. Enter the URL of your **M3U playlist**. This usually comes from your IPTV provider.
4. Optionally enter the URL of an **XMLTV EPG** (program guide).
5. Done — your channels appear in the **Live** tab.

## Free trial

ClawTV offers a **7-day free trial** that begins the first time you launch the app. All features are unlocked during the trial. After the trial ends, you can unlock the app permanently with a one-time **$9.99** in-app purchase.

If you've already purchased and installed the app on a new device, tap **Settings → Restore Purchase**.

## Common questions

### Where do I get an M3U URL?

From your legitimate IPTV provider. ClawTV does not provide playlists. If you don't already have one, you don't need this app.

### Why does my playlist load slowly?

Large playlists (tens of thousands of channels) take a few seconds to parse. ClawTV caches the parsed result, so subsequent launches are fast. If your playlist is genuinely huge (50k+ channels), expect a slower first load.

### My EPG isn't showing programs

- Confirm the EPG URL is a valid XMLTV file (usually ends in `.xml` or `.xml.gz`).
- The EPG channel IDs need to match your M3U `tvg-id` values. ClawTV does fuzzy matching but cannot guarantee a match if your provider uses unconventional IDs.
- Try refreshing in **Settings → EPG → Refresh now**.

### A specific channel won't play

Stream URLs go stale, get geo-blocked, or change codec. ClawTV plays whatever your URL points to using the underlying VLC engine — if VLC can't open it, neither can the app. Try the same URL in another player to isolate.

### Can I sync my favorites between devices?

Not in v1. Everything stays on-device.

### Multi-View tiles aren't focusing the way I expect

Use the Siri Remote's hard click (press the touchpad) on a tile to bring up the focus context menu. From there you can pin one tile as the primary view, swap focus, or exit focus mode.

### How do I delete my data?

Delete the app. All data is stored locally; no server to call.

## Contact

For anything not covered here: **support@clawtv.app**

I read every email. Please include your tvOS version and Apple TV model so I can debug effectively.

## Privacy

ClawTV collects nothing. See the [Privacy Policy](privacy.html) for details.
