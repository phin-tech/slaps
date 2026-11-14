import Foundation

/// An sRGB colour, for the custom theme: kept in the settings as hex, and the maths of what reads on it.
public struct ThemeColor: Equatable, Sendable {
    public var red: Double, green: Double, blue: Double

    public init(red: Double, green: Double, blue: Double) {
        func clamp(_ v: Double) -> Double { min(1, max(0, v)) }
        self.red = clamp(red)
        self.green = clamp(green)
        self.blue = clamp(blue)
    }

    /// "#1A2B3C" or "1a2b3c".
    public init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(red: Double(v >> 16 & 0xFF) / 255, green: Double(v >> 8 & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    public var hex: String {
        String(format: "#%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }

    /// WCAG's relative luminance: 0 for black, 1 for white.
    public var luminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG's contrast ratio with another colour, from 1 to 21.
    public func contrast(with other: ThemeColor) -> Double {
        let (a, b) = (luminance, other.luminance)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    public static let white = ThemeColor(red: 1, green: 1, blue: 1)
    public static let ink = ThemeColor(red: 0.1, green: 0.1, blue: 0.1)

    /// White, if it reaches WCAG's 3:1 for large text (an alert's text is large), as on saturated colours where it
    /// looks right even when near-black measures higher; otherwise near-black, on light colours.
    public var readableText: ThemeColor { contrast(with: .white) >= 3 ? .white : .ink }

    /// Mixed with black, for the far end of the background's gradient.
    public func darkened(_ amount: Double) -> ThemeColor {
        ThemeColor(red: red * (1 - amount), green: green * (1 - amount), blue: blue * (1 - amount))
    }
}

/// Kept as its hex, as the settings keep it.
extension ThemeColor: Codable {
    public init(from decoder: Decoder) throws {
        let hex = try decoder.singleValueContainer().decode(String.self)
        guard let color = ThemeColor(hex: hex) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not a hex colour"))
        }
        self = color
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(hex)
    }
}

extension ThemeColor: Hashable {}
