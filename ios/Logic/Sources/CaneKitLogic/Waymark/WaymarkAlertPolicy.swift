//
//  WaymarkAlertPolicy.swift
//  CaneKitLogic
//
//  Waymark L3: whether to speak about one label ahead, right now. Design doc v1.0 8.1 and 8.3, as
//  amended by WAYMARK_PLAN 5.2 (which types speak at which level) and 5.4 (thresholds).
//
//  The rules, in the order they are checked (the first that fails names the silence):
//    1. The type has a line (`crosswalk` / `other` never speak).                 not_spoken_type
//    2. Cue level known and not Quiet; place known and not Indoors.               level_* / indoors / place_unknown
//    3. Standard speaks obstacle / missing curb ramp / no sidewalk only.         level_detailed_only
//    4. Belief p ≥ tau for the type (curb ramps have no tau: Detailed only).     below_threshold
//    5. GPS good (accuracy ≤ 20 m, not "GPS weak") and fresh.                    gps_weak / gps_stale
//    6. Not in a crossing settle, not while the walker is dictating.             crossing / voice_hold
//    7. No LiDAR warning in the last 5 s (never talk over the cane's own cue).   lidar_recent
//    8. Close enough: along-path ≤ trigger distance.                             not_yet
//    9. Not already announced this route; at most 6 per route; 20 s apart.        already_announced / route_cap / spacing
//  Only a `.speak` decision changes state. Unknown levels fail quiet: a renamed base-app level must
//  never make Waymark louder.
//  The app speaks a decision at `SpeechPriority.obstacle`, never `.nav` or `.safety` (plan 7.5).
//
//  Design choices to confirm with W (STATUS_M): curb ramps at Detailed speak without a p gate;
//  "LiDAR warned" means any LiDAR cue (the app cannot match identities), which only makes Waymark
//  quieter; the position-uncertainty margin is added to the trigger distance (warn earlier when GPS
//  and the label position are uncertain), capped at the look-ahead.
//
//  Portability (plan 1.4): Foundation only; cue level / place arrive as raw strings so this folder
//  needs no base-repo type beyond `Coordinate` / `GeoMath`.
//  Pure: explicit `nowUTC`; the AR-clock "seconds since LiDAR cue" is computed by the app.
//  Tests: `WaymarkAlertPolicyTests.swift`.
//

import Foundation

/// Everything the policy may look at, as plain values.
public struct WaymarkAlertInputs: Sendable, Equatable {
    /// `CueLevel.rawValue`: "quiet", "standard" or "detailed".
    public let cueLevel: String
    /// `CuePlace.rawValue`: "outdoors" or "indoors".
    public let cuePlace: String
    /// `NavigationEngine.isCrossingSettle`.
    public let crossingSettle: Bool
    /// The speech queue's voice hold (the walker is dictating).
    public let voiceHeld: Bool
    /// `NavigationEngine.gpsWeak`.
    public let gpsWeak: Bool
    /// `NavigationHealth.isFresh` for the fix.
    public let fixFresh: Bool
    /// Seconds since the last LiDAR obstacle / head cue (AR clock), or nil when none this session.
    public let secondsSinceLidarCue: Double?
    /// Ground speed, m/s (negative = invalid).
    public let speedMps: Double
    /// Horizontal accuracy, m (negative = invalid).
    public let gpsAccuracyM: Double
    /// UTC seconds (wall clock), for the spacing rule.
    public let nowUTC: Double

    public init(cueLevel: String, cuePlace: String, crossingSettle: Bool, voiceHeld: Bool, gpsWeak: Bool,
                fixFresh: Bool, secondsSinceLidarCue: Double?, speedMps: Double, gpsAccuracyM: Double,
                nowUTC: Double) {
        self.cueLevel = cueLevel; self.cuePlace = cuePlace; self.crossingSettle = crossingSettle
        self.voiceHeld = voiceHeld; self.gpsWeak = gpsWeak; self.fixFresh = fixFresh
        self.secondsSinceLidarCue = secondsSinceLidarCue; self.speedMps = speedMps
        self.gpsAccuracyM = gpsAccuracyM; self.nowUTC = nowUTC
    }
}

/// The outcome of one `decide` call.
public enum WaymarkDecision: Sendable, Equatable {
    /// Speak `line` about `labelID`.
    case speak(WaymarkLine, labelID: String)
    /// Stay silent; `reason` is logged as `waymark_cue.suppressed_reason`.
    case silent(reason: String)
}

