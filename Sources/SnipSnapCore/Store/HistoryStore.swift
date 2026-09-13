import Foundation
import Combine

/// New content handed to the store. The store owns all hashing, dedup and
/// file layout so callers (and tests) don't have to know where things land.
enum SnipSnapContent {
    case text(String)
    /// `png` is already PNG-encoded; dimensions are the full-image pixel size.
    case image(png: Data, pixelWidth: Int, pixelHeight: Int)
}

/// The single source of truth for clipboard history: an ordered, deduped,
/// size-bounded list of `ClipItem`, persisted under Application Support.
///
/// Ordering is pinned-first (newest first within each group). Pinned items
/// are never trimmed — that is the entire point of pinning.
final class HistoryStore: ObservableObject {

    @Published private(set) var items: [ClipItem] = []

    /// Maximum number of *unpinned* items to retain. Pinned items are exempt.
    var maxUnpinned: Int

    /// Longest edge of generated previews, in pixels. Sized so a wide
    /// screenshot rendered full-width in the panel (~348pt content width on
    /// a default-sized panel, 2x for Retina, plus headroom for a widened
    /// panel) stays sharp rather than being upscaled from a small thumbnail.
    var thumbnailPixelSize = 768

    private let baseURL: URL
    private let imagesDir: URL
    private let textDir: URL
    private let indexURL: URL
    private let fm = FileManager.default

    private var pendingSave: DispatchWorkItem?
    /// Debounce window for coalescing a burst of copies into one disk write.
    var saveDebounce: TimeInterval = 1.0

    // MARK: - Lifecycle

    /// - Parameter baseURL: root directory for state. Defaults to
    ///   `~/Library/Application Support/SnipSnap`. Tests pass a temp dir.
    init(baseURL: URL? = nil, maxUnpinned: Int = 200) {
        self.maxUnpinned = maxUnpinned
        self.baseURL = baseURL ?? Self.defaultBaseURL()
        self.imagesDir = self.baseURL.appendingPathComponent("images", isDirectory: true)
        self.textDir = self.baseURL.appendingPathComponent("text", isDirectory: true)
        self.indexURL = self.baseURL.appendingPathComponent("index.json")
        createDirectories()
        load()
    }

