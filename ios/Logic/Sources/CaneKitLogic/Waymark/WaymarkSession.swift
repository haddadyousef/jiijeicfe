//
//  WaymarkSession.swift
//  CaneKitLogic
//
//  Waymark A1 (plan v1.1 §6, design doc §8.4): the pure core of the app's `WaymarkEngine`. One GPS
//  fix in, at most one spoken line out. It owns the label index, the per-label beliefs (field
//  evidence, `WaymarkBelief`) and the alert policy, and turns each decision into a `waymark_cue`
//  trip-log record (`WaymarkRecord.cue`).
//
//  Per fix (`step`): candidates within `lookaheadMaxM + corridorHalfWidthM` of the fix →
//  `WaymarkAhead.select` (route legs win over heading) → hits closest first (ties by id) → for each,
//  belief p and `WaymarkAlertPolicy.decide`; the first `.speak` ends the fix. So two labels never
//  speak in one fix, and the 20 s spacing holds the second one afterwards.
//
//  Speaks only into silence (`Context.speechIdle`, A1 review): while the base app speaks or has
//  anything queued, nothing is decided and the label stays unannounced (`speech_busy`).
//
//  Logging rule (keeps a 1 Hz trip log readable): a spoken line is always logged; a silence is
//  logged once per (label, reason) per route and only inside the trigger distance; `not_yet` (the
//  label is ahead but not close enough, true on almost every fix) is never logged. `routeStarted()` / `routeEnded()` reset the policy's
//  announcements and this dedupe set together; beliefs survive (they are evidence, not state).
//
//  This file has no clock, no I/O and no platform types: the engine passes `nowUTC`, the heading
//  (its own `CourseSmoother`) and the route legs. Waymark code may use only Coordinate / GeoFix /
//  GeoMath from the base logic (design doc §8.1).
//
//  Owner: `WaymarkEngine` (ios/CaneKit/Waymark/WaymarkEngine.swift). Tests: WaymarkSessionTests.swift.
//

import Foundation

/// One walk's Waymark state: labels, beliefs, policy, and the log dedupe set.
public struct WaymarkSession: Sendable {

    /// Everything about the moment the session needs besides the fix itself. Strings are the
    /// base app's raw values (`cueLevel.rawValue`, `cuePlace.rawValue`) so the policy can fail
    /// quiet on a value it does not know.
    public struct Context: Sendable, Equatable {
        /// "quiet" / "standard" / "detailed".
        public var cueLevel: String
        /// "outdoors" / "indoors".
        public var cuePlace: String
        /// The base app is settling a crossing (`nav.isCrossingSettle`).
        public var crossingSettle: Bool
        /// The speech queue is holding the voice (a call, Siri, dictation).
        public var voiceHeld: Bool
        /// The base app's own GPS-weak flag (`nav.gpsWeak`).
        public var gpsWeak: Bool
        /// The fix is younger than `NavigationHealth.maxFixAge`.
        public var fixFresh: Bool
        /// Seconds since the last LiDAR cue, nil if none this run.
        public var secondsSinceLidarCue: Double?
        /// UTC seconds now (beliefs decay against it; spacing uses it).
        public var nowUTC: Double
        /// Course over ground in degrees (0 = north), nil when unknown.
        public var headingDeg: Double?
        /// The remaining route waypoints, nearest first; nil off-route. Wins over `headingDeg`.
        public var legs: [Coordinate]?
        /// Nothing is speaking, queued, paused between bands or held (`SpeechQueue.isIdle`). Waymark
        /// speaks only into silence, so it can never queue in front of, or be resumed after, a
        /// base-app line (A1 review H1 / H3).
        public var speechIdle: Bool

        /// Memberwise.
        public init(cueLevel: String, cuePlace: String, crossingSettle: Bool, voiceHeld: Bool, gpsWeak: Bool,
                    fixFresh: Bool, secondsSinceLidarCue: Double?, nowUTC: Double, headingDeg: Double?,
                    legs: [Coordinate]?, speechIdle: Bool) {
            self.cueLevel = cueLevel; self.cuePlace = cuePlace; self.crossingSettle = crossingSettle
            self.voiceHeld = voiceHeld; self.gpsWeak = gpsWeak; self.fixFresh = fixFresh
            self.secondsSinceLidarCue = secondsSinceLidarCue; self.nowUTC = nowUTC
            self.headingDeg = headingDeg; self.legs = legs; self.speechIdle = speechIdle
        }
    }