/// The cue policy. One instance per app run, owned by `WaymarkEngine`.
public struct WaymarkAlertPolicy: Sendable, Equatable {
    /// Minimum time between two Waymark lines, seconds `[H]` (design doc 8.3).
    public static let minSpacingS = 20.0
    /// Most Waymark lines per route `[H]` (design doc 8.3).
    public static let maxPerRoute = 6
    /// Silence after any LiDAR warning, seconds (design doc 8.3).
    public static let lidarQuietS = 5.0
    /// Assumed label position error, metres `[H]` until F1 measures it (design doc 8.3).
    public static let labelErrorM = 8.0
    /// Worse GPS than this is "weak", metres (the base app's veer bound).
    public static let maxGpsAccuracyM = 20.0
    /// Seconds of walking a line should come before the label `[H]` (design doc 8.3).
    public static let leadTimeS = 8.0
    /// Bounds of the speed-based trigger distance, metres (design doc 8.3).
    public static let minTriggerM = 12.0, maxTriggerM = 35.0

    /// Labels announced since the last `routeStarted()` / `routeEnded()`.
    private var announced: Set<String> = []
    /// Lines spoken since the last route boundary.
    private var spokenThisRoute = 0
    /// UTC seconds of the last line, any route.
    private var lastSpokenAt: Double?

    public init() {}

    /// How far before a label to speak: `clamp(speed × 8 s, 12, 35) + √(gps² + label²)`, capped at
    /// `WaymarkAhead.lookaheadMaxM` (labels farther than that are never candidates).
    /// - Parameters:
    ///   - speedMps: ground speed (negative / non-finite treated as 0).
    ///   - gpsAccuracyM: horizontal accuracy (negative / non-finite treated as 0).
    /// - Returns: metres along the path.
    public static func triggerDistanceM(speedMps: Double, gpsAccuracyM: Double) -> Double {
        let v = speedMps.isFinite ? max(0, speedMps) : 0
        let acc = gpsAccuracyM.isFinite ? max(0, gpsAccuracyM) : 0
        let base = min(max(v * leadTimeS, minTriggerM), maxTriggerM)
        let margin = (acc * acc + labelErrorM * labelErrorM).squareRoot()
        return min(WaymarkAhead.lookaheadMaxM, base + margin)
    }

    /// Decides about one label ahead.
    /// - Parameters:
    ///   - hit: the label and where it is along the path (`WaymarkAhead.select`).
    ///   - p: the label's current belief (`WaymarkBelief.read(...).p`).
    ///   - inputs: the moment's state.
    /// - Returns: `.speak` (and records it) or `.silent(reason:)` (state unchanged).
    public mutating func decide(_ hit: WaymarkAhead.Hit, p: Double, inputs: WaymarkAlertInputs) -> WaymarkDecision {
        let type = hit.prior.type
        guard let line = WaymarkLine(for: type) else { return .silent(reason: "not_spoken_type") }
        switch inputs.cueLevel {
        case "quiet": return .silent(reason: "level_quiet")
        case "standard": if line.detailedOnly { return .silent(reason: "level_detailed_only") }
        case "detailed": break
        default: return .silent(reason: "level_unknown")
        }
        switch inputs.cuePlace {
        case "outdoors": break
        case "indoors": return .silent(reason: "indoors")
        default: return .silent(reason: "place_unknown")
        }
        guard p.isFinite else { return .silent(reason: "below_threshold") }
        if let tau = WaymarkThreshold.tau(for: type), p < tau { return .silent(reason: "below_threshold") }
        let acc = inputs.gpsAccuracyM
        if inputs.gpsWeak || !acc.isFinite || acc < 0 || acc > Self.maxGpsAccuracyM {
            return .silent(reason: "gps_weak")
        }
        guard inputs.fixFresh else { return .silent(reason: "gps_stale") }
        if inputs.crossingSettle { return .silent(reason: "crossing") }
        if inputs.voiceHeld { return .silent(reason: "voice_hold") }
        if let s = inputs.secondsSinceLidarCue, s < Self.lidarQuietS { return .silent(reason: "lidar_recent") }
        let trigger = Self.triggerDistanceM(speedMps: inputs.speedMps, gpsAccuracyM: acc)
        guard hit.alongM <= trigger else { return .silent(reason: "not_yet") }
        guard !announced.contains(hit.prior.id) else { return .silent(reason: "already_announced") }
        guard spokenThisRoute < Self.maxPerRoute else { return .silent(reason: "route_cap") }
        if let last = lastSpokenAt, inputs.nowUTC - last < Self.minSpacingS { return .silent(reason: "spacing") }
        announced.insert(hit.prior.id)
        spokenThisRoute += 1
        lastSpokenAt = inputs.nowUTC
        return .speak(line, labelID: hit.prior.id)
    }

    /// A route started: every label may be announced once more and the per-route cap resets.
    /// The 20 s spacing carries over.
    public mutating func routeStarted() { announced.removeAll(); spokenThisRoute = 0 }

    /// A route ended (arrived or stopped): same reset as `routeStarted()`.
    public mutating func routeEnded() { announced.removeAll(); spokenThisRoute = 0 }
}
