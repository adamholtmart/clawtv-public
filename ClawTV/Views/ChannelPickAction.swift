import SwiftUI

struct ChannelPickAction {
    let handler: (Channel) -> Void
    func callAsFunction(_ channel: Channel) { handler(channel) }
}

private struct ChannelPickActionKey: EnvironmentKey {
    static let defaultValue: ChannelPickAction? = nil
}

extension EnvironmentValues {
    var channelPickAction: ChannelPickAction? {
        get { self[ChannelPickActionKey.self] }
        set { self[ChannelPickActionKey.self] = newValue }
    }
}
