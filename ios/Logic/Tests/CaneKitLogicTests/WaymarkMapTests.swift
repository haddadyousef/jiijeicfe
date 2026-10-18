//
//  WaymarkMapTests.swift
//  CaneKitLogicTests
//
//  Pins the map of reports (judge demo, task 2): which labels are drawn (`WaymarkMapSelection`:
//  a corridor along the route plus a circle around the walker, de-duplicated, capped), the
//  confidence band each pin shows (`WaymarkConfidenceBand`: colour AND shape, so colour is never
//  the only cue), and the words of a tapped pin (`WaymarkGlance.imagery`, `.votes`, `.confidence`).
//  Source pinned: `ios/Logic/Sources/CaneKitLogic/Waymark/WaymarkMap.swift`, `WaymarkGlance.swift`.
//

import Foundation
import Testing
@testable import CaneKitLogic

private let origin = Coordinate(latitude: 47.6540, longitude: -122.3050)

private func at(north: Double, east: Double = 0) -> Coordinate {
    let m = 6_371_000.0 * .pi / 180
    return Coordinate(latitude: origin.latitude + north / m,
                      longitude: origin.longitude + east / (m * cos(origin.latitude * .pi / 180)))
}

private func prior(_ n: Int, _ c: Coordinate, _ type: WaymarkLabelType = .obstacle,
                   imagery: String? = "2019-05", agree: Int = 2, disagree: Int = 1) -> WaymarkPrior {
    WaymarkPrior(id: "ps:\(n)", type: type, lat: c.latitude, lng: c.longitude, severity: 2, tags: [],
                 nAgree: agree, nDisagree: disagree, nUnsure: 0, clusterSize: 1, streetEdgeID: nil,
                 intersectionID: nil, osmWayID: nil, imageryDate: imagery, labelDate: nil, sourceClusterID: n)
}

// MARK: - Selection

@Test func routeCorridorKeepsLabelsBesideTheRouteOnly() {
    // Route: 300 m north, then 200 m east. Corridor 25 m (both sidewalks + label error).
    let route = [at(north: 0), at(north: 300), at(north: 300, east: 200)]
    let index = WaymarkIndex([
        prior(1, at(north: 150, east: 20)),     // 20 m beside leg 1: in
        prior(2, at(north: 150, east: 30)),     // 30 m beside: out (a parallel street's sidewalk)
        prior(3, at(north: 320, east: 100)),    // 20 m beside leg 2: in
        prior(4, at(north: -20)),               // 20 m before the start: in (corridor, not "ahead")
        prior(5, at(north: 900)),               // far: out
    ])
    let ids = WaymarkMapSelection.labels(index: index, route: route, walker: nil).map(\.id)
    #expect(ids == ["ps:1", "ps:3", "ps:4"])
}

@Test func aLabelBetweenTwoSamplesOfALongSegmentIsFound() {
    // Review 12: worst case for the sampled queries — beside the midpoint between two 20 m samples.
    let route = [at(north: 0), at(north: 1000)]
    let index = WaymarkIndex([prior(1, at(north: 510, east: 24.9))])
    #expect(WaymarkMapSelection.labels(index: index, route: route, walker: nil).map(\.id) == ["ps:1"])
}

@Test func withoutARouteTheWalkersCircleIsUsed() {
    let index = WaymarkIndex([prior(1, at(north: 200)), prior(2, at(north: 260)), prior(3, at(north: -100))])
    let ids = WaymarkMapSelection.labels(index: index, route: [], walker: at(north: 0)).map(\.id)
    #expect(ids == ["ps:1", "ps:3"])
}

@Test func withARouteTheWalkersCircleIsNotAdded() {
    // Judge-demo shot: a 250 m circle around the route start filled the map with side streets.
    let route = [at(north: 0), at(north: 100)]
    let index = WaymarkIndex([prior(1, at(north: 50, east: 10)), prior(2, at(north: 0, east: -200))])
    let ids = WaymarkMapSelection.labels(index: index, route: route, walker: at(north: 0)).map(\.id)
    #expect(ids == ["ps:1"])
}

@Test func capWithARouteAndNoWalkerKeepsThoseNearestTheRouteStart() {
    var labels: [WaymarkPrior] = []
    for i in 0..<(WaymarkMapSelection.maxPins + 10) { labels.append(prior(i, at(north: Double(i) * 0.4))) }
    let route = [at(north: 0), at(north: 400)]
    let picked = WaymarkMapSelection.labels(index: WaymarkIndex(labels), route: route, walker: nil)
    #expect(picked.count == WaymarkMapSelection.maxPins)
    #expect(picked.contains { $0.id == "ps:0" })
    #expect(!picked.contains { $0.id == "ps:\(WaymarkMapSelection.maxPins + 9)" })
}

