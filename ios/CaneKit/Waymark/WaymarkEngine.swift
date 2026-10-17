//
//  WaymarkEngine.swift
//  CaneKit
//
//  Waymark A1 (plan v1.1 §6, M_NOTES §8.1): "sidewalk memory" in the app. Loads the Project
//  Sidewalk priors bundle off the main thread, keeps one `WaymarkSession` (the pure core in
//  CaneKitLogic), feeds it every GPS fix, and hands at most one line per fix to the speech queue
//  at `.scene` priority. ⚠ Waymark never speaks at `.safety` or `.nav` and never delays a base-app
//  cue: it speaks only into an idle queue, at the lowest band, never resumed after a cut, and any
//  LiDAR cue or one-shot LiDAR line silences it for `WaymarkAlertPolicy.lidarQuietS` (5 s) via
//  `lidarCue(active:)` / `lidarPulse()`.
//
//  Off by default (`AppModel.waymarkEnabled`, cleared after a crash loop by LaunchRecovery). The
//  bundle loads on first enable, never at launch while off.
//
//  Clocks (M_NOTES §8.2 "Clock rule"): wall clock for beliefs and spacing (`Date()`, UTC seconds
//  since 1970) and fix freshness (`GeoFix.timestamp` is `timeIntervalSinceReferenceDate`);
//  `systemUptime` only for the LiDAR window and the `*_ms` timings. The two are never compared.
//
//  Trip log (eval/README.md input contract):
//    · `waymark_load {labels, load_ms, source}` or `{error, load_ms}`;
//    · `waymark_cue` = `WaymarkRecord.cue` fields + `lookup_ms` (candidate lookup and decision for
//      that fix) and, on a spoken line, `latency_ms` (GPS fix timestamp → the `say` call; the queue
//      is idle by rule, so dispatch follows at once — `speech_dispatch` has the exact moment).
//
//  Inputs: `WAYMARK_PRIORS_FILE` (absolute path, simulator / e2e only) else the bundled
//  `waymark_priors.json`. Owner: `AppModel` (`waymark`, wired in `AppModel+Waymark.swift`).
//  Tests: the decisions are pure and tested in CaneKitLogic (`WaymarkSessionTests` and the L1–L3
//  suites); this class only measures time and moves data.
//

import Foundation
import Observation
import CaneKitLogic

/// Owns the Waymark session for the app. Main actor; the only off-main work is the file decode.
@MainActor @Observable
final class WaymarkEngine {

    /// What the Sense card shows under the switch.
    enum LoadState: Equatable {
        /// Never asked to load (the switch has been off since launch).
        case idle
        /// Decoding the bundle.
        case loading
        /// Ready; `labels` labels indexed.
        case loaded(labels: Int)
        /// The file was missing or failed validation; Waymark stays silent.
        case failed(String)
    }

    /// Load progress for the UI.
    private(set) var state: LoadState = .idle
    /// The last line spoken, for the card ("Reported obstacle ahead."). Nil before the first.
    private(set) var lastLine: String?
    /// Lines spoken since launch.
    private(set) var spokenCount = 0
    /// E1: a spotter tap waiting out its undo window (the card's toast). Nil when none.
    private(set) var pendingTap: SpotterTap?
    /// E1: the last evidence outcome in words ("Confirmed: obstacle, 3 m"), for the card.
    private(set) var lastEvidence: String?
    /// E1: evidence lines written since launch.
    private(set) var evidenceCount = 0
    /// E1: why the last spotter tap did nothing ("No sidewalk report within 15 m."), cleared by the next.
    private(set) var spotterMessage: String?

    /// A spotter tap held for `undoSeconds` before it counts (design doc §9.3).
    struct SpotterTap: Equatable {
        /// Distinguishes taps (a new tap replaces an old one).
        let token: Int
        /// The label tapped.
        let labelID: String
        /// Label type in words ("missing curb ramp").
        let typeWord: String
        /// Straight-line distance at the tap, metres.
        let distM: Double
        /// Confirm or Not there.
        let outcome: WaymarkOutcome
        /// The verdict to commit.
        let verdict: WaymarkEvidenceVerdict
    }

    /// How long a spotter tap can be undone (design doc §9.3: 10 s).
    static let undoSeconds = 10.0

    /// Mirrors `AppModel.waymarkEnabled`. Turning it on loads the bundle the first time.
    var enabled = false {
        didSet { if enabled { load() } }
    }

