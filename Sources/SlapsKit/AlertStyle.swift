import CoreGraphics

/// How much of the screen an alert takes.
public enum AlertStyle: String, CaseIterable, Identifiable, Sendable {
    /// Every screen, all of it: hard to miss, and it takes the keyboard.
    case fullScreen
    /// A band across the top, below the menu bar; the rest of the screen stays usable.
    case top
    /// A band across the bottom.
    case bottom

    public var id: Self { self }

    public var name: String {
        switch self {
        case .fullScreen: "Full screen"
        case .top: "Banner at the top"
        case .bottom: "Banner at the bottom"
        }
    }

    public var isBanner: Bool { self != .fullScreen }

    /// The share of the screen's height a banner takes.
    public static let bannerShare: CGFloat = 0.2
    /// Enough for a title, a line of details and the buttons, on a small screen.
    public static let bannerMinHeight: CGFloat = 170

    /// The alert's frame on a screen whose whole frame is `screen` and whose `visible` frame leaves out the menu bar
    /// and Dock (AppKit coordinates, origin bottom-left). The top banner sits under the menu bar; the bottom one at
    /// the screen's edge, over the Dock.
    public func frame(screen: CGRect, visible: CGRect) -> CGRect {
        let height = min(screen.height, max(Self.bannerMinHeight, (screen.height * Self.bannerShare).rounded()))
        switch self {
        case .fullScreen:
            return screen
        case .top:
            return CGRect(x: screen.minX, y: visible.maxY - height, width: screen.width, height: height)
        case .bottom:
            return CGRect(x: screen.minX, y: screen.minY, width: screen.width, height: height)
        }
    }
}