@Test func selectionIsCappedNearestTheWalkerFirst() {
    var labels: [WaymarkPrior] = []
    for i in 0..<(WaymarkMapSelection.maxPins + 50) { labels.append(prior(i, at(north: Double(i) * 0.4))) }
    let picked = WaymarkMapSelection.labels(index: WaymarkIndex(labels), route: [], walker: at(north: 0))
    #expect(picked.count == WaymarkMapSelection.maxPins)
    // The farthest ones were dropped.
    #expect(!picked.contains { $0.id == "ps:\(WaymarkMapSelection.maxPins + 49)" })
    #expect(picked.contains { $0.id == "ps:0" })
}

@Test func nothingToDrawWithoutRouteOrWalker() {
    #expect(WaymarkMapSelection.labels(index: WaymarkIndex([prior(1, origin)]), route: [], walker: nil).isEmpty)
}

// MARK: - Bands

@Test func bandsSplitAtTheirEdges() {
    // Review 1: the band follows the percent the screen shows, so "70 %" is never "Uncertain".
    #expect(WaymarkConfidenceBand(p: 0.70) == .likely)
    #expect(WaymarkConfidenceBand(p: 0.695) == .likely)        // shown as 70 %
    #expect(WaymarkConfidenceBand(p: 0.6949) == .uncertain)    // shown as 69 %
    #expect(WaymarkConfidenceBand(p: 0.40) == .uncertain)
    #expect(WaymarkConfidenceBand(p: 0.395) == .uncertain)     // shown as 40 %
    #expect(WaymarkConfidenceBand(p: 0.3949) == .doubtful)     // shown as 39 %
    #expect(WaymarkConfidenceBand(p: 1) == .likely)
    #expect(WaymarkConfidenceBand(p: 0) == .doubtful)
    #expect(WaymarkConfidenceBand(p: .nan) == .uncertain)
}

@Test func eachBandHasItsOwnWordAndShape() {
    let bands = WaymarkConfidenceBand.allCases
    #expect(Set(bands.map(\.word)).count == bands.count)
    #expect(Set(bands.map(\.shape)).count == bands.count)
    #expect(WaymarkConfidenceBand.likely.word == "Likely")
}

@Test func onlySpokenTypesAreDrawnFull() {
    #expect(WaymarkGlance.isSpoken(.obstacle))
    #expect(WaymarkGlance.isSpoken(.curbRamp))
    #expect(!WaymarkGlance.isSpoken(.crosswalk))
    #expect(!WaymarkGlance.isSpoken(.other))
}

// MARK: - Pin words

@Test func imageryDateInWords() {
    #expect(WaymarkGlance.imagery("2018-10") == "Street imagery from Oct 2018")
    #expect(WaymarkGlance.imagery("2019-01") == "Street imagery from Jan 2019")
    #expect(WaymarkGlance.imagery(nil) == "Street imagery date unknown")
    #expect(WaymarkGlance.imagery("2019-13") == "Street imagery date unknown")
    #expect(WaymarkGlance.imagery("soon") == "Street imagery date unknown")
}

@Test func votesInWords() {
    #expect(WaymarkGlance.votes(agree: 5, disagree: 5) == "Project Sidewalk votes: 5 agree · 5 disagree")
    #expect(WaymarkGlance.votes(agree: 1, disagree: 0) == "Project Sidewalk votes: 1 agree · 0 disagree")
}

@Test func confidenceInWords() {
    #expect(WaymarkGlance.confidence(0.5) == "50 % likely · Uncertain")
    #expect(WaymarkGlance.confidence(0.889) == "89 % likely · Likely")
    #expect(WaymarkGlance.confidenceSpoken(0.889) == "89 percent likely, likely")
}

@Test func sessionReportsTheCurrentConfidenceOfALabel() {
    let s = WaymarkSession(priors: WaymarkPriorSet(generatedAt: "x", sourceName: "SYNTHETIC test",
                                                   bboxLngLat: [-123, 47, -122, 48],
                                                   labels: [prior(1, origin, agree: 5, disagree: 5)]))
    #expect(abs((s.confidence(of: "ps:1", nowUTC: 0) ?? 0) - 0.5) < 1e-12)
    #expect(s.confidence(of: "ps:404", nowUTC: 0) == nil)
}
