//
//  WaymarkGlance.swift
//  CaneKitLogic
//
//  Waymark judge-demo: the words sidewalk memory shows on screen, defined once so the Guide card,
//  the Details card, the map and VoiceOver say the same thing. Display only: nothing here decides
//  whether to speak (that is `WaymarkAlertPolicy`) and nothing here is spoken by the speech queue.
//
//  Honesty rule (design doc §3.2.4): every type is phrased as a report ("Reported obstacle"),
//  never as something the phone detected. Confidence is the belief p of `WaymarkBelief` (plan 5.3),
//  shown as a whole percent with the word "likely".
//
//  Numbers: metres and percent are rounded half away from zero; a non-finite value drops its part
//  of the line instead of printing "nan" (the card must stay readable on a bad fix).
//  Portability (plan 1.4): Foundation only. Pure. Tests: `WaymarkGlanceTests.swift`.
//

import Foundation

/// Screen words for sidewalk memory.
public enum WaymarkGlance {

    /// A label type in everyday words. `surface_problem` uses the spoken line's word ("rough
    /// surface"); `other` says "sidewalk issue" so the card never shows a bare "report".
    /// - Parameter type: the label type.
    /// - Returns: lower-case words, unique per type.
    public static func words(_ type: WaymarkLabelType) -> String {
        switch type {
        case .obstacle: "obstacle"
        case .missingCurbRamp: "missing curb ramp"
        case .curbRamp: "curb ramp"
        case .surfaceProblem: "rough surface"
        case .noSidewalk: "no sidewalk"
        case .crosswalk: "crosswalk"
        case .other: "sidewalk issue"
        }
    }

    /// "Reported obstacle": the type as a report, never a detection.
    public static func reported(_ type: WaymarkLabelType) -> String { "Reported \(words(type))" }

    /// p as a whole percent, clamped to 0…100; nil when p is not finite.
    public static func percent(_ p: Double) -> Int? {
        guard p.isFinite else { return nil }
        return Int((min(max(p, 0), 1) * 100).rounded())
    }

    /// A distance as whole metres, never negative; nil when not finite.
    public static func metres(_ m: Double) -> Int? {
        guard m.isFinite else { return nil }
        return Int(max(0, m).rounded())
    }

    /// The Guide card line: "Reported obstacle · 40 m · 72 % likely".
    /// - Parameters:
    ///   - type: the label type.
    ///   - alongM: metres ahead along the path (`WaymarkAhead.Hit.alongM`).
    ///   - p: the belief (`WaymarkBelief.read(...).p`).
    public static func aheadLine(type: WaymarkLabelType, alongM: Double, p: Double) -> String {
        let facts = aheadFacts(alongM: alongM, p: p)
        return facts.isEmpty ? reported(type) : reported(type) + " · " + facts
    }

    /// The line without its type, for the card's second row: "40 m · 72 % likely" ("" when both
    /// numbers are bad).
    public static func aheadFacts(alongM: Double, p: Double) -> String {
        var parts: [String] = []
        if let m = metres(alongM) { parts.append("\(m) m") }
        if let pc = percent(p) { parts.append("\(pc) % likely") }
        return parts.joined(separator: " · ")
    }

    /// The same line for VoiceOver: "Reported obstacle, 40 meters ahead, 72 percent likely."
    public static func aheadSpoken(type: WaymarkLabelType, alongM: Double, p: Double) -> String {
        var parts = [reported(type)]
        if let m = metres(alongM) { parts.append("\(m) meters ahead") }
        if let pc = percent(p) { parts.append("\(pc) percent likely") }
        return parts.joined(separator: ", ") + "."
    }

    /// The small Guide chip: "Sidewalk memory off · Turn on", "… loading", "… unavailable",
    /// "… on · 3,405 reports".
    /// - Parameters:
    ///   - enabled: the stored switch.
    ///   - loadedLabels: label count once the bundle has loaded, else nil.
    ///   - failed: the bundle failed to load (Waymark stays silent).
    public static func chip(enabled: Bool, loadedLabels: Int?, failed: Bool = false) -> String {
        guard enabled else { return "Sidewalk memory off · Turn on" }
        if failed { return "Sidewalk memory unavailable" }
        guard let n = loadedLabels else { return "Sidewalk memory loading" }
        return "Sidewalk memory on · \(grouped(n)) reports"
    }

    /// The ahead card when the corridor ahead is empty (uses `WaymarkAhead.lookaheadMaxM`).
    public static let noneAhead = "Nothing reported in the next \(Int(WaymarkAhead.lookaheadMaxM)) m"
    /// The ahead card when the last fix is older than `NavigationHealth.maxFixAge`.
    public static let waitingForGPS = "Waiting for a fresh GPS fix"
    /// The ahead card while the bundle loads.
    public static let loadingLine = "Loading sidewalk reports…"
    /// The ahead card when the bundle failed to load.
    public static let failedLine = "Reports could not be loaded"

    /// An integer with comma thousands separators ("3,405"), independent of the device locale so
    /// tests and screenshots read the same everywhere.
    public static func grouped(_ n: Int) -> String {
        let digits = String(n.magnitude)
        var out = ""
        for (i, ch) in digits.enumerated() {
            if i > 0, (digits.count - i) % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return n < 0 ? "-" + out : out
    }
}
