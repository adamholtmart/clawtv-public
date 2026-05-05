import SwiftUI

/// Platform-specific layout constants shared across all views.
enum Layout {
    #if os(tvOS)
    static let hPad: CGFloat = 60
    static let vPad: CGFloat = 40
    static let cardColumns    = Array(repeating: GridItem(.fixed(260), spacing: 32), count: 5)
    static let categoryColumns = Array(repeating: GridItem(.fixed(380), spacing: 24), count: 4)
    static let cardHSpacing: CGFloat = 32
    #else
    static let hPad: CGFloat = 20
    static let vPad: CGFloat = 20
    static let cardColumns    = [GridItem(.adaptive(minimum: 150), spacing: 16)]
    static let categoryColumns = [GridItem(.adaptive(minimum: 160), spacing: 12)]
    static let cardHSpacing: CGFloat = 16
    #endif
}
