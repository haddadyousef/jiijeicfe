//
//  WaymarkAheadTests.swift
//  CaneKitLogicTests
//
//  Pins `WaymarkAhead` (design doc v1.0 §8.1, plan §7.3): only labels ahead of the walker, inside a
//  corridor along the direction of travel (the remaining route legs when a route runs, else the
//  smoothed heading), up to the look-ahead distance. Behind is excluded, beside is excluded,
//  closest first, and a walker standing still gets nothing.
//  Source pinned: `ios/Logic/Sources/CaneKitLogic/Waymark/WaymarkAhead.swift`.
//

import Foundation
import Testing
@testable import CaneKitLogic

private let origin = Coordinate(latitude: 47.6540, longitude: -122.3050)

/// Metres north / east of the origin → coordinate (equirectangular, fine at this scale).
private func at(north: Double, east: Double) -> Coordinate {
    let m = 6_371_000.0 * .pi / 180
    return Coordinate(latitude: origin.latitude + north / m,
                      longitude: origin.longitude + east / (m * cos(origin.latitude * .pi / 180)))
}

private func prior(_ n: Int, _ c: Coordinate) -> WaymarkPrior {
    WaymarkPrior(id: "ps:\(n)", type: .obstacle, lat: c.latitude, lng: c.longitude, severity: 2, tags: [],
                 nAgree: 1, nDisagree: 0, nUnsure: 0, clusterSize: 1, streetEdgeID: nil, intersectionID: nil,
                 osmWayID: nil, imageryDate: nil, labelDate: nil, sourceClusterID: n)
}

private func ids(_ hits: [WaymarkAhead.Hit]) -> [String] { hits.map { $0.prior.id } }

@Test func headingModeKeepsAheadAndDropsBehindAndBeside() {
    let labels = [prior(1, at(north: 20, east: 0)),    // ahead
                  prior(2, at(north: -10, east: 0)),   // behind
                  prior(3, at(north: 10, east: 20)),   // beside, outside the 12 m corridor
                  prior(4, at(north: 30, east: -8)),   // ahead, inside the corridor
                  prior(5, at(north: 50, east: 0))]    // beyond the 35 m look-ahead
    let hits = WaymarkAhead.select(from: labels, at: origin, speedMps: 1.2, headingDeg: 0, legs: nil)
    #expect(ids(hits) == ["ps:1", "ps:4"])
    #expect(abs(hits[0].alongM - 20) < 0.5 && abs(hits[0].crossM) < 0.5)
    #expect(abs(hits[1].alongM - 30) < 0.5 && abs(abs(hits[1].crossM) - 8) < 0.5)
}

@Test func headingIsRespectedNotJustNorth() {
    let labels = [prior(1, at(north: 0, east: 20)), prior(2, at(north: 20, east: 0))]
    #expect(ids(WaymarkAhead.select(from: labels, at: origin, speedMps: 1.2, headingDeg: 90, legs: nil)) == ["ps:1"])
}

@Test func standingStillReturnsNothing() {
    let labels = [prior(1, at(north: 10, east: 0))]
    #expect(WaymarkAhead.select(from: labels, at: origin, speedMps: 0.3, headingDeg: 0, legs: nil).isEmpty)
    #expect(WaymarkAhead.select(from: labels, at: origin, speedMps: -1, headingDeg: 0, legs: nil).isEmpty)
}

@Test func noDirectionReturnsNothing() {
    let labels = [prior(1, at(north: 10, east: 0))]
    #expect(WaymarkAhead.select(from: labels, at: origin, speedMps: 1.2, headingDeg: nil, legs: nil).isEmpty)
    #expect(WaymarkAhead.select(from: labels, at: origin, speedMps: 1.2, headingDeg: .nan, legs: []).isEmpty)
}

@Test func closestFirstThenByID() {
    let labels = [prior(3, at(north: 25, east: 1)), prior(2, at(north: 10, east: 0)), prior(1, at(north: 25, east: 1))]
    #expect(ids(WaymarkAhead.select(from: labels, at: origin, speedMps: 1.2, headingDeg: 0, legs: nil))
            == ["ps:2", "ps:1", "ps:3"])
}

@Test func routeLegsFollowTheTurn() {
    // Walk north 15 m to a corner, then east. A label 20 m east of the corner is ahead along the
    // route (15 + 20 = 35 m); a label straight on past the corner is not.
    let corner = at(north: 15, east: 0)
    let legs = [corner, at(north: 15, east: 60)]
    let labels = [prior(1, at(north: 15, east: 18)),   // after the turn, on the route
                  prior(2, at(north: 34, east: 0)),    // straight on past the corner: off route
                  prior(3, at(north: -5, east: 0))]    // behind the walker
    let hits = WaymarkAhead.select(from: labels, at: origin, speedMps: 1.2, headingDeg: 0, legs: legs)
    #expect(ids(hits) == ["ps:1"])
    #expect(abs(hits[0].alongM - 33) < 0.5)
}

@Test func routeLegsWinOverAHeadingThatPointsElsewhere() {
    let legs = [at(north: 0, east: 60)]                 // the route goes east
    let labels = [prior(1, at(north: 0, east: 20)), prior(2, at(north: 20, east: 0))]
    #expect(ids(WaymarkAhead.select(from: labels, at: origin, speedMps: 1.2, headingDeg: 0, legs: legs)) == ["ps:1"])
}

@Test func aLabelAtTheCornerIsCountedOnce() {
    let corner = at(north: 15, east: 0)
    let labels = [prior(1, corner)]
    let hits = WaymarkAhead.select(from: labels, at: origin, speedMps: 1.2, headingDeg: 0,
                                   legs: [corner, at(north: 15, east: 60)])
    #expect(ids(hits) == ["ps:1"])
    #expect(abs(hits[0].alongM - 15) < 0.5)
}

@Test func lookAheadAndCorridorAreThePlanDefaults() {
    #expect(WaymarkAhead.lookaheadMaxM == 35)
    #expect(WaymarkAhead.corridorHalfWidthM == 12)
    #expect(WaymarkAhead.minSpeedMps == 0.5)
}
