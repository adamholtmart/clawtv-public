import SwiftUI

struct PiPView: View {
    let pair: [Channel]     // always 2 elements
    let onExit: () -> Void

    @EnvironmentObject var store: PlaylistStore
    @State private var mainIdx: Int = 0
    @State private var statuses: [PlayerStatus] = [.loading, .loading]
    @State private var errorTexts: [String?] = [nil, nil]
    @FocusState private var pipFocused: Bool

    private let pipSize = CGSize(width: 400, height: 225)
    private var pipIdx: Int { 1 - mainIdx }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color.black.ignoresSafeArea()

                // Both players with stable IDs — only muted/size/offset change on swap
                ForEach(0..<2, id: \.self) { i in
                    let isMain = (i == mainIdx)
                    VLCPlayerView(
                        url: pair[i].streamURL,
                        status: statusBinding(i),
                        errorText: errorBinding(i),
                        muted: !isMain,
                        paused: false
                    )
                    .frame(
                        width: isMain ? geo.size.width : pipSize.width,
                        height: isMain ? geo.size.height : pipSize.height
                    )
                    .clipShape(RoundedRectangle(cornerRadius: isMain ? 0 : 12))
                    .offset(
                        x: isMain ? 0 : geo.size.width - pipSize.width - 60,
                        y: isMain ? 0 : geo.size.height - pipSize.height - 60
                    )
                    .zIndex(isMain ? 0 : 1)
                    .animation(.easeInOut(duration: 0.25), value: mainIdx)
                }

                // Focusable controls overlay for the PiP corner (separate layer so VLC stays stable)
                ZStack(alignment: .bottomLeading) {
                    Color.clear
                    Text(pair[pipIdx].name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.black.opacity(0.7), in: .capsule)
                        .padding(10)
                }
                .frame(width: pipSize.width, height: pipSize.height)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(pipFocused ? Color.white : Color.white.opacity(0.4),
                                lineWidth: pipFocused ? 3 : 1)
                )
                .scaleEffect(pipFocused ? 1.04 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: pipFocused)
                #if os(tvOS)
                .focusable(true)
                .focused($pipFocused)
                #endif
                .onTapGesture { swapChannels() }
                .contextMenu {
                    Button { swapChannels() } label: {
                        Label("Swap Channels", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Button { store.openChannel(pair[pipIdx]) } label: {
                        Label("Watch Full Screen", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                    Button(role: .destructive) { onExit() } label: {
                        Label("Close PiP", systemImage: "xmark.circle")
                    }
                }
                .offset(
                    x: geo.size.width - pipSize.width - 60,
                    y: geo.size.height - pipSize.height - 60
                )
                .zIndex(2)

                // Main channel name label
                Text(pair[mainIdx].name)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(.black.opacity(0.65), in: .capsule)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.horizontal, 60).padding(.bottom, 60)
                    .zIndex(3)
            }
        }
        .ignoresSafeArea()
        #if os(tvOS)
        .onExitCommand { onExit() }
        #endif
    }

    private func statusBinding(_ i: Int) -> Binding<PlayerStatus> {
        Binding(get: { statuses[i] }, set: { statuses[i] = $0 })
    }

    private func errorBinding(_ i: Int) -> Binding<String?> {
        Binding(get: { errorTexts[i] }, set: { errorTexts[i] = $0 })
    }

    private func swapChannels() {
        mainIdx = 1 - mainIdx
    }
}