    /// Speaks a line; returns whether the queue took it. AppModel wires it to
    /// `speech.say(line, .scene, ttl: 6)` (lowest band; spoken only into silence).
    @ObservationIgnored var onSpeak: ((String) -> Bool)?
    /// Called once after a successful load (AppModel prefetches the lines for the natural voice).
    @ObservationIgnored var onLoaded: (() -> Void)?
    /// Writes a trip-log record. AppModel wires it to `logger.event`.
    @ObservationIgnored var onLog: ((String, [String: Any]) -> Void)?

    /// The pure core; nil until the bundle has loaded.
    @ObservationIgnored private var session: WaymarkSession?
    /// E1: LiDAR passes and curb events (pure, CaneKitLogic).
    @ObservationIgnored private var tracker = WaymarkEvidenceTracker()
    /// E1: `Documents/waymark/` files.
    @ObservationIgnored private let store = WaymarkStore()
    /// E1: the last fix, its heading and route legs (spotter taps and ground events use them).
    @ObservationIgnored private var lastFix: GeoFix?
    @ObservationIgnored private var lastHeading: Double?
    @ObservationIgnored private var lastLegs: [Coordinate]?
    /// E1: spotter tap counter.
    @ObservationIgnored private var tapToken = 0
    /// E1: `CFBundleShortVersionString (CFBundleVersion)` for the evidence `build` field.
    @ObservationIgnored private let build: String = {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "?"
        let b = info?["CFBundleVersion"] as? String ?? "?"
        return "waymark \(v) (\(b))"
    }()
    /// Heading from successive fixes (the engine's own; the base app's smoother is not shared).
    @ObservationIgnored private var course = CourseSmoother()
    /// A LiDAR cue is on right now (`AppModel.activeCue != .clear`).
    @ObservationIgnored private var lidarActive = false
    /// `systemUptime` when the last LiDAR cue started or ended; nil if none this run.
    @ObservationIgnored private var lidarChangedAt: TimeInterval?

    /// Loads the bundle once (no-op while loading or loaded; retries after a failure).
    func load() {
        switch state {
        case .loading, .loaded: return
        case .idle, .failed: break
        }
        guard let url = Self.bundleURL() else {
            state = .failed("waymark_priors.json is not in the app")
            onLog?("waymark_load", ["error": "missing_file", "load_ms": 0])
            return
        }
        state = .loading
        let started = ProcessInfo.processInfo.systemUptime
        Task {
            let (decoded, error) = await Task.detached(priority: .utility) { () -> (WaymarkPriorSet?, String?) in
                do {
                    let data = try Data(contentsOf: url)
                    return (try WaymarkPriorSet.decode(data), nil)
                } catch {
                    return (nil, String(describing: error))
                }
            }.value
            // Index build is part of "load and index" (eval contract), so it stays inside the timing.
            var made = decoded.map { WaymarkSession(priors: $0) }
            made?.restore(store.loadBeliefs())        // E1: evidence survives a relaunch
            let loadMs = (ProcessInfo.processInfo.systemUptime - started) * 1000
            if let made {
                session = made
                state = .loaded(labels: made.labelCount)
                onLog?("waymark_load", ["labels": made.labelCount, "load_ms": Self.round1(loadMs),
                                        "source": decoded?.sourceName ?? ""])
                onLoaded?()
            } else {
                state = .failed(error ?? "unknown")
                onLog?("waymark_load", ["error": error ?? "unknown", "load_ms": Self.round1(loadMs)])
            }
        }
    }

