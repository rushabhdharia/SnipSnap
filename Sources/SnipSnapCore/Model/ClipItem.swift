import Foundation
import CryptoKit

/// The two kinds of clipboard content this app records.
enum ClipKind: String, Codable {
    case text
    case image
}

/// One entry in the clipboard history.
///
/// Text small enough to be cheap is stored inline in `text`; anything larger
/// is spilled to a sidecar file and `text` is left nil. Images are always
/// stored as sidecar PNGs, with a small pre-rendered thumbnail alongside so
/// the history list never has to decode full screenshots while scrolling.
struct ClipItem: Identifiable, Codable, Equatable {
    /// Text at or below this size is kept inline in the index; larger text
    /// goes to `text/<id>.txt`.
    static let inlineTextByteLimit = 8 * 1024

    let id: UUID
    let kind: ClipKind
    var createdAt: Date
    var pinned: Bool
    /// SHA-256 of the raw content, used to collapse duplicate copies.
    let contentHash: String

    // Text payload -------------------------------------------------------
    var text: String?

    // Image payload ----------------------------------------------------
    var imageFile: String?
    var thumbFile: String?
    var pixelWidth: Int?
    var pixelHeight: Int?

    /// Size of the underlying content in bytes (inline or on disk).
    var byteSize: Int

    init(
        id: UUID = UUID(),
        kind: ClipKind,
        createdAt: Date = Date(),
        pinned: Bool = false,
        contentHash: String,
        text: String? = nil,
        imageFile: String? = nil,
        thumbFile: String? = nil,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        byteSize: Int
    ) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
        self.pinned = pinned
        self.contentHash = contentHash
        self.text = text
        self.imageFile = imageFile
        self.thumbFile = thumbFile
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.byteSize = byteSize
    }

    /// True when the text payload lives in a sidecar file rather than inline.
    var textIsExternal: Bool { kind == .text && text == nil }

    /// One-line-ish label for a row. For text this is the content with
    /// interior runs of whitespace collapsed; for images a dimension string.
    var preview: String {
        switch kind {
        case .text:
            guard let text else { return "Large text (\(Self.humanSize(byteSize)))" }
            let collapsed = text
                .replacingOccurrences(of: "\r\n", with: "\n")
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            return collapsed.isEmpty ? text : collapsed
        case .image:
            if let w = pixelWidth, let h = pixelHeight {
                return "Image \(w) × \(h)"
            }
            return "Image"
        }
    }

    var detail: String {
        switch kind {
        case .text:
            return "\(byteSize == 1 ? "1 byte" : "\(Self.humanSize(byteSize))")"
        case .image:
            return Self.humanSize(byteSize)
        }
    }

    static func humanSize(_ bytes: Int) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: Int64(bytes))
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func hash(_ string: String) -> String {
        hash(Data(string.utf8))
    }
}
