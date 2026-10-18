//
//  WaymarkMap.swift
//  CaneKitLogic
//
//  Waymark judge demo, task 2: the map of reports.
//    · `WaymarkMapSelection` — which labels the map draws: with a route, every label within
//      `corridorM` of it (the whole route, behind the walker too: the map is a picture of the walk,
//      not the look-ahead); without one, every label within `nearRadiusM` of the walker (review: a
//      250 m circle on top of the route filled the judge shot with side streets). De-duplicated,
//      capped at `maxPins` (nearest the walker, else the route start, first). Output sorted by id.
//    · `WaymarkConfidenceBand` — the three display bands of belief p, each with a word and a shape,
//      so a pin never depends on colour alone (the colours are the app's colour-blind-safe lane
//      ladder, Theme.swift). The edges are display choices `[H]`, not alert thresholds: whether a
//      label is spoken is still `WaymarkAlertPolicy` with `WaymarkThreshold.tau`.
//  Geometry: a local east/north plane per route segment (equirectangular, R = 6,371,000 m as in
//  `GeoMath`), centimetre-accurate over a few hundred metres.
//  Portability (plan 1.4): Foundation only; base types `Coordinate`, `GeoMath`. Pure.
//  Tests: `WaymarkMapTests.swift`.
//

import Foundation

/// Which labels the map of reports draws.
public enum WaymarkMapSelection {
    /// Half-width of the band drawn along the route, metres `[H]`: half a street plus its sidewalk
    /// (~12 m) and the 8 m label error of design doc §8.3, rounded up. 40 m also drew the parallel
    /// street's sidewalks on the Ave.
    public static let corridorM = 25.0
    /// Radius drawn around the walker when there is no route, metres `[H]`.
    public static let nearRadiusM = 250.0
    /// Most pins drawn at once.
    public static let maxPins = 400
    /// Spacing of the index queries along a route segment, metres.
    static let sampleM = 20.0

    /// The labels to draw.
    /// - Parameters:
    ///   - index: the loaded labels.
    ///   - route: the route's waypoints in order (empty or one point = no route).
    ///   - walker: the walker's position, or nil when unknown.
    /// - Returns: at most `maxPins` labels, sorted by id.
    public static func labels(index: WaymarkIndex, route: [Coordinate], walker: Coordinate?) -> [WaymarkPrior] {
        var picked: [String: WaymarkPrior] = [:]
        if route.count >= 2 {
            // Any label within corridorM of a segment is within corridorM + sampleM / 2 of a sample.
            let query = corridorM + sampleM / 2
            for (a, b) in zip(route, route.dropFirst()) {
                let len = GeoMath.distanceMeters(a, b)
                let n = max(1, Int((len / sampleM).rounded(.up)))
                for k in 0...n {
                    let f = Double(k) / Double(n)
                    let c = Coordinate(latitude: a.latitude + f * (b.latitude - a.latitude),
                                       longitude: a.longitude + f * (b.longitude - a.longitude))
                    for p in index.within(query, of: c) where picked[p.id] == nil
                        && distanceToSegment(p.coordinate, a, b) <= corridorM {
                        picked[p.id] = p
                    }
                }
            }
        }
        if route.count < 2, let walker {
            for p in index.within(nearRadiusM, of: walker) { picked[p.id] = p }
        }
        var out = Array(picked.values)
        if out.count > maxPins {
            let centre = walker ?? route.first ?? out[0].coordinate
            out.sort {
                let (da, db) = (GeoMath.distanceMeters(centre, $0.coordinate), GeoMath.distanceMeters(centre, $1.coordinate))
                return da != db ? da < db : $0.id < $1.id
            }
            out = Array(out.prefix(maxPins))
        }
        return out.sorted { $0.id < $1.id }
    }

    /// Metres from `q` to the segment a–b (local plane centred on a).
    static func distanceToSegment(_ q: Coordinate, _ a: Coordinate, _ b: Coordinate) -> Double {
        let m = WaymarkAhead.metresPerDegree
        let k = cos(a.latitude * .pi / 180)
        let bx = (b.longitude - a.longitude) * m * k, by = (b.latitude - a.latitude) * m
        let qx = (q.longitude - a.longitude) * m * k, qy = (q.latitude - a.latitude) * m
        let len2 = bx * bx + by * by
        let t = len2 > 1e-12 ? min(max((qx * bx + qy * by) / len2, 0), 1) : 0
        let dx = qx - t * bx, dy = qy - t * by
        return (dx * dx + dy * dy).squareRoot()
    }
}

