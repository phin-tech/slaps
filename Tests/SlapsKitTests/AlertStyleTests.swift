import CoreGraphics
import Testing
@testable import SlapsKit

// A 1710×1112 laptop screen with a 37-pt menu bar and a 70-pt Dock, and a second screen to its left.
private let screen = CGRect(x: 0, y: 0, width: 1710, height: 1112)
private let visible = CGRect(x: 0, y: 70, width: 1710, height: 1005)

@Test func fullScreenIsTheWholeScreen() {
    #expect(AlertStyle.fullScreen.frame(screen: screen, visible: visible) == screen)
}

@Test func topBannerIsAFifthUnderTheMenuBar() {
    let f = AlertStyle.top.frame(screen: screen, visible: visible)
    #expect(f.height == 222)
    #expect(f.maxY == visible.maxY)
    #expect(f.minX == 0 && f.width == 1710)
}

@Test func bottomBannerIsAFifthAtTheBottomEdge() {
    let f = AlertStyle.bottom.frame(screen: screen, visible: visible)
    #expect(f == CGRect(x: 0, y: 0, width: 1710, height: 222))
}

@Test func sideCardIsInTheTopRightUnderTheMenuBar() {
    let f = AlertStyle.side.frame(screen: screen, visible: visible)
    #expect(f.size == AlertStyle.cardSize)
    #expect(f.maxX == visible.maxX - AlertStyle.cardMargin)
    #expect(f.maxY == visible.maxY - AlertStyle.cardMargin)
    #expect(!AlertStyle.side.takesKeyboard && !AlertStyle.side.onEveryScreen && !AlertStyle.side.isBanner)
    #expect(AlertStyle(external: "side") == .side)
}

@Test func bannersKeepAMinimumHeightAndFollowTheScreen() {
    let small = CGRect(x: -1280, y: 200, width: 1280, height: 720)
    let f = AlertStyle.top.frame(screen: small, visible: small)
    #expect(f.height == AlertStyle.bannerMinHeight)
    #expect(f.minX == -1280 && f.maxY == small.maxY)
}
