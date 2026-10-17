//
//  WaymarkAhead.swift
//  CaneKitLogic
//
//  Waymark L2: which prior labels are ahead of the walker. "Ahead" means: along the direction of
//  travel between 0 and `lookaheadMaxM`, and within `corridorHalfWidthM` of that line. The line is
//  the remaining route (walker → next waypoints) when a route runs, because a route turns and a
//  heading does not; otherwise the smoothed heading. No direction or no walking (speed below
//  `minSpeedMps`) means nothing is ahead, so a walker standing still is never warned.
//
//  Geometry: a local east/north plane centred on the walker (equirectangular, R = 6,371,000 m as in
//  `GeoMath`), accurate to centimetres over the 35 m that matter. On the route, each label takes
//  the leg it is closest to; on the first leg a label whose projection falls before the walker is
//  behind and excluded.
//  Constants are `[H]` (design doc v1.0 8.1 / M_NOTES §2), to tune after the first field walk.
//
//  Portability (plan 1.4): Foundation only; base-repo types used: `Coordinate`.
//  Pure. Tests: `WaymarkAheadTests.swift`.
//

import Foundation

/// Selects the labels ahead of the walker.
public enum WaymarkAhead {
    /// Farthest a label may be along the path, metres `[H]`.
    public static let lookaheadMaxM = 35.0
    /// Half-width of the corridor around the path, metres `[H]`. Wide because route legs are
    /// straight chords between waypoints and labels are geolocated from imagery.
    public static let corridorHalfWidthM = 12.0
    /// Below this ground speed the walker is treated as standing still, m/s (the base app's
    /// "not walking" bound).
    public static let minSpeedMps = 0.5

    /// One label ahead: how far along the path, and how far off it (signed, + = right of travel).
    public struct Hit: Sendable, Equatable {
        public let prior: WaymarkPrior
        public let alongM: Double
        public let crossM: Double
    }

    /// Metres per degree on the `GeoMath` sphere.
    static let metresPerDegree = 6_371_000.0 * .pi / 180

    /// A point in the walker-centred plane: x east, y north, metres.
    struct XY { let x: Double, y: Double }

    /// The labels ahead, closest along the path first, ties by id.
    /// - Parameters:
    ///   - candidates: labels to consider (usually `WaymarkIndex.within(lookahead + corridor)`).
    ///   - position: the walker.
    ///   - speedMps: ground speed; negative = invalid.
    ///   - headingDeg: direction of travel, degrees from true north, or nil.
    ///   - legs: the route ahead as points after the walker (next waypoint first), or nil / empty
    ///     when no route runs. Takes precedence over `headingDeg`.
    /// - Returns: the hits.
    public static func select(from candidates: [WaymarkPrior], at position: Coordinate, speedMps: Double,
                              headingDeg: Double?, legs: [Coordinate]?) -> [Hit] {
        guard speedMps.isFinite, speedMps >= minSpeedMps else { return [] }
        let cosLat = cos(position.latitude * .pi / 180)
        func xy(_ c: Coordinate) -> XY {
            XY(x: (c.longitude - position.longitude) * metresPerDegree * cosLat,
               y: (c.latitude - position.latitude) * metresPerDegree)
        }
        var hits: [Hit] = []
        if let legs, !legs.isEmpty {
            let path = [XY(x: 0, y: 0)] + legs.map(xy)
            for p in candidates {
                if let (along, cross) = project(xy(p.coordinate), on: path),
                   along >= 0, along <= lookaheadMaxM, abs(cross) <= corridorHalfWidthM {
                    hits.append(Hit(prior: p, alongM: along, crossM: cross))
                }
            }
        } else if let h = headingDeg, h.isFinite {
            let r = h * .pi / 180
            let (ux, uy) = (sin(r), cos(r))           // unit vector of travel
            for p in candidates {
                let q = xy(p.coordinate)
                let along = q.x * ux + q.y * uy
                let cross = q.x * uy - q.y * ux        // + = right of travel
                if along >= 0, along <= lookaheadMaxM, abs(cross) <= corridorHalfWidthM {
                    hits.append(Hit(prior: p, alongM: along, crossM: cross))
                }
            }
        } else {
            return []
        }
        hits.sort { $0.alongM != $1.alongM ? $0.alongM < $1.alongM : $0.prior.id < $1.prior.id }
        return hits
    }

    /// Projects `q` onto the polyline `path` (first point = the walker). Returns the along-path
    /// distance and signed cross-track distance for the leg nearest to `q`, or nil when `q` lies
    /// behind the walker and no later leg is nearer. Degenerate (zero-length) legs are skipped.
    static func project(_ q: XY, on path: [XY]) -> (along: Double, cross: Double)? {
        var best: (along: Double, cross: Double, dist: Double)?
        var walked = 0.0
        for i in 0..<(path.count - 1) {
            let a = path[i], b = path[i + 1]
            let dx = b.x - a.x, dy = b.y - a.y
            let len = (dx * dx + dy * dy).squareRoot()
            guard len > 1e-9 else { continue }
            let ux = dx / len, uy = dy / len
            let t = (q.x - a.x) * ux + (q.y - a.y) * uy   // metres along this leg
            if i == 0 && t < 0 { walked += len; continue } // behind the walker on the first leg
            let tc = min(max(t, 0), len)
            let px = a.x + ux * tc, py = a.y + uy * tc
            let dist = ((q.x - px) * (q.x - px) + (q.y - py) * (q.y - py)).squareRoot()
            let cross = (q.x - a.x) * uy - (q.y - a.y) * ux
            if best == nil || dist < best!.dist {
                best = (walked + tc, t >= 0 && t <= len ? cross : (cross < 0 ? -dist : dist), dist)
            }
            walked += len
        }
        return best.map { ($0.along, $0.cross) }
    }
}
