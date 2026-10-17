//
//  WaymarkIndexTests.swift
//  CaneKitLogicTests
//
//  Pins `WaymarkIndex` (WAYMARK_PLAN v1.1 §7.3): a grid lookup must return exactly what a brute-force
//  scan over every label returns, in the same order (distance, then id), including labels that sit
//  exactly on a cell edge. A miss here is a hazard the walker is never warned about.
//  Source pinned: `ios/Logic/Sources/CaneKitLogic/Waymark/WaymarkIndex.swift`.
//  Seeded LCG (no Foundation RNG), so macOS and Linux see the same "random" sets.
//

import Foundation
import Testing
@testable import CaneKitLogic

/// Deterministic generator in [0, 1) (Knuth MMIX constants, top 53 bits).
private struct LCG {
    var state: UInt64
    mutating func unit() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53)
    }
}

/// A label at `lat`, `lng` with id `ps:<n>`.
private func prior(_ n: Int, _ lat: Double, _ lng: Double, _ type: WaymarkLabelType = .obstacle) -> WaymarkPrior {
    WaymarkPrior(id: "ps:\(n)", type: type, lat: lat, lng: lng, severity: 2, tags: [], nAgree: 1, nDisagree: 0,
                 nUnsure: 0, clusterSize: 1, streetEdgeID: nil, intersectionID: nil, osmWayID: nil,
                 imageryDate: nil, labelDate: nil, sourceClusterID: n)
}

/// The reference answer: every label within `r` metres of `c`, closest first, ties by id.
private func bruteForce(_ labels: [WaymarkPrior], _ r: Double, _ c: Coordinate) -> [String] {
    var hits: [(id: String, d: Double)] = []
    for p in labels {
        let d: Double = GeoMath.distanceMeters(c, p.coordinate)
        if d <= r { hits.append((id: p.id, d: d)) }
    }
    hits.sort { (x: (id: String, d: Double), y: (id: String, d: Double)) -> Bool in
        x.d != y.d ? x.d < y.d : x.id < y.id
    }
    return hits.map { $0.id }
}

@Test func indexEqualsBruteForceOnSeededRandomSets() {
    for seed in UInt64(1)...UInt64(20) {
        var rng = LCG(state: seed)
        // Seattle University District, about 1.1 km × 0.8 km.
        let labels = (1...400).map { n in prior(n, 47.650 + rng.unit() * 0.010, -122.312 + rng.unit() * 0.012) }
        let index = WaymarkIndex(labels)
        for _ in 0..<25 {
            let c = Coordinate(latitude: 47.649 + rng.unit() * 0.012, longitude: -122.313 + rng.unit() * 0.014)
            let r = 5 + rng.unit() * 120
            #expect(index.within(r, of: c).map(\.id) == bruteForce(labels, r, c), "seed \(seed) r \(r)")
        }
    }
}

@Test func emptyIndexReturnsNothing() {
    #expect(WaymarkIndex([]).within(500, of: Coordinate(latitude: 47.654, longitude: -122.305)).isEmpty)
}

@Test func labelsExactlyOnCellEdgesAreFound() {
    let cell = WaymarkIndex.cellDegrees
    // Points on grid lines and grid corners around the query point.
    let base = (47.654 / cell).rounded() * cell
    let baseLng = (-122.305 / cell).rounded() * cell
    let labels = [prior(1, base, baseLng), prior(2, base + cell, baseLng), prior(3, base, baseLng - cell),
                  prior(4, base - cell, baseLng + cell), prior(5, base + 2 * cell, baseLng + 2 * cell)]
    let index = WaymarkIndex(labels)
    for c in labels.map(\.coordinate) + [Coordinate(latitude: base + cell / 2, longitude: baseLng + cell / 2)] {
        for r in [0.0, 1, 40, 60, 80, 150] {
            #expect(index.within(r, of: c).map(\.id) == bruteForce(labels, r, c))
        }
    }
}

@Test func radiusZeroFindsOnlyALabelAtThePoint() {
    let labels = [prior(1, 47.654, -122.305), prior(2, 47.6541, -122.305)]
    #expect(WaymarkIndex(labels).within(0, of: labels[0].coordinate).map(\.id) == ["ps:1"])
}

@Test func resultsAreClosestFirstThenByID() {
    // Two labels at the same point: the tie breaks by id.
    let labels = [prior(3, 47.6545, -122.305), prior(2, 47.6545, -122.305), prior(1, 47.6550, -122.305)]
    let ids = WaymarkIndex(labels).within(200, of: Coordinate(latitude: 47.654, longitude: -122.305)).map(\.id)
    #expect(ids == ["ps:2", "ps:3", "ps:1"])
}

@Test func negativeOrNonFiniteRadiusReturnsNothing() {
    let index = WaymarkIndex([prior(1, 47.654, -122.305)])
    let c = Coordinate(latitude: 47.654, longitude: -122.305)
    #expect(index.within(-1, of: c).isEmpty)
    #expect(index.within(.nan, of: c).isEmpty)
    #expect(index.within(.infinity, of: c).isEmpty)
}
