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
//      is idle by rule, so dispatch follows at once — `speech_dispatch` has the exact moment);
//    · `waymark_evidence` = label id, outcome, sensor, distances and (judge demo task 3)
//      `p_before` / `p_after` to 3 dp (`WaymarkLearning.tripLogFields`). These two are trip-log
//      only: the `evidence.jsonl` line (`waymark.evidence.v1`, additionalProperties false) is unchanged.
//
//  Judge demo task 3, learning made visible: every committed outcome keeps what it did to the
//  label's belief (`lastLearning`, `learned` per label this launch) for the Sidewalk memory card,
//  the Guide's ahead card and the map; `MapPin.checked` says the phone holds field evidence for it.
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
    /// Judge demo: the nearest report ahead at the last fix (`WaymarkSession.Step.nearest`, the
    /// same order the spoken line uses), for the Guide's Sidewalk memory card. Nil when nothing is
    /// ahead or the feature is off; cleared at a route boundary (idle fixes may fill it again).
    private(set) var nearest: WaymarkSession.Nearest?
    /// `GeoFix.timestamp` of the fix behind `nearest` (reference-date seconds), so the card can say
    /// "Waiting for a fresh GPS fix" once it is older than `NavigationHealth.maxFixAge` (review 2).
    private(set) var nearestFixTimestamp: TimeInterval?
    /// Judge demo task 3: what the last committed outcome did to its label's belief ("Not there ·
    /// 50 % → 43 % · spotter"). An unverifiable outcome (before == after) is shown only while no
    /// decisive one has been recorded this launch (`WaymarkLearning.kept`, review). Nil before the
    /// first this launch.
    private(set) var lastLearning: WaymarkLearning?
    /// Judge demo task 3: the last decisive outcome per label id (else the last unverifiable one),
    /// this launch only (the map's pin details, the Guide's ahead card).
    private(set) var learned: [String: WaymarkLearning] = [:]

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
        didSet {
            if enabled { load() } else { stopEvidence() }   // E1 review H2: nothing carries over
        }
    }

    /// E1 review H3: true while `AppModel` simulates a walk. Synthetic fixes with real LiDAR frames
    /// must never become evidence, so passes, ground events and spotter taps are skipped meanwhile.
    var simulating = false {
        didSet { if simulating { tracker.reset() } }
    }

    /// Speaks a line; returns whether the queue took it. AppModel wires it to
    /// `speech.say(line, .scene, ttl: 6)` (lowest band; spoken only into silence).
    @ObservationIgnored var onSpeak: ((String) -> Bool)?
    /// Called once after a successful load (AppModel prefetches the lines for the natural voice).
    @ObservationIgnored var onLoaded: (() -> Void)?
    /// Speaks a short VoiceOver announcement (spotter feedback). AppModel wires it to UIAccessibility.
    @ObservationIgnored var onAnnounce: ((String) -> Void)?
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
    /// E1 review M5: saved beliefs for ids this bundle does not have, kept so a different bundle
    /// (e.g. the simulator's `WAYMARK_PRIORS_FILE`) never erases them from `beliefs.json`.
    @ObservationIgnored private var foreignBeliefs: [String: WaymarkBelief] = [:]
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
            store.removeStaleTestFolders()            // task 3 review: UI tests only, no-op otherwise
            let saved = store.loadBeliefs()
            made?.restore(saved)                      // E1: evidence survives a relaunch
            if let made { foreignBeliefs = saved.filter { made.prior($0.key) == nil } }
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
        if nearest != step.nearest { nearest = step.nearest }
        nearestFixTimestamp = fix.timestamp
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
        // E1: LiDAR passes (design doc §9.1 / §9.2); never from a simulated walk (review H3).
        guard !simulating else { return }
        let near = session!.index.within(WaymarkSession.searchRadiusM, of: fix.coordinate)
        let gates = WaymarkEvidenceGates(speedMps: fix.speed, gpsAccuracyM: fix.accuracy, fixFresh: context.fixFresh)
        for verdict in tracker.step(labels: near, at: fix.coordinate, headingDeg: heading, legs: legs, gates: gates) {
            commit(verdict)
        }
    }

    /// E1: one LiDAR frame (every `LaneReport`, ~30 Hz). Cheap: counts and minima only.
    func ingest(depth sample: WaymarkDepthSample) {
        guard enabled, session != nil, !simulating else { return }
        tracker.add(sample)
    }

    /// E1: a LiDAR ground hazard was confirmed. Curb-like kinds (drop-off, step up) confirm the
    /// nearest curb-ramp / missing-curb-ramp label ahead (design doc §9.1 row 2).
    /// - Parameter curbLike: the hazard's kind is `.dropOff` or `.stepUp`.
    func groundEvent(curbLike: Bool) {
        guard curbLike, enabled, !simulating, let session, let fix = lastFix else { return }
        let near = session.index.within(WaymarkSession.searchRadiusM, of: fix.coordinate)
        let gates = WaymarkEvidenceGates(speedMps: fix.speed, gpsAccuracyM: fix.accuracy,
                                         fixFresh: NavigationHealth.isFresh(timestamp: fix.timestamp,
                                                                            now: Date().timeIntervalSinceReferenceDate))
        if let verdict = tracker.groundEvent(labels: near, at: fix.coordinate, headingDeg: lastHeading,
                                             legs: lastLegs, gates: gates) {
            commit(verdict)
        }
    }

    /// E1: the spotter's Confirm / Not there (design doc §9.3). Applies to the nearest label with a
    /// spoken line within 15 m; held `undoSeconds` before it counts (a new tap commits the old one).
    /// - Parameter outcome: `.confirmed` or `.contradicted`.
    func spotter(_ outcome: WaymarkOutcome) {
        guard let session, let fix = lastFix,
              NavigationHealth.isFresh(timestamp: fix.timestamp, now: Date().timeIntervalSinceReferenceDate) else {
            say(session == nil ? "Turn on Sidewalk memory first." : "Waiting for a fresh GPS fix.")
            return
        }
        guard !simulating else { say("Not saved during a simulated walk."); return }
        let near = session.index.within(WaymarkSpotter.reachM, of: fix.coordinate)
        guard let target = WaymarkSpotter.target(labels: near, at: fix.coordinate, headingDeg: lastHeading) else {
            say("No sidewalk report within 15 m.")
            return
        }
        // Review H5: a new tap on the same label replaces the pending one (the natural fix for a
        // mis-tap); a tap on another label commits the old one first.
        if let old = pendingTap, old.labelID != target.prior.id { commit(old.verdict) }
        spotterMessage = nil
        tapToken += 1
        let token = tapToken
        let verdict = WaymarkEvidenceVerdict(labelID: target.prior.id, outcome: outcome, sensor: .spotter,
                                             distM: target.distM, alongM: target.alongM,
                                             gpsAccuracyM: fix.accuracy, speedMps: fix.speed,
                                             tiltDeg: tracker.lastSample?.tiltDeg,
                                             torsoCover: tracker.lastSample?.torsoCover,
                                             headCover: tracker.lastSample?.headCover)
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

    /// Judge demo task 2: one pin on the map of reports — the label and its belief p now.
    struct MapPin: Identifiable, Equatable {
        /// The label.
        let prior: WaymarkPrior
        /// Belief p at the moment the pins were computed.
        let p: Double
        /// Task 3: field evidence for this label is stored on this phone (`WaymarkSession.isChecked`,
        /// restored from `beliefs.json`, so it survives a relaunch).
        var checked = false
        /// Task 3: what this launch's last outcome for the label did, if any.
        var learning: WaymarkLearning?
        /// The label id.
        var id: String { prior.id }
    }

    /// Judge demo task 2: the labels the map draws (`WaymarkMapSelection`: along the route and
    /// around the walker) with their current belief. Empty until the bundle has loaded.
    /// - Parameters:
    ///   - route: the route's waypoints (active route, else the demo route).
    ///   - walker: the last GPS position, if any.
    func mapPins(route: [Coordinate], walker: Coordinate?) -> [MapPin] {
        guard let session else { return [] }
        let now = Date().timeIntervalSince1970
        return WaymarkMapSelection.labels(index: session.index, route: route, walker: walker).map {
            MapPin(prior: $0, p: session.confidence(of: $0.id, nowUTC: now) ?? .nan,
                   checked: session.isChecked($0.id), learning: learned[$0.id])
        }
    }

    /// Shows and announces why a spotter tap did nothing (review M4).
    private func say(_ message: String) {
        spotterMessage = message
        onAnnounce?(message)
    }

    /// E1 review H2: the feature went off — drop open passes, the last fix, a pending tap (not
    /// committed: the helper switched the feature off inside the undo window) and any message.
    private func stopEvidence() {
        tracker.reset()
        lastFix = nil; lastHeading = nil; lastLegs = nil
        if let tap = pendingTap { onLog?("waymark_spotter", ["action": "dropped_feature_off", "label_id": tap.labelID]) }
        pendingTap = nil
        spotterMessage = nil
        nearest = nil
    }

    /// E1: cancels the pending spotter tap (the toast's Undo).
    func undoSpotter() {
        guard let tap = pendingTap else { return }
        pendingTap = nil
        onLog?("waymark_spotter", ["action": "undo", "label_id": tap.labelID])
    }

    /// E1: applies one outcome: belief update, `evidence.jsonl` line, `beliefs.json`, a
    /// `waymark_evidence` trip-log record (label id, outcome, sensor, distances, p before / after —
    /// no coordinates). Task 3: keeps what it did in `lastLearning` / `learned`.
    private func commit(_ v: WaymarkEvidenceVerdict) {
        guard session != nil, enabled else { return }
        let now = Date().timeIntervalSince1970
        let learning = session!.record(v.outcome, sensor: v.sensor, labelID: v.labelID, nowUTC: now)
        let line = WaymarkRecord.evidence(labelID: v.labelID, outcome: v.outcome, sensor: v.sensor, distM: v.distM,
                                          alongM: v.alongM, gpsAccuracyM: v.gpsAccuracyM, speedMps: v.speedMps,
                                          tiltDeg: v.tiltDeg, torsoCover: v.torsoCover, headCover: v.headCover,
                                          build: build, timestampUTC: now)
        var fields: [String: Any] = ["label_id": v.labelID, "outcome": v.outcome.rawValue, "sensor": v.sensor.rawValue]
        if let d = v.distM, d.isFinite { fields["dist_m"] = Self.round1(d) }
        if let a = v.alongM, a.isFinite { fields["along_m"] = Self.round1(a) }
        if let r = v.reason { fields["reason"] = r }                       // review M3
        // Task 3: trip log only — never the evidence.jsonl line (schema additionalProperties false).
        for (key, value) in learning?.tripLogFields ?? [:] { fields[key] = value }
        if let error = store.appendEvidence(line) { fields["write_error"] = error }
        // Unverifiable changes no belief (review), so only decisive outcomes rewrite beliefs.json;
        // ids from other bundles are written back unchanged (review M5).
        if v.outcome != .unverifiable,
           let error = store.saveBeliefs(foreignBeliefs.merging(session!.beliefs) { _, mine in mine }) {
            fields["beliefs_error"] = error
        }
        onLog?("waymark_evidence", fields)
        if let learning {                                                   // task 3
            // Review: an unverifiable pass never hides a decisive change (`WaymarkLearning.kept`).
            learned[learning.labelID] = WaymarkLearning.kept(learning, over: learned[learning.labelID])
            lastLearning = WaymarkLearning.kept(learning, over: lastLearning)
        }
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

    /// A label type in everyday words (`WaymarkGlance.words`, one definition for every screen).
    static func words(_ type: WaymarkLabelType) -> String { WaymarkGlance.words(type) }

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
        nearest = nil
        guard enabled else { tracker.reset(); return }
        for verdict in tracker.routeEnded() { commit(verdict) }
    }

    /// Task 3: the `Documents/` sub-folder in use (`waymark`, or the UI-test folder), for the card.
    var storeFolderName: String { WaymarkStore.folderName }

    /// Task 3 review: field evidence for `id` is stored on this phone (`WaymarkSession.isChecked`).
    func isChecked(_ id: String) -> Bool { session?.isChecked(id) ?? false }

    /// Task 3 review: how many label beliefs `beliefs.json` holds (this bundle's and foreign ids),
    /// so the card's "Saved on this phone" caption appears only once something is saved.
    var savedLabelCount: Int { (session?.beliefs.count ?? 0) + foreignBeliefs.count }

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
