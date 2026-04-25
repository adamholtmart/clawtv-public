import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: PlaylistStore
    @EnvironmentObject var epg: EPGService
    @EnvironmentObject var entitlement: EntitlementStore
    @State private var newURL: String = ""
    @State private var newName: String = ""
    @State private var isAdding = false

    var body: some View {
        NavigationStack {
            Form {
                Section("ClawTV") {
                    if entitlement.isPurchased {
                        Label("Purchased — thanks for your support", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.tint)
                    } else if entitlement.isInTrial {
                        let days = entitlement.trialDaysRemaining
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Free trial — \(days) day\(days == 1 ? "" : "s") left",
                                  systemImage: "hourglass")
                                .foregroundStyle(.tint)
                            Text("Unlock now to keep using ClawTV after the trial ends.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Button {
                            Task { await entitlement.purchase() }
                        } label: {
                            HStack {
                                Image(systemName: "lock.open.fill")
                                Text(entitlement.product.flatMap { "Unlock ClawTV — \($0.displayPrice)" } ?? "Unlock ClawTV")
                            }
                        }
                        .disabled(entitlement.isPurchasing)
                    }
                    Button {
                        Task { await entitlement.restore() }
                    } label: {
                        Label("Restore Purchase", systemImage: "arrow.counterclockwise")
                    }
                    .disabled(entitlement.isRestoring)
                    if let err = entitlement.lastError {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                }

                Section("Playlists") {
                    if store.playlists.isEmpty {
                        Text("No playlists").foregroundStyle(.secondary)
                    }
                    ForEach(store.playlists) { playlist in
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(playlist.name).font(.headline)
                                Text(playlist.sourceURL.absoluteString)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                store.removePlaylist(playlist)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                Section("Add Playlist") {
                    TextField("Name (optional)", text: $newName)
                    TextField("M3U URL", text: $newURL)
                        .textContentType(.URL)
                    Button {
                        Task {
                            guard let url = URL(string: newURL), url.scheme != nil else { return }
                            isAdding = true
                            await store.addPlaylist(name: newName, url: url)
                            isAdding = false
                            newURL = ""; newName = ""
                        }
                    } label: {
                        if isAdding {
                            HStack { ProgressView(); Text("Adding…") }
                        } else {
                            Label("Add Playlist", systemImage: "plus.circle.fill")
                        }
                    }
                    .disabled(newURL.isEmpty || isAdding)
                }

                Section {
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        Label("Refresh All Playlists", systemImage: "arrow.clockwise")
                    }
                }

                Section("EPG (Program Guide)") {
                    TextField("EPG URL", text: $epg.epgURL)
                        .textContentType(.URL)
                    Button {
                        Task {
                            await epg.refresh()
                            await epg.rebuildM3UIndex(from: store.channels)
                        }
                    } label: {
                        if epg.isLoading {
                            HStack { ProgressView(); Text("Loading EPG…") }
                        } else {
                            Label("Refresh EPG", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(epg.isLoading)
                    LabeledContent("Channels in guide",
                                   value: "\(epg.epgChannels.count)")
                    LabeledContent("Channels with schedule",
                                   value: "\(epg.programmesByEPGId.count)")
                    LabeledContent("Stream matches (browse)",
                                   value: "\(epg.index.matched)/\(epg.index.total)")
                    if let last = epg.lastRefresh {
                        LabeledContent("Last refresh",
                                       value: last.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let err = epg.errorMessage {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                }

                Section("Stats") {
                    LabeledContent("Total channels", value: "\(store.channels.count)")
                    LabeledContent("Categories", value: "\(store.groups.count)")
                    LabeledContent("Pinned categories", value: "\(store.favoriteGroups.count)")
                    LabeledContent("Favorite channels", value: "\(store.favoriteChannels.count)")
                    LabeledContent("Recently watched", value: "\(store.recentlyWatched.count)")
                    if let last = store.lastRefresh {
                        LabeledContent("Channels last refreshed",
                                       value: last.formatted(date: .abbreviated, time: .shortened))
                    }
                }

                Section("Playback") {
                    Toggle("Resume last channel on launch", isOn: $store.resumeOnLaunchEnabled)
                }

                Section {
                    TextField("City (e.g. Buffalo)", text: $store.localCity)
                    LabeledContent("Local channels found",
                                   value: "\(store.localChannels.count)")
                } header: {
                    Text("Locals")
                } footer: {
                    Text("Channels whose name or category contains this city appear in a Locals row at the top of Home.")
                }

                Section("Data") {
                    Button(role: .destructive) {
                        store.clearRecentlyWatched()
                    } label: {
                        Label("Clear Recently Watched", systemImage: "clock.arrow.circlepath")
                    }
                    .disabled(store.recentlyWatched.isEmpty)

                    Button(role: .destructive) {
                        store.clearChannelCache()
                    } label: {
                        Label("Clear Channel Cache & Refetch", systemImage: "trash")
                    }
                }

                Section("About") {
                    LabeledContent("App", value: "ClawTV")
                    LabeledContent("Version", value: "1.0")
                }
            }
            .navigationTitle("Settings")
        }
    }
}