    /// What one fix produced.
    public struct Step: Sendable, Equatable {
        /// The line to speak, if any (at most one per fix).
        public var spoken: WaymarkLine?
        /// The label behind `spoken`.
        public var spokenLabelID: String?
        /// `waymark_cue` payloads to log, in decision order (already de-duplicated).
        public var records: [[String: String]]
        /// How many labels were ahead (`WaymarkAhead.select` hits), for the `lookup` log.
        public var candidates: Int
        /// The first hit in decision order (closest along the path, ties by id) with its belief,
        /// for the Guide's Sidewalk memory card; nil when nothing is ahead. Set before the speech
        /// gate, so a busy queue does not blank the card (judge demo, task 1). While the walker
        /// stands still or has no direction (`WaymarkAhead` selects nothing then), the last
        /// walking value is kept with its belief read again (review 1).
        public var nearest: Nearest? = nil
    }

    /// The nearest label ahead for display (`Step.nearest`). Same selection as the spoken line.
    public struct Nearest: Sendable, Equatable {
        /// The label's id ("ps:13292406").
        public let labelID: String
        /// Its type.
        public let type: WaymarkLabelType
        /// Metres ahead along the path.
        public let alongM: Double
        /// Belief p at this fix (`WaymarkBelief.read`).
        public let p: Double
    }

    /// Spatial index over the bundle.
    public let index: WaymarkIndex
    /// Labels by id, for `record(...)`.
    private let byID: [String: WaymarkPrior]
    /// Field evidence per label id (absent = no evidence yet).
    public private(set) var beliefs: [String: WaymarkBelief] = [:]
    /// Spacing, per-route cap and announced set.
    private var policy = WaymarkAlertPolicy()
    /// "label_id|reason" pairs already logged this route.
    private var logged: Set<String> = []
    /// The last `Step.nearest` computed while moving with a direction, kept for standing fixes.
    private var lastNearest: Nearest?

    /// Search radius around the fix: anything farther cannot be a `WaymarkAhead` hit.
    public static let searchRadiusM = WaymarkAhead.lookaheadMaxM + WaymarkAhead.corridorHalfWidthM

    /// - Parameter priors: a decoded bundle (`WaymarkPriorSet.decode`).
    public init(priors: WaymarkPriorSet) {
        index = WaymarkIndex(priors.labels)
        var map: [String: WaymarkPrior] = [:]
        for p in priors.labels { map[p.id] = p }   // decode already rejects duplicate ids
        byID = map
    }

    /// Number of labels loaded.
    public var labelCount: Int { byID.count }

