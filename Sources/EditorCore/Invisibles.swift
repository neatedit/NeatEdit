import Foundation

/// The marks drawn over whitespace when invisibles are shown.
public enum Invisibles {
    public static let lineEnd = "¬"

    /// Nil for characters that are drawn as themselves. Line breaks are
    /// marked separately, once per line end (CRLF is one).
    public static func symbol(for character: unichar) -> String? {
        switch character {
        case 0x20: "·"
        case 0x09: "→"
        case 0xA0: "°"  // no-break space, the one that bites
        case 0x3000: "□"  // ideographic space
        default: nil
        }
    }
}
