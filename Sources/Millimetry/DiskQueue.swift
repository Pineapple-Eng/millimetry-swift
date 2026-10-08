import Foundation

/// The outbound queue on disk, under `Application Support/Millimetry/queue/`:
///
/// - `open.jsonl` — events as they are tracked, one JSON line each, appended.
/// - `batch-<seq>.json` — formed batches, each with its `batchID`, sent oldest first.
/// - `sealing-<id>.jsonl` — `open.jsonl` mid-way through being cut into batches.
///
/// Cutting batches is crash-safe: `open.jsonl` is first renamed (atomic), the batches are written
/// tagged with that sealing file's id, then the sealing file is deleted. A sealing file found at
/// launch means the cut was interrupted: its batches are discarded and it is cut again, so no
/// event is lost and none is queued twice.
///
/// Limits: at most `maxQueuedEvents` (the oldest are dropped) and nothing older than
/// `maxEventAge`. The directory is excluded from backups and its files use
/// `completeUntilFirstUserAuthentication` protection.
struct DiskQueue {
    let directory: URL
    let limits: Limits

    private var openURL: URL { directory.appendingPathComponent("open.jsonl") }
    private(set) var openCount = 0
    private(set) var batchedCount = 0
    private var nextSequence = 1

    var count: Int { openCount + batchedCount }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    /// Opens (creating if needed) the queue in `directory` and recovers from an interrupted cut.
    init(directory: URL, limits: Limits) throws {
        self.directory = directory
        self.limits = limits
        try DiskQueue.prepare(directory)
        for sealing in try files(prefix: "sealing-") {
            try recover(sealing: sealing)
        }
        openCount = try readOpenEvents().count
        // A batch file that does not decode (a write cut short) would block the queue forever.
        for url in try batchFiles() where try readBatch(url) == nil {
            try FileManager.default.removeItem(at: url)
        }
        let batches = try batchFiles()
        nextSequence = (batches.compactMap { DiskQueue.sequence(of: $0) }.max() ?? 0) + 1
        batchedCount = try batches.reduce(0) { $0 + (try readBatch($1)?.events.count ?? 0) }
    }

