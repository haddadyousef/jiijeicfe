//
//  WaymarkLearning.swift
//  CaneKitLogic
//
//  Waymark judge demo, task 3: make learning visible. `WaymarkSession.record` returns what one
//  outcome did to a label's belief — p before and after, the outcome and its source — so the
//  Sidewalk memory cards and the map pin can show "Not there · 50 % → 43 % · spotter".
//  `unverifiable` changes nothing (plan 5.3, `WaymarkBelief.update`), so its before and after are
//  the same number and the words say "confidence unchanged" instead of pretending to learn.
//  Portability (plan 1.4): Foundation only. Pure. Tests: `WaymarkLearningTests.swift`.
//

import Foundation

/// What one recorded outcome did to one label's belief.
public struct WaymarkLearning: Sendable, Equatable {
    /// The label ("ps:13292406").
    public let labelID: String
    /// Its type.
    public let type: WaymarkLabelType
    /// What the pass showed.
    public let outcome: WaymarkOutcome
    /// Where it came from.
    public let sensor: WaymarkSensor
    /// Belief p just before the outcome, at the same instant.
    public let pBefore: Double
    /// Belief p just after (equal to `pBefore` for `unverifiable`).
    public let pAfter: Double

    /// Memberwise.
    public init(labelID: String, type: WaymarkLabelType, outcome: WaymarkOutcome, sensor: WaymarkSensor,
                pBefore: Double, pAfter: Double) {
        self.labelID = labelID; self.type = type; self.outcome = outcome; self.sensor = sensor
        self.pBefore = pBefore; self.pAfter = pAfter
    }

    /// False for `unverifiable`: the belief did not move.
    public var changed: Bool { outcome != .unverifiable }
}

extension WaymarkGlance {
    /// The source in words: "spotter", "LiDAR", "LiDAR curb check", "camera".
    public static func source(_ sensor: WaymarkSensor) -> String {
        switch sensor {
        case .spotter: "spotter"
        case .lidarTorso, .lidarHead: "LiDAR"
        case .ground: "LiDAR curb check"
        case .vision: "camera"
        }
    }

    /// "Not there · 50 % → 43 % · spotter", "Confirmed · 50 % → 60 % · LiDAR", or for an
    /// unverifiable pass "Couldn't check · confidence unchanged at 50 % · LiDAR".
    public static func learningLine(_ l: WaymarkLearning) -> String {
        let src = source(l.sensor)
        let after = percent(l.pAfter).map { "\($0) %" } ?? "?"
        switch l.outcome {
        case .unverifiable:
            return "Couldn't check · confidence unchanged at \(after) · \(src)"
        case .confirmed, .contradicted:
            let before = percent(l.pBefore).map { "\($0) %" } ?? "?"
            return "\(l.outcome == .confirmed ? "Confirmed" : "Not there") · \(before) → \(after) · \(src)"
        }
    }

    /// The same for VoiceOver: "Spotter said not there. Confidence went from 50 to 43 percent."
    public static func learningSpoken(_ l: WaymarkLearning) -> String {
        let src = source(l.sensor)
        let who = src.prefix(1).uppercased() + src.dropFirst()
        let after = percent(l.pAfter).map(String.init) ?? "unknown"
        switch l.outcome {
        case .unverifiable:
            return "\(who) could not check it. Confidence unchanged at \(after) percent."
        case .confirmed, .contradicted:
            let before = percent(l.pBefore).map(String.init) ?? "unknown"
            let said = l.outcome == .confirmed ? "confirmed it" : "said not there"
            return "\(who) \(said). Confidence went from \(before) to \(after) percent."
        }
    }
}
