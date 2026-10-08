import Foundation
import Testing
@testable import Millimetry

struct DiskQueueTests {
    let now = Date(timeIntervalSince1970: 1_791_000_000)
    let session = UUID()

    private func event(_ name: String, at date: Date? = nil, system: SystemInfo = testSystem, padding: Int = 0) -> QueuedEvent {
        QueuedEvent(
            name: name,
            timestamp: Int64(((date ?? now).timeIntervalSince1970 * 1_000).rounded()),
            sessionID: session,
            properties: padding > 0 ? ["note": .string(String(repeating: "x", count: padding))] : [:],
            system: system
        )
    }

    private func allBatches(_ queue: inout DiskQueue) throws -> [StoredBatch] {
        var batches: [StoredBatch] = []
        while let (url, batch) = try queue.oldestBatch() {
            batches.append(batch)
            try queue.remove(url)
        }
        return batches
    }

    @Test func appendedEventsSurviveReopeningTheQueue() throws {
        let directory = temporaryQueueDirectory()
        var queue = try DiskQueue(directory: directory, limits: Limits())
        for index in 0..<5 { try queue.append(event("e\(index)")) }
        let reopened = try DiskQueue(directory: directory, limits: Limits())
        #expect(reopened.count == 5)
        #expect(reopened.openCount == 5)
    }

    @Test func sealingCutsBatchesOfAtMostOneHundredEvents() throws {
        var queue = try DiskQueue(directory: temporaryQueueDirectory(), limits: Limits())
        for index in 0..<250 { try queue.append(event("e\(index)")) }
        try queue.seal(now: now)
        let batches = try allBatches(&queue)
        #expect(batches.map(\.events.count) == [100, 100, 50])
        #expect(batches.flatMap(\.events).map(\.name) == (0..<250).map { "e\($0)" }, "order is kept")
        #expect(Set(batches.map(\.batchID)).count == 3)
    }

    @Test func sealingKeepsEachBatchUnderTheByteLimit() throws {
        var queue = try DiskQueue(directory: temporaryQueueDirectory(), limits: Limits())
        for index in 0..<40 { try queue.append(event("e\(index)", padding: 10_000)) }
        try queue.seal(now: now)
        let batches = try allBatches(&queue)
        #expect(batches.count > 1)
        for batch in batches {
            let size = try WirePayload(batch: batch).encoded().count
            #expect(size <= Limits().maxBatchBytes + 1_024, "\(size) bytes")
        }
        #expect(batches.flatMap(\.events).count == 40)
    }

    @Test func aSystemChangeStartsANewBatch() throws {
        var queue = try DiskQueue(directory: temporaryQueueDirectory(), limits: Limits())
        var updated = testSystem
        updated.appVersion = "1.6.0"
        try queue.append(event("before"))
        try queue.append(event("before"))
        try queue.append(event("after", system: updated))
        try queue.seal(now: now)
        let batches = try allBatches(&queue)
        #expect(batches.map(\.system.appVersion) == ["1.5.0", "1.6.0"])
        #expect(batches.map(\.events.count) == [2, 1])
    }

    @Test func theQueueKeepsAtMostOneThousandEventsDroppingTheOldest() throws {
        var queue = try DiskQueue(directory: temporaryQueueDirectory(), limits: Limits())
        for index in 0..<600 { try queue.append(event("old\(index)")) }
        try queue.seal(now: now)
        for index in 0..<600 { try queue.append(event("new\(index)")) }
        #expect(queue.count == 1_000)
        try queue.seal(now: now)
        let names = try allBatches(&queue).flatMap(\.events).map(\.name)
        #expect(names.count == 1_000)
        #expect(names.first == "old200", "the 200 oldest were dropped")
        #expect(names.last == "new599")
    }

    @Test func eventsOlderThanSevenDaysAreDropped() throws {
        var queue = try DiskQueue(directory: temporaryQueueDirectory(), limits: Limits())
        try queue.append(event("ancient", at: now - 8 * 86_400))
        try queue.append(event("recent", at: now - 6 * 86_400))
        try queue.seal(now: now)
        let names = try allBatches(&queue).flatMap(\.events).map(\.name)
        #expect(names == ["recent"])
    }

