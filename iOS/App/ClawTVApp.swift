import SwiftUI

@main
struct ClawTVApp: App {
    @StateObject private var store = PlaylistStore()
    @StateObject private var epg = EPGService()
    @StateObject private var resolver = ChannelResolver()
    @StateObject private var entitlement = EntitlementStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(epg)
                .environmentObject(resolver)
                .environmentObject(entitlement)
                .preferredColorScheme(.dark)
                .task {
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
