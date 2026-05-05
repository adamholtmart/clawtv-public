import SwiftUI

/// Cross-platform replacement for `.card` (tvOS-only).
/// On tvOS: delegates to the system `.card` style.
/// On iOS: subtle press-scale with a highlight overlay.
struct ChannelCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .brightness(configuration.isPressed ? 0.06 : 0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == ChannelCardButtonStyle {
    static var channelCard: ChannelCardButtonStyle { ChannelCardButtonStyle() }
}