    /// The default location: `Application Support/Millimetry/queue/`.
    static func defaultDirectory() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return support.appendingPathComponent("Millimetry", isDirectory: true)
            .appendingPathComponent("queue", isDirectory: true)
    }

    // MARK: Appending

    /// Appends an event, then enforces the size limit.
    mutating func append(_ event: QueuedEvent) throws {
        var line = try DiskQueue.encoder.encode(event)
        line.append(0x0A)
        if FileManager.default.fileExists(atPath: openURL.path) {
            let handle = try FileHandle(forWritingTo: openURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: openURL, options: DiskQueue.writeOptions)
        }
        openCount += 1
        if count > limits.maxQueuedEvents {
            try dropOldest(count - limits.maxQueuedEvents)
        }
    }

    // MARK: Forming batches

    /// Cuts every open event into batches: one system per batch, at most `maxBatchEvents` events
    /// and `maxBatchBytes` of JSON each. Events older than the age limit are dropped.
    mutating func seal(now: Date) throws {
        guard openCount > 0, FileManager.default.fileExists(atPath: openURL.path) else { return }
        let sealingID = UUID().uuidString.lowercased()
        let sealingURL = directory.appendingPathComponent("sealing-\(sealingID).jsonl")
        try FileManager.default.moveItem(at: openURL, to: sealingURL)
        openCount = 0
        try cut(sealingURL: sealingURL, sealingID: sealingID, now: now)
    }

    private mutating func cut(sealingURL: URL, sealingID: String, now: Date) throws {
        let events = try DiskQueue.readLines(sealingURL).filter { !isTooOld($0, now: now) }
        var batch: [QueuedEvent] = []
        var batchBytes = 0
        func flushBatch() throws {
            guard let first = batch.first else { return }
            try writeNewBatch(StoredBatch(batchID: UUID(), system: first.system, events: batch, source: sealingID))
            batch = []
            batchBytes = 0
        }
        for event in events {
            let size = WirePayload.encodedSize(of: event) + 1
            let systemChanged = batch.first.map { $0.system != event.system } ?? false
            if systemChanged || batch.count >= limits.maxBatchEvents
                || (!batch.isEmpty && batchBytes + size > limits.maxBatchBytes) {
                try flushBatch()
            }
            batch.append(event)
            batchBytes += size
        }
        try flushBatch()
        try FileManager.default.removeItem(at: sealingURL)
    }

    /// Discards batches an interrupted cut left behind, then cuts the sealing file again.
    private mutating func recover(sealing url: URL) throws {
        let name = url.deletingPathExtension().lastPathComponent
        let sealingID = String(name.dropFirst("sealing-".count))
        for batchURL in try batchFiles() {
            if let batch = try readBatch(batchURL), batch.source == sealingID {
                try FileManager.default.removeItem(at: batchURL)
            }
        }
        let existing = try batchFiles().compactMap { DiskQueue.sequence(of: $0) }.max() ?? 0
        nextSequence = max(nextSequence, existing + 1)
        try cut(sealingURL: url, sealingID: sealingID, now: Date())
    }

    // MARK: Reading and changing batches

    /// The oldest formed batch, with its file.
    func oldestBatch() throws -> (url: URL, batch: StoredBatch)? {
        for url in try batchFiles() {
            if let batch = try readBatch(url) {
                return (url, batch)
            }
        }
        return nil
    }

    /// Rewrites a batch in place: same file, same `batchID` (used when events are removed from it).
    mutating func replace(_ url: URL, with batch: StoredBatch) throws {
        let before = try readBatch(url)?.events.count ?? 0
        if batch.events.isEmpty {
            try remove(url)
            return
        }
        try DiskQueue.encoder.encode(batch).write(to: url, options: DiskQueue.writeOptions)
        batchedCount += batch.events.count - before
    }

    /// Deletes a delivered or rejected batch.
    mutating func remove(_ url: URL) throws {
        let events = try readBatch(url)?.events.count ?? 0
        try FileManager.default.removeItem(at: url)
        batchedCount -= events
    }

    /// Replaces a batch the server refused as too large (413) with its two halves, in its place
    /// in the order. The halves get new ids: the server stored nothing for the original. The batch
    /// is read back from its file, since the size limit may have trimmed it while the request was
    /// out; a batch already gone or down to one event is simply removed.
    mutating func split(_ url: URL) throws {
        guard let batch = try readBatch(url) else { return }
        guard batch.events.count > 1 else {
            try remove(url)
            return
        }
        let middle = batch.events.count / 2
        let stem = url.deletingPathExtension().lastPathComponent
        let halves = [Array(batch.events[..<middle]), Array(batch.events[middle...])]
        for (suffix, events) in zip(["a", "b"], halves) {
            let half = StoredBatch(batchID: UUID(), system: batch.system, events: events, source: batch.source)
            let halfURL = directory.appendingPathComponent("\(stem)\(suffix).json")
            try DiskQueue.encoder.encode(half).write(to: halfURL, options: DiskQueue.writeOptions)
        }
        try FileManager.default.removeItem(at: url)
    }

    /// Deletes everything (opt-out).
    mutating func removeAll() throws {
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            try FileManager.default.removeItem(at: url)
        }
        openCount = 0
        batchedCount = 0
    }

    func isTooOld(_ event: QueuedEvent, now: Date) -> Bool {
        now.timeIntervalSince(event.date) > limits.maxEventAge
    }

    // MARK: Dropping the oldest

    private mutating func dropOldest(_ excess: Int) throws {
        var remaining = excess
        while remaining > 0, let (url, batch) = try oldestBatch() {
            let removed = min(remaining, batch.events.count)
            var trimmed = batch
            trimmed.events.removeFirst(removed)
            try replace(url, with: trimmed)
            remaining -= removed
        }
        guard remaining > 0 else { return }
        let kept = Array(try readOpenEvents().dropFirst(remaining))
        try writeOpen(kept)
    }

    // MARK: Files

    private static var writeOptions: Data.WritingOptions {
        #if os(macOS)
        return [.atomic]
        #else
        return [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        #endif
    }

    private static func prepare(_ directory: URL) throws {
        let fileManager = FileManager.default
        #if os(macOS)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        #else
        try fileManager.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        #endif
        // Exclude the SDK's whole folder (the queue's parent) from iCloud and device backups.
        var parent = directory.deletingLastPathComponent()
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try parent.setResourceValues(values)
    }

    private func files(prefix: String) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(prefix) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func batchFiles() throws -> [URL] {
        try files(prefix: "batch-").filter { $0.pathExtension == "json" }
    }

    /// `batch-0000000012ab.json` → 12.
    private static func sequence(of url: URL) -> Int? {
        let stem = url.deletingPathExtension().lastPathComponent.dropFirst("batch-".count)
        return Int(stem.prefix { $0.isNumber })
    }

    private mutating func writeNewBatch(_ batch: StoredBatch) throws {
        let name = "batch-" + String(repeating: "0", count: max(0, 10 - String(nextSequence).count)) + "\(nextSequence).json"
        nextSequence += 1
        try DiskQueue.encoder.encode(batch).write(to: directory.appendingPathComponent(name), options: DiskQueue.writeOptions)
        batchedCount += batch.events.count
    }

    private func readBatch(_ url: URL) throws -> StoredBatch? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(StoredBatch.self, from: data)
    }

    private func readOpenEvents() throws -> [QueuedEvent] {
        guard FileManager.default.fileExists(atPath: openURL.path) else { return [] }
        return try DiskQueue.readLines(openURL)
    }

    private mutating func writeOpen(_ events: [QueuedEvent]) throws {
        var data = Data()
        for event in events {
            data.append(try DiskQueue.encoder.encode(event))
            data.append(0x0A)
        }
        try data.write(to: openURL, options: DiskQueue.writeOptions)
        openCount = events.count
    }

    /// Reads JSON lines, skipping any line that does not decode (a write cut short by a crash).
    private static func readLines(_ url: URL) throws -> [QueuedEvent] {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return data.split(separator: 0x0A).compactMap { try? decoder.decode(QueuedEvent.self, from: Data($0)) }
    }
}
