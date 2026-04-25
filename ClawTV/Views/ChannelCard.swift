import SwiftUI

struct ChannelCard: View {
    let channel: Channel
    @EnvironmentObject var epg: EPGService
    @EnvironmentObject var store: PlaylistStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(
                        colors: [Color(white: 0.15), Color(white: 0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))

                if let logoURL = channel.logoURL {
                    AsyncImage(url: logoURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .padding(18)
                        case .failure, .empty:
                            fallbackIcon
                        @unknown default:
                            fallbackIcon
                        }
                    }
                } else {
                    fallbackIcon
                }

                if store.isFavorite(channel) {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                        .padding(6)
                        .background(.black.opacity(0.55), in: .circle)
                        .padding(6)
                }
            }
            .frame(width: 260, height: 146)

            VStack(alignment: .leading, spacing: 2) {
                Text(channel.name)
                    .font(.system(size: 18, weight: .semibold))
                    .lineLimit(1)

                if let live = epg.currentProgramme(for: channel) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 5, height: 5)
                        Text(live.title)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } else {
                    Text(channel.groupTitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 260, alignment: .leading)
        }
    }

    private var fallbackIcon: some View {
        VStack(spacing: 6) {
            Image(systemName: "tv.fill")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text(channel.name.prefix(2).uppercased())
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}
