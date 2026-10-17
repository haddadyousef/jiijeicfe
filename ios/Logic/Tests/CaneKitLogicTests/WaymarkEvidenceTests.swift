//
//  WaymarkEvidenceTests.swift
//  CaneKitLogicTests
//
//  Pins E1 (design doc §9): how a walk past a label turns into one `waymark.evidence.v1` outcome.
//  LiDAR passes for obstacles (§9.1 row 1, gates §9.2), ground curb events for curb-ramp labels,
//  and the spotter's nearest-label rule (§9.3). Source: `WaymarkEvidence.swift`.
//

import Foundation
import Testing
@testable import CaneKitLogic

private let o = Coordinate(latitude: 47.6540, longitude: -122.3050)
private func at(_ north: Double, east: Double = 0) -> Coordinate {
    let m = 6_371_000.0 * .pi / 180
    return Coordinate(latitude: o.latitude + north / m, longitude: o.longitude + east / (m * cos(o.latitude * .pi / 180)))
}
private func label(_ n: Int, _ t: WaymarkLabelType, _ c: Coordinate) -> WaymarkPrior {
    WaymarkPrior(id: "ps:\(n)", type: t, lat: c.latitude, lng: c.longitude, severity: 2, tags: [], nAgree: 1,
                 nDisagree: 0, nUnsure: 0, clusterSize: 1, streetEdgeID: nil, intersectionID: nil, osmWayID: nil,
                 imageryDate: nil, labelDate: nil, sourceClusterID: n)
}
private func frame(torso: Double = .infinity, head: Double = .infinity, trusted: Bool = true,
                   torsoCover: Bool = true, headCover: Bool = false) -> WaymarkDepthSample {
    WaymarkDepthSample(trusted: trusted, torsoMinM: torso, headMinM: head, torsoCover: torsoCover,
                       headCover: headCover, tiltDeg: 5)
}
private func gates(_ ok: Bool = true) -> WaymarkEvidenceGates {
    WaymarkEvidenceGates(speedMps: ok ? 1.3 : 0.2, gpsAccuracyM: 5, fixFresh: true)
}

/// Walk north from 0 to `to` metres in 1 m steps, feeding `frames(northNow)` before each fix.
private func walk(_ t: inout WaymarkEvidenceTracker, labels: [WaymarkPrior], to: Double,
                  frames: (Double) -> [WaymarkDepthSample], gatesAt: (Double) -> WaymarkEvidenceGates = { _ in gates() })
    -> [WaymarkEvidenceVerdict] {
    var out: [WaymarkEvidenceVerdict] = []
    var n = 0.0
    while n <= to {
        for f in frames(n) { t.add(f) }
        out += t.step(labels: labels, at: at(n), headingDeg: 0, legs: nil, gates: gatesAt(n))
        n += 1
    }
    return out
}

@Test func anObstacleSeenUnderTwoMetresIsConfirmed() {
    var t = WaymarkEvidenceTracker()
    let l = label(1, .obstacle, at(20))
    let v = walk(&t, labels: [l], to: 30) { n in [frame(torso: 20 - n)] }
    #expect(v.count == 1)
    #expect(v.first?.labelID == "ps:1" && v.first?.outcome == .confirmed && v.first?.sensor == .lidarTorso)
}

@Test func aHeadReadingCountsOnlyWithHeadCover() {
    var covered = WaymarkEvidenceTracker()
    let l = label(1, .obstacle, at(20))
    let yes = walk(&covered, labels: [l], to: 30) { n in [frame(head: 20 - n, headCover: true)] }
    #expect(yes.first?.outcome == .confirmed && yes.first?.sensor == .lidarHead)
    var blind = WaymarkEvidenceTracker()
    let no = walk(&blind, labels: [l], to: 30) { n in [frame(head: 20 - n, headCover: false)] }
    #expect(no.first?.outcome != .confirmed)
}

@Test func aCleanEmptyPassContradicts() {
    var t = WaymarkEvidenceTracker()
    let v = walk(&t, labels: [label(1, .obstacle, at(20))], to: 30) { _ in [frame(), frame(), frame()] }
    #expect(v.count == 1 && v.first?.outcome == .contradicted && v.first?.sensor == .lidarTorso)
}

@Test func aBetweenReadingIsUnverifiable() {
    // 2.2 m is above the 2.0 m confirm bar and below the 2.5 m clear bar: no claim either way.
    var t = WaymarkEvidenceTracker()
    let v = walk(&t, labels: [label(1, .obstacle, at(20))], to: 30) { n in [frame(torso: max(2.2, 20 - n))] }
    #expect(v.first?.outcome == .unverifiable)
}