    /// One GPS fix (every fix, idle or navigating). Silent unless enabled and loaded.
    /// - Parameters:
    ///   - fix: the fix as the base app received it.
    ///   - route / waypointIndex: the active route and the next waypoint, or nil off-route.
    ///   - crossingSettle, voiceHeld, gpsWeak: base-app state (see `WaymarkSession.Context`).
    ///   - cueLevel, cuePlace: `rawValue`s of the walker's settings.
    func ingest(fix: GeoFix, route: Route?, waypointIndex: Int, crossingSettle: Bool, voiceHeld: Bool,
                speechIdle: Bool, gpsWeak: Bool, cueLevel: String, cuePlace: String) {
        let heading = course.update(fix)
        guard enabled, session != nil else { return }
        let t0 = ProcessInfo.processInfo.systemUptime
        let now = Date()
        var legs: [Coordinate]?
        if let route, waypointIndex < route.waypoints.count {
            legs = route.waypoints[max(0, waypointIndex)...].map(\.coordinate)
        }
        let sinceLidar: Double? = lidarActive ? 0 : lidarChangedAt.map { t0 - $0 }
        let context = WaymarkSession.Context(
            cueLevel: cueLevel, cuePlace: cuePlace, crossingSettle: crossingSettle, voiceHeld: voiceHeld,
            gpsWeak: gpsWeak,
            fixFresh: NavigationHealth.isFresh(timestamp: fix.timestamp, now: now.timeIntervalSinceReferenceDate),
            secondsSinceLidarCue: sinceLidar, nowUTC: now.timeIntervalSince1970, headingDeg: heading, legs: legs,
            speechIdle: speechIdle)
        lastFix = fix
        lastHeading = heading
        lastLegs = legs
        let step = session!.step(fix: fix, context: context)
        let lookupMs = Self.round1((ProcessInfo.processInfo.systemUptime - t0) * 1000)
        if let line = step.spoken, onSpeak?(line.text) == true {
            lastLine = line.text
            spokenCount += 1
        }
        let latencyMs = Self.round1((Date().timeIntervalSinceReferenceDate - fix.timestamp) * 1000)
        for record in step.records {
            var fields: [String: Any] = record
            fields["lookup_ms"] = lookupMs
            if record["line"] != nil { fields["latency_ms"] = latencyMs }
            onLog?("waymark_cue", fields)
        }
        // E1: LiDAR passes (design doc §9.1 / §9.2).
        let near = session!.index.within(WaymarkSession.searchRadiusM, of: fix.coordinate)
        let gates = WaymarkEvidenceGates(speedMps: fix.speed, gpsAccuracyM: fix.accuracy, fixFresh: context.fixFresh)
        for verdict in tracker.step(labels: near, at: fix.coordinate, headingDeg: heading, legs: legs, gates: gates) {
            commit(verdict)
        }
    }

    /// E1: one LiDAR frame (every `LaneReport`, ~30 Hz). Cheap: counts and minima only.
    func ingest(depth sample: WaymarkDepthSample) {
        guard enabled, session != nil else { return }
        tracker.add(sample)
    }

    /// E1: a LiDAR ground hazard was confirmed. Curb-like kinds (drop-off, step up) confirm the
    /// nearest curb-ramp / missing-curb-ramp label ahead (design doc §9.1 row 2).
    /// - Parameter curbLike: the hazard's kind is `.dropOff` or `.stepUp`.
    func groundEvent(curbLike: Bool) {
        guard curbLike, enabled, let session, let fix = lastFix else { return }
        let near = session.index.within(WaymarkSession.searchRadiusM, of: fix.coordinate)
        if let verdict = tracker.groundEvent(labels: near, at: fix.coordinate, headingDeg: lastHeading,
                                             legs: lastLegs, speedMps: fix.speed) {
            commit(verdict)
        }
    }