    @Test func anInterruptedCutIsRedoneWithoutLosingOrDuplicatingEvents() throws {
        let directory = temporaryQueueDirectory()
        var queue = try DiskQueue(directory: directory, limits: Limits())
        for index in 0..<150 { try queue.append(event("e\(index)")) }
        // Simulate a crash mid-cut: the open file was renamed and one of two batches was written.
        let sealingID = "crash"
        let sealing = directory.appendingPathComponent("sealing-\(sealingID).jsonl")
        try FileManager.default.moveItem(at: directory.appendingPathComponent("open.jsonl"), to: sealing)
        let partial = StoredBatch(batchID: UUID(), system: testSystem, events: [event("e0")], source: sealingID)
        try JSONEncoder().encode(partial).write(to: directory.appendingPathComponent("batch-0000000001.json"))

        var recovered = try DiskQueue(directory: directory, limits: Limits())
        #expect(recovered.count == 150)
        let names = try allBatches(&recovered).flatMap(\.events).map(\.name)
        #expect(names == (0..<150).map { "e\($0)" })
        #expect(FileManager.default.fileExists(atPath: sealing.path) == false)
    }

    @Test func aTruncatedLineFromACrashIsSkipped() throws {
        let directory = temporaryQueueDirectory()
        var queue = try DiskQueue(directory: directory, limits: Limits())
        try queue.append(event("whole"))
        let handle = try FileHandle(forWritingTo: directory.appendingPathComponent("open.jsonl"))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(#"{"n":"cut sh"#.utf8))
        try handle.close()
        var reopened = try DiskQueue(directory: directory, limits: Limits())
        try reopened.seal(now: now)
        #expect(try allBatches(&reopened).flatMap(\.events).map(\.name) == ["whole"])
    }

    @Test func splittingKeepsTheHalvesInPlaceWithNewIds() throws {
        var queue = try DiskQueue(directory: temporaryQueueDirectory(), limits: Limits())
        for index in 0..<10 { try queue.append(event("first\(index)")) }
        try queue.seal(now: now)
        for index in 0..<3 { try queue.append(event("second\(index)")) }
        try queue.seal(now: now)
        let (url, batch) = try #require(try queue.oldestBatch())
        try queue.split(url)
        let batches = try allBatches(&queue)
        #expect(batches.map(\.events.count) == [5, 5, 3])
        #expect(batches[0].batchID != batch.batchID)
        #expect(batches.flatMap(\.events).map(\.name).prefix(10) == ArraySlice((0..<10).map { "first\($0)" }))
    }

    @Test func splittingReadsTheBatchAsItIsNowNotAsItWasSent() throws {
        var queue = try DiskQueue(directory: temporaryQueueDirectory(), limits: Limits())
        for index in 0..<10 { try queue.append(event("e\(index)")) }
        try queue.seal(now: now)
        let (url, sent) = try #require(try queue.oldestBatch())
        // While the request was out, the size limit trimmed the batch to its last two events.
        var trimmed = sent
        trimmed.events.removeFirst(8)
        try queue.replace(url, with: trimmed)
        try queue.split(url)
        let names = try allBatches(&queue).flatMap(\.events).map(\.name)
        #expect(names == ["e8", "e9"], "the trimmed events do not come back")
    }

    @Test func splittingABatchOfOneRemovesIt() throws {
        var queue = try DiskQueue(directory: temporaryQueueDirectory(), limits: Limits())
        try queue.append(event("only"))
        try queue.seal(now: now)
        let (url, _) = try #require(try queue.oldestBatch())
        try queue.split(url)
        #expect(queue.count == 0)
        #expect(try queue.oldestBatch() == nil)
    }

    @Test func removeAllEmptiesTheQueue() throws {
        var queue = try DiskQueue(directory: temporaryQueueDirectory(), limits: Limits())
        for index in 0..<120 { try queue.append(event("e\(index)")) }
        try queue.seal(now: now)
        try queue.append(event("late"))
        try queue.removeAll()
        #expect(queue.count == 0)
        #expect(try queue.oldestBatch() == nil)
    }

    @Test func theSDKFolderIsExcludedFromBackups() throws {
        let directory = temporaryQueueDirectory()
        _ = try DiskQueue(directory: directory, limits: Limits())
        let values = try directory.deletingLastPathComponent().resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }
}