@Test func anUntrustedFrameSpoilsAContradictionButNotAConfirmation() {
    var t = WaymarkEvidenceTracker()
    let v = walk(&t, labels: [label(1, .obstacle, at(20))], to: 30) { n in [frame(trusted: n != 15)] }
    #expect(v.first?.outcome == .unverifiable)
    var c = WaymarkEvidenceTracker()
    let w = walk(&c, labels: [label(1, .obstacle, at(20))], to: 30) { n in
        [frame(trusted: n != 15), frame(torso: max(0.5, 20 - n))] }
    #expect(w.first?.outcome == .confirmed)
}

@Test func untrustedCloseReadingsNeverConfirm() {
    var t = WaymarkEvidenceTracker()
    let v = walk(&t, labels: [label(1, .obstacle, at(20))], to: 30) { n in [frame(torso: 20 - n, trusted: false)] }
    #expect(v.first?.outcome == .unverifiable)
}

@Test func missingTorsoCoverSpoilsAContradiction() {
    var t = WaymarkEvidenceTracker()
    let v = walk(&t, labels: [label(1, .obstacle, at(20))], to: 30) { _ in [frame(torsoCover: false)] }
    #expect(v.first?.outcome == .unverifiable)
}

@Test func standingStillInsideTheWindowSpoilsAContradiction() {
    // §9.2: evidence counts only while walking. A stop inside the window makes the pass unverifiable.
    var t = WaymarkEvidenceTracker()
    let v = walk(&t, labels: [label(1, .obstacle, at(20))], to: 30, frames: { _ in [frame()] },
                 gatesAt: { n in gates(n != 16) })
    #expect(v.first?.outcome == .unverifiable)
}

@Test func onlyObstaclesGetLidarVerdicts() {
    var t = WaymarkEvidenceTracker()
    let v = walk(&t, labels: [label(1, .surfaceProblem, at(10)), label(2, .noSidewalk, at(12))], to: 30) { _ in [frame()] }
    #expect(v.isEmpty)
}

@Test func oneVerdictPerLabelPerRoute() {
    var t = WaymarkEvidenceTracker()
    let l = label(1, .obstacle, at(20))
    _ = walk(&t, labels: [l], to: 30) { n in [frame(torso: 20 - n)] }
    #expect(walk(&t, labels: [l], to: 30) { n in [frame(torso: 20 - n)] }.isEmpty)
    t.routeStarted()
    #expect(walk(&t, labels: [l], to: 30) { n in [frame(torso: 20 - n)] }.count == 1)
}

@Test func routeEndFlushesAnOpenPass() {
    var t = WaymarkEvidenceTracker()
    let l = label(1, .obstacle, at(20))
    _ = walk(&t, labels: [l], to: 15) { _ in [frame()] }     // inside the window, not past it
    let v = t.routeEnded()
    #expect(v.count == 1 && v.first?.outcome == .unverifiable)
}

@Test func aCurbEventConfirmsTheNearestRampLabel() {
    let labels = [label(1, .missingCurbRamp, at(6)), label(2, .curbRamp, at(30)), label(3, .obstacle, at(5))]
    var t = WaymarkEvidenceTracker()
    let v = t.groundEvent(labels: labels, at: at(0), headingDeg: 0, legs: nil, speedMps: 1.3)
    #expect(v?.labelID == "ps:1" && v?.outcome == .confirmed && v?.sensor == .ground)
    #expect(t.groundEvent(labels: [label(2, .curbRamp, at(30))], at: at(0), headingDeg: 0, legs: nil, speedMps: 1.3) == nil)
}

@Test func theSpotterTargetsTheNearestSpeakableLabelWithin15m() {
    let labels = [label(1, .obstacle, at(12)), label(2, .surfaceProblem, at(-4)), label(3, .crosswalk, at(1)),
                  label(4, .noSidewalk, at(40))]
    let target = WaymarkSpotter.target(labels: labels, at: at(0), headingDeg: 0)
    #expect(target?.prior.id == "ps:2")             // just passed, 4 m; crosswalk has no line
    #expect(abs((target?.alongM ?? 0) - -4) < 0.5)
    #expect(WaymarkSpotter.target(labels: [label(4, .noSidewalk, at(40))], at: at(0), headingDeg: 0) == nil)
}