    /// E1: the spotter's Confirm / Not there (design doc §9.3). Applies to the nearest label with a
    /// spoken line within 15 m; held `undoSeconds` before it counts (a new tap commits the old one).
    /// - Parameter outcome: `.confirmed` or `.contradicted`.
    func spotter(_ outcome: WaymarkOutcome) {
        guard let session, let fix = lastFix else {
            spotterMessage = session == nil ? "Turn on Sidewalk memory first." : "Waiting for a GPS fix."
            return
        }
        let near = session.index.within(WaymarkSpotter.reachM, of: fix.coordinate)
        guard let target = WaymarkSpotter.target(labels: near, at: fix.coordinate, headingDeg: lastHeading) else {
            spotterMessage = "No sidewalk report within 15 m."
            return
        }
        if let old = pendingTap { commit(old.verdict) }
        spotterMessage = nil
        tapToken += 1
        let token = tapToken
        let verdict = WaymarkEvidenceVerdict(labelID: target.prior.id, outcome: outcome, sensor: .spotter,
                                             distM: target.distM, alongM: target.alongM,
                                             gpsAccuracyM: fix.accuracy, speedMps: fix.speed, tiltDeg: nil,
                                             torsoCover: nil, headCover: nil)
        pendingTap = SpotterTap(token: token, labelID: target.prior.id, typeWord: Self.words(target.prior.type),
                                distM: target.distM, outcome: outcome, verdict: verdict)
        onLog?("waymark_spotter", ["action": "tap", "label_id": target.prior.id, "outcome": outcome.rawValue])
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.undoSeconds))
            guard let self, let tap = self.pendingTap, tap.token == token else { return }
            self.pendingTap = nil
            self.commit(tap.verdict)
        }
    }

    /// E1: cancels the pending spotter tap (the toast's Undo).
    func undoSpotter() {
        guard let tap = pendingTap else { return }
        pendingTap = nil
        onLog?("waymark_spotter", ["action": "undo", "label_id": tap.labelID])
    }

    /// E1: applies one outcome: belief update, `evidence.jsonl` line, `beliefs.json`, a
    /// `waymark_evidence` trip-log record (label id, outcome, sensor, distances — no coordinates).
    private func commit(_ v: WaymarkEvidenceVerdict) {
        guard session != nil else { return }
        let now = Date().timeIntervalSince1970
        session!.record(v.outcome, sensor: v.sensor, labelID: v.labelID, nowUTC: now)
        let line = WaymarkRecord.evidence(labelID: v.labelID, outcome: v.outcome, sensor: v.sensor, distM: v.distM,
                                          alongM: v.alongM, gpsAccuracyM: v.gpsAccuracyM, speedMps: v.speedMps,
                                          tiltDeg: v.tiltDeg, torsoCover: v.torsoCover, headCover: v.headCover,
                                          build: build, timestampUTC: now)
        var fields: [String: Any] = ["label_id": v.labelID, "outcome": v.outcome.rawValue, "sensor": v.sensor.rawValue]
        if let d = v.distM { fields["dist_m"] = Self.round1(d) }
        if let a = v.alongM { fields["along_m"] = Self.round1(a) }
        if let error = store.appendEvidence(line) { fields["write_error"] = error }
        if let error = store.saveBeliefs(session!.beliefs) { fields["beliefs_error"] = error }
        onLog?("waymark_evidence", fields)
        evidenceCount += 1
        let type = session!.prior(v.labelID).map { Self.words($0.type) } ?? "report"
        let verb: String
        switch v.outcome {
        case .confirmed: verb = "Confirmed"
        case .contradicted: verb = "Not there"
        case .unverifiable: verb = "Couldn't check"
        }
        lastEvidence = "\(verb): \(type)" + (v.distM.map { ", \(Int($0.rounded())) m" } ?? "")
    }

    /// A label type in everyday words.
    static func words(_ type: WaymarkLabelType) -> String {
        switch type {
        case .obstacle: "obstacle"
        case .missingCurbRamp: "missing curb ramp"
        case .curbRamp: "curb ramp"
        case .surfaceProblem: "surface problem"
        case .noSidewalk: "no sidewalk"
        case .crosswalk: "crosswalk"
        case .other: "report"
        }
    }

    /// A one-shot LiDAR line (a ground hazard, "Close.") was spoken: restart the 5 s quiet window
    /// (A1 review H2 — those lines do not move `activeCue`).
    func lidarPulse() {
        lidarChangedAt = ProcessInfo.processInfo.systemUptime
    }

    /// The base app's rendered LiDAR cue changed. Any cue (on, or just ended) restarts the 5 s
    /// quiet window, so Waymark never talks over or right after an obstacle warning.
    /// - Parameter active: `activeCue != .clear`.
    func lidarCue(active: Bool) {
        guard active != lidarActive else { return }
        lidarActive = active
        lidarChangedAt = ProcessInfo.processInfo.systemUptime
    }

    /// A route began: labels may be announced again on this route.
    func routeStarted() {
        session?.routeStarted()
        tracker.routeStarted()
        course.reset()
    }

    /// A route ended (Stop, arrival or a replacement route). Open LiDAR passes close (E1).
    func routeEnded() {
        session?.routeEnded()
        for verdict in tracker.routeEnded() { commit(verdict) }
    }

    /// `WAYMARK_PRIORS_FILE` when set (simulator / e2e), else the bundled file.
    private static func bundleURL() -> URL? {
        if let path = ProcessInfo.processInfo.environment["WAYMARK_PRIORS_FILE"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return Bundle.main.url(forResource: "waymark_priors", withExtension: "json")
    }

    /// Milliseconds to one decimal for the log.
    private static func round1(_ ms: Double) -> Double { (ms * 10).rounded() / 10 }
}