    static func defaultBaseURL() -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return root.appendingPathComponent("SnipSnap", isDirectory: true)
    }

    private func createDirectories() {
        for dir in [baseURL, imagesDir, textDir] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Mutation

    /// Record new clipboard content. Returns the resulting item, or nil when
    /// the content was empty and skipped.
    @discardableResult
    func add(_ content: SnipSnapContent) -> ClipItem? {
        switch content {
        case .text(let raw):
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let hash = ClipItem.hash(raw)
            if promoteExisting(hash: hash) { return items.first { $0.contentHash == hash } }

            let bytes = raw.utf8.count
            let item = ClipItem(
                kind: .text,
                contentHash: hash,
                text: bytes <= ClipItem.inlineTextByteLimit ? raw : nil,
                byteSize: bytes
            )
            if item.text == nil {
                try? Data(raw.utf8).write(to: textURL(item.id), options: .atomic)
            }
            insert(item)
            return item

        case .image(let png, let w, let h):
            guard !png.isEmpty else { return nil }
            let hash = ClipItem.hash(png)
            if promoteExisting(hash: hash) { return items.first { $0.contentHash == hash } }

            let id = UUID()
            let imageName = "\(id.uuidString).png"
            let thumbName = "\(id.uuidString)_thumb.png"
            do {
                try png.write(to: imagesDir.appendingPathComponent(imageName), options: .atomic)
            } catch {
                return nil
            }
            // No point storing a second near-identical copy of an image
            // that's already at or under the preview target — `imageFile`
            // serves directly (thumbnailURL(for:) falls back to it below).
            if max(w, h) > thumbnailPixelSize,
               let thumb = ImageUtil.thumbnailPNG(from: png, maxPixel: thumbnailPixelSize) {
                try? thumb.write(to: imagesDir.appendingPathComponent(thumbName), options: .atomic)
            }
            let item = ClipItem(
                id: id,
                kind: .image,
                contentHash: hash,
                imageFile: imageName,
                thumbFile: fm.fileExists(atPath: imagesDir.appendingPathComponent(thumbName).path) ? thumbName : nil,
                pixelWidth: w,
                pixelHeight: h,
                byteSize: png.count
            )
            insert(item)
            return item
        }
    }

    func togglePin(id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].pinned.toggle()
        resort()
        trim()
        scheduleSave()
    }

    func clearAll() {
        for item in items { deleteSidecars(item) }
        items.removeAll()
        scheduleSave()
    }

    // MARK: - Content resolution

    /// The full text for an item, whether stored inline or in a sidecar.
    func resolveText(for item: ClipItem) -> String? {
        if let inline = item.text { return inline }
        guard item.kind == .text else { return nil }
        return (try? Data(contentsOf: textURL(item.id))).flatMap { String(data: $0, encoding: .utf8) }
    }

    func fullImageData(for item: ClipItem) -> Data? {
        guard let name = item.imageFile else { return nil }
        return try? Data(contentsOf: imagesDir.appendingPathComponent(name))
    }

    func thumbnailURL(for item: ClipItem) -> URL? {
        guard let name = item.thumbFile ?? item.imageFile else { return nil }
        return imagesDir.appendingPathComponent(name)
    }

    // MARK: - Persistence

    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        do {
            let encoder = JSONEncoder()
            // Default (.deferredToDate) keeps full sub-second precision, so
            // item ordering survives a save/reload; .iso8601 would truncate
            // to whole seconds and make same-second items sort unstably.
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(items)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            NSLog("SnipSnap: failed to write index: \(error)")
        }
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + saveDebounce, execute: work)
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        let decoder = JSONDecoder()
        guard let decoded = try? decoder.decode([ClipItem].self, from: data) else {
            NSLog("SnipSnap: index.json unreadable, starting empty")
            return
        }
        // Self-heal: drop entries whose backing files vanished.
        items = decoded.filter { sidecarsPresent($0) }
        migrateUndersizedThumbnails()
        resort()
        trim()
    }

    /// Regenerates any on-disk preview image that's smaller than the
    /// current target size — covers items whose preview was generated
    /// before `thumbnailPixelSize` was raised. Reads only image headers (no
    /// full decode) to decide, so this is cheap even for a couple hundred
    /// items, and self-corrects again if the target ever changes.
    private func migrateUndersizedThumbnails() {
        for item in items {
            guard item.kind == .image, let thumbName = item.thumbFile else { continue }
            let thumbURL = imagesDir.appendingPathComponent(thumbName)
            guard let thumbData = try? Data(contentsOf: thumbURL),
                  let thumbSize = ImageUtil.pixelSize(of: thumbData)
            else { continue }

            let fullLongEdge = max(item.pixelWidth ?? 0, item.pixelHeight ?? 0)
            let target = min(thumbnailPixelSize, fullLongEdge)
            guard max(thumbSize.width, thumbSize.height) < target else { continue }

            guard let fullData = fullImageData(for: item),
                  let regenerated = ImageUtil.thumbnailPNG(from: fullData, maxPixel: thumbnailPixelSize)
            else { continue }
            try? regenerated.write(to: thumbURL, options: .atomic)
        }
    }

    // MARK: - Internals

    private func promoteExisting(hash: String) -> Bool {
        guard let idx = items.firstIndex(where: { $0.contentHash == hash }) else { return false }
        items[idx].createdAt = Date()
        resort()
        scheduleSave()
        return true
    }

    private func insert(_ item: ClipItem) {
        items.append(item)
        resort()
        trim()
        scheduleSave()
    }

    private func resort() {
        items.sort { a, b in
            if a.pinned != b.pinned { return a.pinned && !b.pinned }
            return a.createdAt > b.createdAt
        }
    }

    private func trim() {
        var unpinnedSeen = 0
        var survivors: [ClipItem] = []
        var doomed: [ClipItem] = []
        for item in items {
            if item.pinned {
                survivors.append(item)
                continue
            }
            unpinnedSeen += 1
            if unpinnedSeen <= maxUnpinned {
                survivors.append(item)
            } else {
                doomed.append(item)
            }
        }
        guard !doomed.isEmpty else { return }
        for item in doomed { deleteSidecars(item) }
        items = survivors
    }

    private func sidecarsPresent(_ item: ClipItem) -> Bool {
        switch item.kind {
        case .text:
            if item.text != nil { return true }
            return fm.fileExists(atPath: textURL(item.id).path)
        case .image:
            guard let name = item.imageFile else { return false }
            return fm.fileExists(atPath: imagesDir.appendingPathComponent(name).path)
        }
    }

    private func deleteSidecars(_ item: ClipItem) {
        if item.kind == .text, item.text == nil {
            try? fm.removeItem(at: textURL(item.id))
        }
        if item.kind == .image {
            if let n = item.imageFile { try? fm.removeItem(at: imagesDir.appendingPathComponent(n)) }
            if let n = item.thumbFile { try? fm.removeItem(at: imagesDir.appendingPathComponent(n)) }
        }
    }

    private func textURL(_ id: UUID) -> URL {
        textDir.appendingPathComponent("\(id.uuidString).txt")
    }
}
