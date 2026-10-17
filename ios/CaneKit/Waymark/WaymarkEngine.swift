//
//  WaymarkEngine.swift
//  CaneKit
//
//  Waymark A1 (plan v1.1 §6, M_NOTES §8.1): "sidewalk memory" in the app. Loads the Project
//  Sidewalk priors bundle off the main thread, keeps one `WaymarkSession` (the pure core in
//  CaneKitLogic), feeds it every GPS fix, and hands at most one line per fix to the speech queue
//  at `.obstacle` priority. ⚠ Waymark never speaks at `.safety` or `.nav` and never delays a
//  base-app safety cue: the caller's `onSpeak` uses `.obstacle`, and any LiDAR cue silences
//  Waymark for `WaymarkAlertPolicy.lidarQuietS` (5 s) via `lidarCue(active:)`.
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
//      that fix) and, on a spoken line, `latency_ms` (GPS fix timestamp → speech dispatch).
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

    /// Mirrors `AppModel.waymarkEnabled`. Turning it on loads the bundle the first time.
    var enabled = false {
        didSet { if enabled { load() } }
    }

    /// Speaks a line. AppModel wires it to `speech.say(line, .obstacle, ttl: 6)`.
    @ObservationIgnored var onSpeak: ((String) -> Void)?
    /// Writes a trip-log record. AppModel wires it to `logger.event`.
    @ObservationIgnored var onLog: ((String, [String: Any]) -> Void)?

    /// The pure core; nil until the bundle has loaded.
    @ObservationIgnored private var session: WaymarkSession?
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
            let made = decoded.map { WaymarkSession(priors: $0) }
            let loadMs = (ProcessInfo.processInfo.systemUptime - started) * 1000
            if let made {
                session = made
                state = .loaded(labels: made.labelCount)
                onLog?("waymark_load", ["labels": made.labelCount, "load_ms": Self.round1(loadMs),
                                        "source": decoded?.sourceName ?? ""])
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
                gpsWeak: Bool, cueLevel: String, cuePlace: String) {
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
            secondsSinceLidarCue: sinceLidar, nowUTC: now.timeIntervalSince1970, headingDeg: heading, legs: legs)
        let step = session!.step(fix: fix, context: context)
        let lookupMs = Self.round1((ProcessInfo.processInfo.systemUptime - t0) * 1000)
        if let line = step.spoken {
            lastLine = line.text
            spokenCount += 1
            onSpeak?(line.text)
        }
        let latencyMs = Self.round1((Date().timeIntervalSinceReferenceDate - fix.timestamp) * 1000)
        for record in step.records {
            var fields: [String: Any] = record
            fields["lookup_ms"] = lookupMs
            if record["line"] != nil { fields["latency_ms"] = latencyMs }
            onLog?("waymark_cue", fields)
        }
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
        course.reset()
    }

    /// A route ended (Stop, arrival or a replacement route).
    func routeEnded() {
        session?.routeEnded()
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
