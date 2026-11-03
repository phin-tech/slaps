import Testing
@testable import SlapsKit

@Test func hexRoundTrips() {
    #expect(ThemeColor(hex: "#1A2B3C")?.hex == "#1A2B3C")
    #expect(ThemeColor(hex: "ff8000") == ThemeColor(red: 1, green: 128.0 / 255, blue: 0))
    #expect(ThemeColor(hex: "#12345") == nil)
    #expect(ThemeColor(hex: "zzzzzz") == nil)
}

@Test func textReadsOnTheBackground() {
    #expect(ThemeColor(hex: "#0D1233")!.readableText == .white)    // the Midnight blue
    #expect(ThemeColor(hex: "#F7F7F7")!.readableText == .ink)      // paper
    #expect(ThemeColor(hex: "#FFD60A")!.readableText == .ink)      // bright yellow
    #expect(ThemeColor(hex: "#E5484D")!.readableText == .white)    // red
}

@Test func contrastAndDarkening() {
    #expect(abs(ThemeColor.white.contrast(with: ThemeColor(red: 0, green: 0, blue: 0)) - 21) < 0.01)
    #expect(ThemeColor(hex: "#808080")!.darkened(0.5).hex == "#404040")
    #expect(ThemeColor(red: 2, green: -1, blue: 0.5).red == 1)
}
