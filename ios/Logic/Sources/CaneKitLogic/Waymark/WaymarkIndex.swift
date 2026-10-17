//
//  WaymarkIndex.swift
//  CaneKitLogic
//
//  Waymark L1: radius lookup over the prior labels. The bundle may hold up to 20,000 labels and the
//  engine asks on every GPS fix (about 1 Hz), so a linear scan per fix is avoided with a uniform
//  latitude/longitude grid.
//
//  Contract (pinned by `indexEqualsBruteForceOnSeededRandomSets`): `within(r, of: c)` returns
//  exactly the labels a brute-force scan returns (`GeoMath.distanceMeters(c, label) <= r`), in the
//  same order: closest first, ties by id. The grid only chooses which labels to measure; the
//  final test is always the exact haversine distance, so a cell-size or cell-edge mistake can only
//  cost time, never a missed label, as long as the cell span covers the radius (it does: the span
//  is derived from the same earth radius `GeoMath` uses, plus one extra cell on every side).
//
//  Portability (plan 1.4): Foundation only; base-repo types used: `Coordinate`, `GeoMath`.
//  Pure: no clock, no I/O. Tests: `WaymarkIndexTests.swift`.
//

import Foundation

/// An immutable grid index over prior labels.
public struct WaymarkIndex: Sendable {
    /// Cell size in degrees of latitude and of longitude (about 55 m north–south, 37 m east–west
    /// in Seattle). `[H]` from plan 7.3; any value is correct, only speed depends on it.
    public static let cellDegrees = 0.0005

    /// Metres per degree of latitude on the sphere `GeoMath` uses (R = 6,371,000 m).
    static let metresPerDegree = 6_371_000.0 * .pi / 180

    /// A grid cell: floor(lat / cell), floor(lng / cell).
    struct Cell: Hashable, Sendable { let row: Int, col: Int }

    /// Labels by cell.
    private let cells: [Cell: [WaymarkPrior]]
    /// Every label, for `count` and tests.
    public let count: Int

    /// Builds the index. O(n).
    /// - Parameter labels: the bundle's labels (already validated by `WaymarkPriorSet.decode`).
    public init(_ labels: [WaymarkPrior]) {
        var cells: [Cell: [WaymarkPrior]] = [:]
        for p in labels { cells[Self.cell(lat: p.lat, lng: p.lng), default: []].append(p) }
        self.cells = cells
        self.count = labels.count
    }

    /// The cell holding a point.
    static func cell(lat: Double, lng: Double) -> Cell {
        Cell(row: Int((lat / cellDegrees).rounded(.down)), col: Int((lng / cellDegrees).rounded(.down)))
    }

    /// Every label within `radiusM` metres of `c` (great-circle), closest first, ties by id.
    /// - Parameters:
    ///   - radiusM: search radius in metres; negative or non-finite gives `[]`.
    ///   - c: the query point.
    /// - Returns: matching labels in distance order.
    public func within(_ radiusM: Double, of c: Coordinate) -> [WaymarkPrior] {
        guard radiusM.isFinite, radiusM >= 0, count > 0 else { return [] }
        let dLat = radiusM / Self.metresPerDegree
        // Longitude degrees shrink with cos(latitude); take the widest row the circle can touch.
        let maxAbsLat = min(89.0, abs(c.latitude) + dLat)
        let dLng = radiusM / (Self.metresPerDegree * cos(maxAbsLat * .pi / 180))
        let lo = Self.cell(lat: c.latitude - dLat, lng: c.longitude - dLng)
        let hi = Self.cell(lat: c.latitude + dLat, lng: c.longitude + dLng)
        var hits: [(prior: WaymarkPrior, d: Double)] = []
        for row in (lo.row - 1)...(hi.row + 1) {
            for col in (lo.col - 1)...(hi.col + 1) {
                guard let bucket = cells[Cell(row: row, col: col)] else { continue }
                for p in bucket {
                    let d = GeoMath.distanceMeters(c, p.coordinate)
                    if d <= radiusM { hits.append((p, d)) }
                }
            }
        }
        hits.sort { $0.d != $1.d ? $0.d < $1.d : $0.prior.id < $1.prior.id }
        return hits.map(\.prior)
    }
}
