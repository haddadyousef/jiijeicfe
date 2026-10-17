//
//  WaymarkBelief.swift
//  CaneKitLogic
//
//  Waymark L2: how much to believe a prior label is still true today, and when that is enough to
//  warn. Both are normative (WAYMARK_PLAN v1.1 §5.3, §5.4, D-16): the Windows reference Python and
//  this file must agree to 1e-9 on `belief_vectors.json` / `threshold_vectors.json`.
//
//  Belief (5.3): a Beta posterior. The prior's own validations seed it (a = 1 + n_agree,
//  b = 1 + n_disagree); our evidence adds mass eA (confirmed) / eB (contradicted) weighted by
//  sensor, and that mass halves every `halfLifeDays(type)` days, so an old check fades back toward
//  what Project Sidewalk said. `unverifiable` changes nothing, not even the clock.
//  Threshold (5.4): tau = C_fa / (C_fa + C_miss), the cost-minimizing cut for a calibrated p.
//  Costs are design choices, not measurements `[H]`.
//
//  Clocks: every function takes `now` in UTC seconds (Unix epoch). No stored or hidden clock. The
//  app converts `GeoFix.timestamp` (reference-date seconds) at the engine boundary, never here.
//  Portability (plan 1.4): Foundation only. Pure, `Sendable` value types.
//  Tests: `WaymarkBeliefTests.swift`.
//

import Foundation

/// Where a piece of evidence came from (`waymark.evidence.v1` `sensor`; raw values are the contract).
public enum WaymarkSensor: String, Sendable, Codable, CaseIterable {
    /// The sighted spotter's Confirm / Not there tap.
    case spotter
    /// LiDAR torso band.
    case lidarTorso = "lidar_torso"
    /// LiDAR head band.
    case lidarHead = "lidar_head"
    /// The LiDAR ground (drop-off / curb) detector.
    case ground
    /// The camera's vision hazard watch.
    case vision
}

/// What one pass past a label showed (`waymark.evidence.v1` `outcome`).
public enum WaymarkOutcome: String, Sendable, Codable, CaseIterable {
    /// The sensor saw what the label says.
    case confirmed
    /// The sensor could have seen it and did not.
    case contradicted
    /// The pass could not tell (no coverage, weak GPS, wrong sensor for the type).
    case unverifiable
}

/// Per-label evidence state (plan 5.3). Starts empty.
public struct WaymarkBelief: Sendable, Equatable, Codable {
    /// Accumulated confirming mass, as of `tLast`.
    public var eA: Double = 0
    /// Accumulated contradicting mass, as of `tLast`.
    public var eB: Double = 0
    /// UTC seconds of the last counted (non-unverifiable) update; nil until the first one.
    public var tLast: Double?

    /// An empty belief (prior only).
    public init() {}

    /// Seconds per day.
    static let secondsPerDay = 86_400.0

    /// Evidence half-life in days `[H]` (plan 5.3): obstacles and surface problems change fastest.
    /// - Parameter type: the label type.
    /// - Returns: 60 (obstacle), 120 (surface problem), 365 (everything else).
    public static func halfLifeDays(_ type: WaymarkLabelType) -> Double {
        switch type {
        case .obstacle: 60
        case .surfaceProblem: 120
        case .curbRamp, .missingCurbRamp, .noSidewalk, .crosswalk, .other: 365
        }
    }

    /// Evidence weight by sensor `[H]` (plan 5.3): the spotter's tap is ground truth.
    /// - Parameter sensor: the source.
    /// - Returns: 2.0 spotter, 1.0 LiDAR torso / head, 0.5 ground / vision.
    public static func weight(_ sensor: WaymarkSensor) -> Double {
        switch sensor {
        case .spotter: 2.0
        case .lidarTorso, .lidarHead: 1.0
        case .ground, .vision: 0.5
        }
    }

    /// `e · 0.5^(dt / H)` with dt in days, `dt = max(0, now − tLast)`.
    static func decay(_ e: Double, from tLast: Double?, to now: Double, halfLifeDays h: Double) -> Double {
        guard let tLast, e != 0 else { return e }
        let dtDays = max(0, now - tLast) / secondsPerDay
        return e * pow(0.5, dtDays / h)
    }

    /// The belief at `now`. Does not change the state.
    /// - Parameters:
    ///   - prior: the label (its type picks the half-life; its validations seed a and b).
    ///   - now: UTC seconds.
    /// - Returns: a, b, p = a / (a + b), and n_eff (display only, D-20).
    public func read(prior: WaymarkPrior, now: Double) -> (a: Double, b: Double, p: Double, nEff: Double) {
        let h = Self.halfLifeDays(prior.type)
        let ea = Self.decay(eA, from: tLast, to: now, halfLifeDays: h)
        let eb = Self.decay(eB, from: tLast, to: now, halfLifeDays: h)
        let a = 1 + Double(prior.nAgree) + ea
        let b = 1 + Double(prior.nDisagree) + eb
        return (a, b, a / (a + b), Double(prior.nAgree + prior.nDisagree) + ea + eb)
    }

    /// Counts one outcome at `now`: decay both masses to `now`, set `tLast = now`, then add the
    /// sensor's weight to eA (confirmed) or eB (contradicted). `unverifiable` changes nothing.
    /// - Parameters:
    ///   - outcome: what the pass showed.
    ///   - sensor: where it came from (sets the weight).
    ///   - type: the label's type (sets the half-life).
    ///   - now: UTC seconds.
    public mutating func update(_ outcome: WaymarkOutcome, sensor: WaymarkSensor,
                                type: WaymarkLabelType, now: Double) {
        guard outcome != .unverifiable else { return }
        let h = Self.halfLifeDays(type)
        eA = Self.decay(eA, from: tLast, to: now, halfLifeDays: h)
        eB = Self.decay(eB, from: tLast, to: now, halfLifeDays: h)
        tLast = now
        let w = Self.weight(sensor)
        if outcome == .confirmed { eA += w } else { eB += w }
    }
}

/// Cost-weighted alert thresholds (plan 5.4).
public enum WaymarkThreshold {
    /// Relative costs of a missed real hazard and of warning about one that is gone `[H]`.
    public struct Costs: Sendable, Equatable {
        public let miss: Double
        public let falseAlarm: Double
    }

    /// Plan 5.4 defaults. Types not listed never alert on p alone (curb ramps are informational,
    /// crosswalks and "other" are never spoken).
    public static func costs(for type: WaymarkLabelType) -> Costs? {
        switch type {
        case .obstacle: Costs(miss: 5, falseAlarm: 1)
        case .missingCurbRamp, .noSidewalk: Costs(miss: 4, falseAlarm: 1)
        case .surfaceProblem: Costs(miss: 2, falseAlarm: 1)
        case .curbRamp, .crosswalk, .other: nil
        }
    }

    /// `C_fa / (C_fa + C_miss)`: the threshold that minimizes expected cost for a calibrated p.
    public static func tau(costMiss: Double, costFalseAlarm: Double) -> Double {
        costFalseAlarm / (costFalseAlarm + costMiss)
    }

    /// The type's threshold, computed from its costs (never a typed literal), or nil when the type
    /// has none.
    public static func tau(for type: WaymarkLabelType) -> Double? {
        costs(for: type).map { tau(costMiss: $0.miss, costFalseAlarm: $0.falseAlarm) }
    }
}
