import SwiftUI

struct GuideSetupView: View {
    @EnvironmentObject var store: PlaylistStore
    @Environment(\.dismiss) private var dismiss
    let isFirstRun: Bool

    @State private var searchText = ""
    @State private var selected: Set<String> = []
    @State private var isSaving = false

    private var filteredGroups: [ChannelGroup] {
        if searchText.isEmpty { return store.groups }
        return store.groups.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List {
                // Action buttons at the top — always reachable with the tvOS remote
                Section {
                    Button {
                        guard !isSaving else { return }
                        isSaving = true
                        store.setGuidePinnedGroups(selected)
                        Task {
                            try? await Task.sleep(for: .milliseconds(500))
                            dismiss()
                        }
                    } label: {
                        Label("Save Guide Groups", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .disabled(isSaving || selected.isEmpty)

                    Button {
                        selected = Set(store.groups.map(\.name))
                    } label: {
                        Label("Select All", systemImage: "checkmark.square.fill")
                    }

                    Button {
                        selected.removeAll()
                    } label: {
                        Label("Clear All", systemImage: "square")
                    }

                    Button {
                        dismiss()
                    } label: {
                        Label(isFirstRun ? "Skip for Now" : "Cancel", systemImage: "xmark")
                    }
                } header: {
                    Text(isFirstRun ? "Build Your Guide" : "Actions")
                } footer: {
                    if isFirstRun {
                        Text("Choose the channel groups you want in your Guide. You can change this anytime in Settings.")
                    }
                }

                // Group picker
                Section {
                    ForEach(filteredGroups) { group in
                        Button {
                            if selected.contains(group.name) {
                                selected.remove(group.name)
                            } else {
                                selected.insert(group.name)
                            }
                        } label: {
                            HStack(spacing: 16) {
                                Image(systemName: selected.contains(group.name)
                                      ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(group.name) ? Color.accentColor : Color.secondary)
                                    .font(.system(size: 22))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group.name)
                                        .font(.headline)
                                    Text("\(group.channels.count) channels")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                    }
                } header: {
                    Text("\(selected.count) of \(store.groups.count) groups selected")
                }
            }
            .searchable(text: $searchText, prompt: "Search groups")
            .navigationTitle(isFirstRun ? "Build Your Guide" : "Guide Groups")
        }
        .background(Color(white: 0.094).ignoresSafeArea())
        .overlay {
            if isSaving {
                ZStack {
                    Color(white: 0.094).ignoresSafeArea()
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Building your guide…")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
                .transition(.opacity)
            }
        }
        .onAppear {
            selected = store.guidePinnedGroups
        }
    }
}
