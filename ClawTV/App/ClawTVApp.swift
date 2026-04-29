import SwiftUI

@main
struct ClawTVApp: App {
    @StateObject private var store = PlaylistStore()
    @StateObject private var epg = EPGService()
    @StateObject private var resolver = ChannelResolver()
    @StateObject private var entitlement = EntitlementStore()
    @StateObject private var parental = ParentalControls()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(epg)
                .environmentObject(resolver)
                .environmentObject(entitlement)
                .environmentObject(parental)
                .preferredColorScheme(.dark)
                .task {
                    #if DEBUG
                    if ScreenshotMode.needsShell, store.playlists.isEmpty {
                        await store.addPlaylist(name: "US Channels", url: ScreenshotMode.sampleListURL)
                    }
                    #endif
                    await store.refreshIfStale()
                }
                .task(id: store.channels.count) {
                    guard !store.channels.isEmpty else { return }
                    await epg.refreshIfStale()
                    await epg.rebuildM3UIndex(from: store.channels)
                }
                .task {
                    await entitlement.refresh()
                }
        }
    }
}
