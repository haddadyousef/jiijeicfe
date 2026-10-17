//
//  WaymarkLines.swift
//  CaneKitLogic
//
//  Waymark L3: the only words Waymark ever speaks (design doc v1.0 Appendix A). Fixed, number-free
//  and phrased as reports ("Reported …"), never detections: the phone did not see these, a Project
//  Sidewalk volunteer labelled them from street imagery, possibly years ago.
//  Defined once here. `SpokenPhrases.warningLines` appends `WaymarkLines.all`, so the natural-voice
//  warm-up caches exactly these bytes (design doc 8.3: retyping a line elsewhere silently falls back
//  to the system voice).
//  Portability (plan 1.4): Foundation only. Tests: `WaymarkAlertPolicyTests.swift`.
//

import Foundation

/// One of the five Waymark lines.
public enum WaymarkLine: String, Sendable, CaseIterable, Codable {
    case obstacle, missingCurbRamp = "missing_curb_ramp", noSidewalk = "no_sidewalk",
         surfaceProblem = "surface_problem", curbRamp = "curb_ramp"

    /// The spoken text (Appendix A). Under 40 characters each.
    public var text: String {
        switch self {
        case .obstacle: "Reported obstacle ahead."
        case .missingCurbRamp: "Reported missing curb ramp ahead."
        case .noSidewalk: "Reported no sidewalk ahead."
        case .surfaceProblem: "Reported rough surface ahead."
        case .curbRamp: "Reported curb ramp ahead."
        }
    }

    /// The line for a label type, or nil for types that are never spoken (`crosswalk`, `other`; D-15).
    public init?(for type: WaymarkLabelType) {
        switch type {
        case .obstacle: self = .obstacle
        case .missingCurbRamp: self = .missingCurbRamp
        case .noSidewalk: self = .noSidewalk
        case .surfaceProblem: self = .surfaceProblem
        case .curbRamp: self = .curbRamp
        case .crosswalk, .other: return nil
        }
    }

    /// Spoken at the Detailed cue level only (plan 5.2); the others also at Standard.
    public var detailedOnly: Bool { self == .surfaceProblem || self == .curbRamp }
}

/// The prefetch list.
public enum WaymarkLines {
    /// Every Waymark line, in `WaymarkLine.allCases` order (138 characters in total).
    public static let all: [String] = WaymarkLine.allCases.map(\.text)
}
