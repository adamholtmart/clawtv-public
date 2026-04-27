# r/iptv launch post template

> Internal — not published to the docs site (excluded via `_config.yml`).

## Title (60 chars)

ClawTV — clean tvOS M3U/EPG player, 7-day free trial then $9.99

## Body

Hey r/iptv,

I've been building a tvOS player for my own M3U + XMLTV setup over the past few months and finally polished it enough to put on the App Store. Wanted to share it here first — this community shaped a lot of the decisions, so it feels right.

**What it is**

ClawTV is a native tvOS player. It does not provide, host, or sell any content — strictly bring-your-own M3U playlist URL and XMLTV EPG source, same model as Sparkle TV / Smarters Pro / iMPlayer.

**Pricing**

- Free download
- 7-day free trial — every feature unlocked, no cards needed up-front
- $9.99 one-time to keep using it after day 7
- No subscriptions, no servers, no ads, no tracking

**Features**

- Native SwiftUI / Siri Remote-first design
- EPG via your own XMLTV URL — channel matching that handles the usual M3U / XMLTV ID drift
- Multi-View — up to 4 channels at once, hard-press to focus a tile (72/28 split), hard-press another tile to swap into focus
- Favorites, history, instant search across your whole playlist
- All settings live on your Apple TV — playlists, EPG sources, refresh intervals
- Privacy: zero data collection. Privacy nutrition label is "Data Not Collected." I'd be happy to publish the network call list if anyone wants to verify.

**What it isn't**

- Not a service. Doesn't ship with any pre-loaded channels, sample playlists, or "demo" URLs. Empty until you add your own.
- Not a DVR. Recording was tested but cut to keep the privacy story clean and avoid CloudKit dependencies.
- Not a Plex / Channels DVR competitor. It's just a polished player.

**Why a paid app and not free with ads**

I hate the ad-supported player flow as a user, and the pay-once model lets me skip every server-side cost. The 7-day trial means you can prove it works with your specific playlist before paying — which is the #1 complaint I see in this subreddit about other apps.

**Compatibility**

- Apple TV HD or Apple TV 4K
- tvOS 17 or newer
- Any standard M3U / M3U8 playlist URL
- Any XMLTV EPG URL

**Feedback wanted**

If you want to TestFlight before the v1.0 ship, drop a comment or DM your Apple ID email and I'll add you to the external group. Looking for ~10–20 people running varied provider setups (Latin American IPTV, EU services, US niche providers, self-hosted xTeve / TVHeadend, etc.) so I can break the EPG matcher properly.

Happy to answer anything in the thread. Thanks for the years of unfiltered opinions on this stuff — they made the app better.

— Adam

---

## Posting checklist

- [ ] Wait until app is live on App Store (don't post pre-launch — r/iptv mods auto-remove pre-release self-promo)
- [ ] Use post flair "App / Software" if available
- [ ] Skip TestFlight call-out if launching cold (mention only if seeking pre-launch feedback)
- [ ] Reply quickly to first 3-4 comments — early engagement decides ranking
- [ ] Pin a top reply with the App Store link + one-line privacy summary
- [ ] Don't post multiple times — duplicate self-promo gets banned
- [ ] Cross-post to r/AppleTV after 24h once the r/iptv discussion has settled

## Other launch surfaces

- **r/AppleTV** — separate post, lighter on IPTV jargon, lead with native tvOS / Siri Remote design
- **r/Plex** — only if a Plex Live TV scenario is genuinely supported (not v1.0)
- **r/cordcutters** — too broad, will get downvoted as off-topic; skip
- **HN Show** — only if there's a story angle ("BYOC IPTV player got past App Review with 7-day in-app trial via StoreKit 2") — could work post-launch
- **Provider customer-recommendation lists** — message a handful of legitimate IPTV providers offering ClawTV as a recommended player; this drives the most installs long-term