    /// One GPS fix.
    /// - Parameters:
    ///   - fix: position, accuracy (m) and ground speed (m/s).
    ///   - context: the moment's state; see `Context`.
    /// - Returns: at most one line, the records to log, and the candidate count.
    public mutating func step(fix: GeoFix, context: Context) -> Step {
        var out = Step(spoken: nil, spokenLabelID: nil, records: [], candidates: 0)
        let near = index.within(Self.searchRadiusM, of: fix.coordinate)
        let hits = WaymarkAhead.select(from: near, at: fix.coordinate, speedMps: fix.speed,
                                       headingDeg: context.headingDeg, legs: context.legs)
            .sorted { ($0.alongM, $0.prior.id) < ($1.alongM, $1.prior.id) }
        out.candidates = hits.count
        // Same gate `WaymarkAhead.select` applies: standing, an invalid speed or no direction selects
        // nothing, which says nothing about what is ahead — keep the last report, re-read its belief.
        let moving = fix.speed.isFinite && fix.speed >= WaymarkAhead.minSpeedMps
            && ((context.legs?.isEmpty == false) || context.headingDeg?.isFinite == true)
        if moving {
            lastNearest = hits.first.map {
                Nearest(labelID: $0.prior.id, type: $0.prior.type, alongM: $0.alongM,
                        p: (beliefs[$0.prior.id] ?? WaymarkBelief()).read(prior: $0.prior, now: context.nowUTC).p)
            }
            out.nearest = lastNearest
        } else if let kept = lastNearest, let prior = byID[kept.labelID] {
            out.nearest = Nearest(labelID: kept.labelID, type: kept.type, alongM: kept.alongM,
                                  p: (beliefs[kept.labelID] ?? WaymarkBelief()).read(prior: prior, now: context.nowUTC).p)
        }
        guard !hits.isEmpty else { return out }
        // Silences are logged only inside the trigger distance (A1 review M5): a gate that holds a
        // label 30 m out is not the decision the eval needs; the one at speaking distance is.
        let trigger = WaymarkAlertPolicy.triggerDistanceM(speedMps: fix.speed, gpsAccuracyM: fix.accuracy)
        guard context.speechIdle else {
            for hit in hits where hit.alongM <= trigger {
                let id = hit.prior.id
                guard logged.insert("\(id)|speech_busy").inserted else { continue }
                let p = (beliefs[id] ?? WaymarkBelief()).read(prior: hit.prior, now: context.nowUTC).p
                out.records.append(WaymarkRecord.cue(labelID: id, type: hit.prior.type, p: p,
                                                     tau: WaymarkThreshold.tau(for: hit.prior.type),
                                                     alongM: hit.alongM, decision: .silent(reason: "speech_busy")))
            }
            return out
        }
        let inputs = WaymarkAlertInputs(cueLevel: context.cueLevel, cuePlace: context.cuePlace,
                                        crossingSettle: context.crossingSettle, voiceHeld: context.voiceHeld,
                                        gpsWeak: context.gpsWeak, fixFresh: context.fixFresh,
                                        secondsSinceLidarCue: context.secondsSinceLidarCue,
                                        speedMps: fix.speed, gpsAccuracyM: fix.accuracy, nowUTC: context.nowUTC)
        for hit in hits {
            let id = hit.prior.id
            let p = (beliefs[id] ?? WaymarkBelief()).read(prior: hit.prior, now: context.nowUTC).p
            let decision = policy.decide(hit, p: p, inputs: inputs)
            let record = WaymarkRecord.cue(labelID: id, type: hit.prior.type, p: p,
                                           tau: WaymarkThreshold.tau(for: hit.prior.type),
                                           alongM: hit.alongM, decision: decision)
            switch decision {
            case .speak(let line, _):
                out.records.append(record)
                out.spoken = line
                out.spokenLabelID = id
                return out
            case .silent(let reason):
                guard reason != "not_yet", hit.alongM <= trigger else { continue }
                if logged.insert("\(id)|\(reason)").inserted { out.records.append(record) }
            }
        }
        return out
    }

    /// Adds one piece of field evidence (spotter tap, LiDAR / ground / vision check, E1).
    /// Unknown label ids are ignored; `.unverifiable` changes nothing (`WaymarkBelief.update`).
    /// - Parameters: outcome, sensor, the label id and UTC seconds.
    public mutating func record(_ outcome: WaymarkOutcome, sensor: WaymarkSensor, labelID: String, nowUTC: Double) {
        guard let prior = byID[labelID], outcome != .unverifiable else { return }
        var belief = beliefs[labelID] ?? WaymarkBelief()
        belief.update(outcome, sensor: sensor, type: prior.type, now: nowUTC)
        beliefs[labelID] = belief
    }

    /// Puts back beliefs saved by an earlier run (E1, `beliefs.json`). Ids this bundle does not
    /// have are dropped, so a regenerated bundle cannot carry stale evidence onto other labels.
    public mutating func restore(_ saved: [String: WaymarkBelief]) {
        beliefs = saved.filter { byID[$0.key] != nil }
    }

    /// The label with this id, if loaded.
    public func prior(_ id: String) -> WaymarkPrior? { byID[id] }

    /// A route began: every label may be announced again, and silences are logged afresh.
    public mutating func routeStarted() { policy.routeStarted(); logged.removeAll(); lastNearest = nil }

    /// A route ended (stop or arrival): same reset as `routeStarted()`.
    public mutating func routeEnded() { policy.routeEnded(); logged.removeAll(); lastNearest = nil }
}
