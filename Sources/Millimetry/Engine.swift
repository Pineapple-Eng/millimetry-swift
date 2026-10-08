import Foundation

/// The SDK's state and rules, behind one actor: the session, the disk queue, when to
/// flush, and what each response means. Everything outside it (time, the network, background
/// assertions, the device description) arrives through ``EngineDependencies``, so tests drive it
/// with a hand-moved clock and scripted responses.
actor Engine {
    let configuration: Configuration
    private let dependencies: EngineDependencies
    private let log: DebugLog

    private var queue: DiskQueue
    private var session: SessionTracker
    private var backoff: Backoff
    private var system: SystemInfo
    private(set) var isForeground = true
    private(set) var isEnabled = true

    /// The flush in progress, so every caller can wait for the same one.
    private var flushTask: Task<Void, Never>?
    /// Set when work arrives during a flush; the flush loops once more instead of a second flush
    /// running beside it.
    private var flushAgain = false
    private var loggedOverQuota = false

    init(configuration: Configuration, dependencies: EngineDependencies) async throws {
        self.configuration = configuration
        self.dependencies = dependencies
        self.log = DebugLog(enabled: configuration.isDebug)
        self.queue = try DiskQueue(directory: dependencies.queueDirectory, limits: configuration.limits)
        self.session = SessionTracker(timeout: configuration.limits.sessionTimeout)
        self.backoff = Backoff(base: configuration.limits.backoffBase, cap: configuration.limits.backoffCap)
        self.system = await dependencies.systemInfo()
    }

    /// Called once at launch: the automatic `app_open`, then a first flush for anything a previous
    /// launch left in the queue.
    func start() {
        if configuration.trackAppOpen {
            track("app_open", [:], at: dependencies.clock.now())
        }
        if queue.count > 0 {
            requestFlush()
        }
    }

    // MARK: Tracking

    func track(_ name: String, _ properties: [String: PropValue], at date: Date) {
        guard isEnabled else { return }
        guard !name.isEmpty, name.count <= 64, !name.hasPrefix("$") else {
            log.notice("dropped event with an invalid name (1–64 characters, not starting with $)")
            return
        }
        let event = QueuedEvent(
            name: name,
            timestamp: Int64((date.timeIntervalSince1970 * 1_000).rounded()),
            sessionID: session.sessionID(at: date),
            properties: properties,
            system: system
        )
        do {
            try queue.append(event)
        } catch {
            log.notice("could not queue an event: \(error.localizedDescription)")
            return
        }
        if queue.openCount >= configuration.limits.flushThreshold {
            requestFlush()
        }
    }

    // MARK: Lifecycle

    func didEnterBackground() async {
        let now = dependencies.clock.now()
        isForeground = false
        session.enterBackground(at: now)
        await dependencies.backgroundTasks.run(name: "Millimetry flush") { [self] in
            await self.flush()
        }
    }

    func willEnterForeground() async {
        let now = dependencies.clock.now()
        isForeground = true
        session.enterForeground(at: now)
        system = await dependencies.systemInfo()
        if configuration.trackAppOpen {
            track("app_open", [:], at: dependencies.clock.now())
        }
    }

    /// The timer's beat: flush while in the foreground, unless backing off.
    func tick() async {
        guard isForeground, isEnabled, queue.count > 0 else { return }
        guard backoff.mayAttempt(at: dependencies.clock.now()) else { return }
        await flush()
    }

    /// How long the timer should sleep: the flush interval, or less when a retry is due sooner.
    func nextWakeDelay() -> TimeInterval {
        let interval = configuration.flushInterval
        guard let next = backoff.nextAttemptAt else { return interval }
        let untilRetry = next.timeIntervalSince(dependencies.clock.now())
        return max(0.5, min(interval, untilRetry))
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        guard !enabled else { return }
        do {
            try queue.removeAll()
        } catch {
            log.notice("could not delete the queue: \(error.localizedDescription)")
        }
    }

    // MARK: Flushing

    /// Sends everything that can be sent now, and returns when that attempt is over.
    func flush() async {
        requestFlush()
        await flushTask?.value
    }

    /// Starts a flush, or asks the running one to go round again.
    private func requestFlush() {
        guard isEnabled else { return }
        if flushTask != nil {
            flushAgain = true
            return
        }
        flushTask = Task { await self.runFlush() }
    }

    private func runFlush() async {
        repeat {
            flushAgain = false
            await sendQueued()
        } while flushAgain && isEnabled && backoff.mayAttempt(at: dependencies.clock.now())
        flushTask = nil
    }

    private func sendQueued() async {
        do {
            try queue.seal(now: dependencies.clock.now())
        } catch {
            log.notice("could not form batches: \(error.localizedDescription)")
            return
        }
        while isEnabled, backoff.mayAttempt(at: dependencies.clock.now()) {
            let next: (url: URL, batch: StoredBatch)?
            do {
                next = try queue.oldestBatch()
            } catch {
                log.notice("could not read the queue: \(error.localizedDescription)")
                return
            }
            guard let url = next?.url, var batch = next?.batch else { return }

            // Drop events past the age limit before spending a request on them.
            let now = dependencies.clock.now()
            let fresh = batch.events.filter { !queue.isTooOld($0, now: now) }
            if fresh.count != batch.events.count {
                batch.events = fresh
                do { try queue.replace(url, with: batch) } catch { return }
                if fresh.isEmpty { continue }
            }

            let outcome = await upload(batch)
            // The queue may have changed while the request was out (appends, an opt-out), so
            // nothing read before the await is trusted beyond the batch's own file.
            guard isEnabled else { return }
            if handle(outcome, url: url, batch: batch) == .stop {
                return
            }
        }
    }

    private enum Next { case continueSending, stop }

    private func handle(_ outcome: UploadOutcome, url: URL, batch: StoredBatch) -> Next {
        let now = dependencies.clock.now()
        switch outcome {
        case .delivered:
            backoff.recordSuccess()
            try? queue.remove(url)
            return .continueSending
        case .overQuota:
            backoff.recordSuccess()
            if !loggedOverQuota {
                log.notice("the plan's monthly event limit is used up; events are being dropped")
                loggedOverQuota = true
            }
            try? queue.remove(url)
            return .continueSending
        case .tooLarge:
            if batch.events.count <= 1 {
                log.notice("dropped an event too large to send")
            }
            // Splits what is in the file now (or removes a single event), not the copy sent.
            try? queue.split(url)
            return .continueSending
        case .rateLimited(let seconds):
            backoff.recordRetryAfter(seconds, at: now)
            return .stop
        case .retryLater:
            backoff.recordFailure(at: now, jitter: dependencies.jitter())
            return .stop
        case .rejected(let status):
            log.notice(status == 401 ? "the app key was refused (401); check the key in configure()" : "a batch was refused (\(status)) and deleted")
            try? queue.remove(url)
            return .continueSending
        }
    }

    private func upload(_ batch: StoredBatch) async -> UploadOutcome {
        let body: Data
        do {
            body = try Gzip.compress(try WirePayload(batch: batch).encoded())
        } catch {
            return .rejected(status: 0)
        }
        var request = URLRequest(url: configuration.batchEndpoint)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("gzip", forHTTPHeaderField: "Content-Encoding")
        request.setValue(configuration.appKey, forHTTPHeaderField: "X-App-Key")
        request.setValue(batch.batchID.uuidString.lowercased(), forHTTPHeaderField: "X-Batch-Id")
        do {
            return UploadOutcome.classify(try await dependencies.transport.send(request))
        } catch {
            return .retryLater
        }
    }

    // MARK: Inspection (tests and debugging)

    var queuedCount: Int { queue.count }
    var nextAttemptAt: Date? { backoff.nextAttemptAt }
    var currentSessionID: UUID? { session.current }

    /// Waits for a flush that tracking started on its own (the 50-event threshold).
    func waitForIdle() async {
        while let running = flushTask {
            await running.value
        }
    }
}
