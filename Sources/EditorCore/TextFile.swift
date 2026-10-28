import Foundation

/// Decoded file contents plus what's needed to write them back unchanged.
public struct TextFile: Sendable {
    public var text: String
    public var encoding: String.Encoding
    public var hasBOM: Bool

    public enum DecodingError: Error {
        case unsupportedEncoding
    }

    public init(text: String, encoding: String.Encoding = .utf8, hasBOM: Bool = false) {
        self.text = text
        self.encoding = encoding
        self.hasBOM = hasBOM
    }

    /// BOM first, then strict UTF-8, then the legacy encodings people
    /// actually hit (Cyrillic Windows, then Latin-1 which never fails).
    public init(data: Data) throws {
        for (bom, encoding) in Self.boms where data.starts(with: bom) {
            guard let text = String(data: data.dropFirst(bom.count), encoding: encoding) else {
                throw DecodingError.unsupportedEncoding
            }
            self.init(text: text, encoding: encoding, hasBOM: true)
            return
        }
        if let text = String(data: data, encoding: .utf8) {
            self.init(text: text)
            return
        }
        for encoding in [String.Encoding.windowsCP1251, .isoLatin1] {
            if let text = String(data: data, encoding: encoding) {
                self.init(text: text, encoding: encoding)
                return
            }
        }
        throw DecodingError.unsupportedEncoding
    }

    /// Decodes exactly as `encoding` (a matching BOM is stripped and kept).
    public init(data: Data, encoding: String.Encoding) throws {
        let bom = Self.boms.first { $0.1 == encoding && data.starts(with: $0.0) }?.0
        guard let text = String(data: data.dropFirst(bom?.count ?? 0), encoding: encoding) else {
            throw DecodingError.unsupportedEncoding
        }
        self.init(text: text, encoding: encoding, hasBOM: bom != nil)
    }

    public static let koi8U = cfEncoding(.KOI8_U)
    public static let koi8R = cfEncoding(.KOI8_R)

    /// What the status bar menu offers, in menu order.
    public static let choices: [String.Encoding] = [
        .utf8, .utf16LittleEndian, .utf16BigEndian, .windowsCP1251, koi8U, koi8R,
        .isoLatin1, .windowsCP1252, .macOSRoman,
    ]

    /// Short name for the status bar ("UTF-8", "Windows-1251", "UTF-16 LE BOM").
    public var encodingName: String {
        let base = Self.name(of: encoding)
        return hasBOM && encoding == .utf8 ? base + " BOM" : base
    }

    public static func name(of encoding: String.Encoding) -> String {
        switch encoding {
        case .utf8: "UTF-8"
        case .utf16LittleEndian: "UTF-16 LE"
        case .utf16BigEndian: "UTF-16 BE"
        case .utf32LittleEndian: "UTF-32 LE"
        case .utf32BigEndian: "UTF-32 BE"
        case .windowsCP1251: "Windows-1251"
        case koi8U: "KOI8-U"
        case koi8R: "KOI8-R"
        case .isoLatin1: "ISO-8859-1"
        case .windowsCP1252: "Windows-1252"
        case .macOSRoman: "Mac Roman"
        default: String.localizedName(of: encoding)
        }
    }

    public func canEncode(as encoding: String.Encoding) -> Bool {
        text.canBeConverted(to: encoding)
    }

    private static func cfEncoding(_ encoding: CFStringEncodings) -> String.Encoding {
        String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(encoding.rawValue)))
    }

    public func encoded() -> Data? {
        guard let body = text.data(using: encoding) else { return nil }
        guard hasBOM, let bom = Self.boms.first(where: { $0.1 == encoding })?.0 else { return body }
        return Data(bom) + body
    }

    // UTF-32 BOMs must be checked before UTF-16 (FF FE is a prefix of FF FE 00 00).
    private static let boms: [([UInt8], String.Encoding)] = [
        ([0xEF, 0xBB, 0xBF], .utf8),
        ([0x00, 0x00, 0xFE, 0xFF], .utf32BigEndian),
        ([0xFF, 0xFE, 0x00, 0x00], .utf32LittleEndian),
        ([0xFE, 0xFF], .utf16BigEndian),
        ([0xFF, 0xFE], .utf16LittleEndian),
    ]
}

public enum LineEnding: String, CaseIterable, Sendable {
    case lf = "LF"
    case crlf = "CRLF"
    case cr = "CR"

    public var string: String {
        switch self {
        case .lf: "\n"
        case .crlf: "\r\n"
        case .cr: "\r"
        }
    }

    /// The first line break wins; documents without breaks default to LF.
    public static func detect(in text: String) -> LineEnding {
        var previousWasCR = false
        for byte in text.utf8 {
            if byte == 0x0A { return previousWasCR ? .crlf : .lf }
            if previousWasCR { return .cr }
            previousWasCR = byte == 0x0D
        }
        return previousWasCR ? .cr : .lf
    }

    public func apply(to text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return self == .lf ? normalized : normalized.replacingOccurrences(of: "\n", with: string)
    }
}

public struct TextStats: Equatable, Sendable {
    public var characters: Int
    public var lines: Int

    public init(text: String) {
        characters = text.count
        lines = LineIndex(text as NSString).lineCount
    }
}