/// Display band of a belief p: word, colour (in the app) and shape together.
public enum WaymarkConfidenceBand: String, Sendable, CaseIterable {
    /// p ≥ `likelyMin`: drawn as a filled circle.
    case likely
    /// `uncertainMin` ≤ p < `likelyMin` (and a non-finite p): drawn as a filled diamond.
    case uncertain
    /// p < `uncertainMin`: drawn as a hollow ring.
    case doubtful

    /// Lower edge of `likely` `[H]` (display only).
    public static let likelyMin = 0.7
    /// Lower edge of `uncertain` `[H]` (display only).
    public static let uncertainMin = 0.4

    /// The band of `p`, decided on the whole percent the screen shows (`WaymarkGlance.percent`), so
    /// "70 % likely" is never labelled Uncertain (review: p = 0.696 read "70 % · Uncertain").
    public init(p: Double) {
        guard let pc = WaymarkGlance.percent(p) else { self = .uncertain; return }
        if pc >= Int((Self.likelyMin * 100).rounded()) { self = .likely }
        else if pc >= Int((Self.uncertainMin * 100).rounded()) { self = .uncertain }
        else { self = .doubtful }
    }

    /// "Likely" / "Uncertain" / "Doubtful".
    public var word: String {
        switch self {
        case .likely: "Likely"
        case .uncertain: "Uncertain"
        case .doubtful: "Doubtful"
        }
    }

    /// Pin shape, so the band reads without colour.
    public enum Shape: String, Sendable { case filledCircle, filledDiamond, hollowRing }

    /// The band's pin shape.
    public var shape: Shape {
        switch self {
        case .likely: .filledCircle
        case .uncertain: .filledDiamond
        case .doubtful: .hollowRing
        }
    }
}

/// Pin words for the map of reports (the rest of `WaymarkGlance` is in WaymarkGlance.swift).
extension WaymarkGlance {
    /// True for types sidewalk memory may speak (`WaymarkLine(for:)` exists); crosswalks and
    /// "other" are drawn dimmed on the map (plan 5.2: never spoken, still shown).
    public static func isSpoken(_ type: WaymarkLabelType) -> Bool { WaymarkLine(for: type) != nil }

    /// Month abbreviations for `imagery`, fixed (not the device locale).
    static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// "Street imagery from Oct 2018" from the bundle's `imagery_date` ("YYYY-MM"), or "… date
    /// unknown" when missing or malformed. The age is the point: labels come from old imagery.
    public static func imagery(_ yyyymm: String?) -> String {
        let unknown = "Street imagery date unknown"
        guard let s = yyyymm else { return unknown }
        let parts = s.split(separator: "-")
        guard parts.count == 2, parts[0].count == 4, let year = Int(parts[0]), let month = Int(parts[1]),
              (1...12).contains(month) else { return unknown }
        return "Street imagery from \(months[month - 1]) \(year)"
    }

    /// "Project Sidewalk votes: 5 agree · 5 disagree" (the prior's own validations).
    public static func votes(agree: Int, disagree: Int) -> String {
        "Project Sidewalk votes: \(agree) agree · \(disagree) disagree"
    }

    /// "50 % likely · Uncertain": the belief and its band.
    public static func confidence(_ p: Double) -> String {
        let band = WaymarkConfidenceBand(p: p).word
        guard let pc = percent(p) else { return band }
        return "\(pc) % likely · \(band)"
    }

    /// The same for VoiceOver: "89 percent likely, likely".
    public static func confidenceSpoken(_ p: Double) -> String {
        let band = WaymarkConfidenceBand(p: p).word.lowercased()
        guard let pc = percent(p) else { return band }
        return "\(pc) percent likely, \(band)"
    }

}

extension WaymarkSession {
    /// The current belief p of a label (prior plus decayed field evidence), nil for an unknown id.
    /// For the map of reports.
    public func confidence(of id: String, nowUTC: Double) -> Double? {
        guard let prior = prior(id) else { return nil }
        return (beliefs[id] ?? WaymarkBelief()).read(prior: prior, now: nowUTC).p
    }
}
