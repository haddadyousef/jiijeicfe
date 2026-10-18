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

/// Walk north through `path` (metres north at each fix), feeding `frames(north)` before each fix.
private func walk(_ t: inout WaymarkEvidenceTracker, labels: [WaymarkPrior], path: [Double],
                  frames: (Double) -> [WaymarkDepthSample], gatesAt: (Double) -> WaymarkEvidenceGates = { _ in gates() })
    -> [WaymarkEvidenceVerdict] {
    var out: [WaymarkEvidenceVerdict] = []
    for n in path {
        for f in frames(n) { t.add(f) }
        out += t.step(labels: labels, at: at(n), headingDeg: 0, legs: nil, gates: gatesAt(n))
    }
    return out
}

/// 1 m steps from `from` to `to` (inclusive).
private func metres(_ from: Double, _ to: Double) -> [Double] {
    stride(from: from, through: to, by: from <= to ? 1 : -1).map { $0 }
}

/// The window with 5 m GPS accuracy: 8 + 5 = 13 m; a full pass of a label at 20 m runs 0 → 40.
private let fullPass = metres(0, 40)

@Test func anObstacleSeenUnderTwoMetresIsConfirmed() {
    var t = WaymarkEvidenceTracker()
    let v = walk(&t, labels: [label(1, .obstacle, at(20))], path: fullPass) { n in [frame(torso: max(0.4, 20 - n))] }
    #expect(v.count == 1)
    #expect(v.first?.labelID == "ps:1" && v.first?.outcome == .confirmed && v.first?.sensor == .lidarTorso)
    // along_m is where the deciding reading was taken (review M1), not where the pass ended.
    #expect(abs((v.first?.alongM ?? 99) - 0) <= 1.01)
}

@Test func aConfirmationSurvivesTheLabelPositionError() {
    // The real obstacle is 5 m past the mapped point (label error 8 m): still confirmed (review B1).
    var t = WaymarkEvidenceTracker()
    let v = walk(&t, labels: [label(1, .obstacle, at(20))], path: fullPass) { n in [frame(torso: max(0.4, 25 - n))] }
    #expect(v.first?.outcome == .confirmed)
}

@Test func aHeadReadingCountsOnlyWithHeadCover() {
    var covered = WaymarkEvidenceTracker()
    let l = label(1, .obstacle, at(20))
    let yes = walk(&covered, labels: [l], path: fullPass) { n in [frame(head: max(0.4, 20 - n), headCover: true)] }
    #expect(yes.first?.outcome == .confirmed && yes.first?.sensor == .lidarHead)
    var blind = WaymarkEvidenceTracker()
    let no = walk(&blind, labels: [l], path: fullPass) { n in [frame(head: max(0.4, 20 - n), headCover: false)] }
    #expect(no.first?.outcome != .confirmed)
}

@Test func aCleanFullPassContradicts() {
    var t = WaymarkEvidenceTracker()
    let v = walk(&t, labels: [label(1, .obstacle, at(20))], path: fullPass) { _ in [frame(), frame(), frame()] }
    #expect(v.count == 1 && v.first?.outcome == .contradicted && v.first?.sensor == .lidarTorso)
}

@Test func aBetweenReadingIsUnverifiable() {
    var t = WaymarkEvidenceTracker()
    let v = walk(&t, labels: [label(1, .obstacle, at(20))], path: fullPass) { n in [frame(torso: max(2.2, 20 - n))] }
    #expect(v.first?.outcome == .unverifiable)
}

@Test func anUntrustedFrameSpoilsAContradictionButNotAConfirmation() {
    var t = WaymarkEvidenceTracker()
    let v = walk(&t, labels: [label(1, .obstacle, at(20))], path: fullPass) { n in [frame(trusted: n != 15), frame()] }
    #expect(v.first?.outcome == .unverifiable)
    var c = WaymarkEvidenceTracker()
    let w = walk(&c, labels: [label(1, .obstacle, at(20))], path: fullPass) { n in
        [frame(trusted: n != 15), frame(torso: max(0.5, 20 - n))] }
    #expect(w.first?.outcome == .confirmed)
}

@Test func untrustedCloseReadingsNeverConfirm() {
    var t = WaymarkEvidenceTracker()
    let v = walk(&t, labels: [label(1, .obstacle, at(20))], path: fullPass) { n in [frame(torso: max(0.4, 20 - n), trusted: false)] }
    #expect(v.first?.outcome == .unverifiable)
}

@Test func missingTorsoCoverSpoilsAContradiction() {
    var t = WaymarkEvidenceTracker()
    let v = walk(&t, labels: [label(1, .obstacle, at(20))], path: fullPass) { _ in [frame(torsoCover: false)] }
    #expect(v.first?.outcome == .unverifiable)
}

@Test func standingStillInsideTheWindowSpoilsAContradiction() {
    var t = WaymarkEvidenceTracker()
    let v = walk(&t, labels: [label(1, .obstacle, at(20))], path: fullPass, frames: { _ in [frame()] },
                 gatesAt: { n in gates(n != 16) })
    #expect(v.first?.outcome == .unverifiable)
}

@Test func aCloseReadingOutsideTheGatesDoesNotConfirm() {
    // Review H1: §9.2 gates apply to confirmations too (here: standing still at the label).
    var t = WaymarkEvidenceTracker()
    let v = walk(&t, labels: [label(1, .obstacle, at(20))], path: fullPass,
                 frames: { n in [frame(torso: n == 19 ? 1.0 : .infinity)] }, gatesAt: { n in gates(n != 19) })
    #expect(v.first?.outcome != .confirmed)
}

@Test func turningBackIsNeverAContradiction() {
    // Review B1: walk to 6 m short of the label, turn round, walk away.
    var t = WaymarkEvidenceTracker()
    let l = label(1, .obstacle, at(20))
    let v = walk(&t, labels: [l], path: metres(0, 14) + metres(13, 0)) { _ in [frame(), frame()] }
    #expect(!v.contains { $0.outcome == .contradicted })
    #expect(!t.routeEnded().contains { $0.outcome == .contradicted })
}

@Test func aPassThatStartedInsideTheWindowIsNotJudged() {
    // Review B1: the feature came on (or the bundle loaded) with the label already 5 m ahead.
    var t = WaymarkEvidenceTracker()
    let v = walk(&t, labels: [label(1, .obstacle, at(20))], path: metres(15, 40)) { _ in [frame(), frame()] }
    #expect(v.isEmpty)
}

@Test func aGPSJumpIsNeverAContradiction() {
    var t = WaymarkEvidenceTracker()
    let v = walk(&t, labels: [label(1, .obstacle, at(20))], path: metres(0, 14) + [45, 46]) { _ in [frame(), frame()] }
    #expect(!v.contains { $0.outcome == .contradicted })
}

@Test func aLabelToTheSideIsNotJudged() {
    // Review B2: LiDAR lanes see about ±1.5 m; a label 10 m to the side is neither confirmed nor contradicted.
    var t = WaymarkEvidenceTracker()
    let v = walk(&t, labels: [label(1, .obstacle, at(20, east: 10))], path: fullPass) { n in [frame(torso: 1.0)] }
    #expect(v.isEmpty)
}

@Test func onlyObstaclesGetLidarVerdicts() {
    var t = WaymarkEvidenceTracker()
    let v = walk(&t, labels: [label(1, .surfaceProblem, at(10)), label(2, .noSidewalk, at(12))], path: fullPass) { _ in [frame()] }
    #expect(v.isEmpty)
}

@Test func oneVerdictPerLabelPerRoute() {
    var t = WaymarkEvidenceTracker()
    let l = label(1, .obstacle, at(20))
    _ = walk(&t, labels: [l], path: fullPass) { n in [frame(torso: max(0.4, 20 - n))] }
    #expect(walk(&t, labels: [l], path: fullPass) { n in [frame(torso: max(0.4, 20 - n))] }.isEmpty)
    t.routeStarted()
    #expect(walk(&t, labels: [l], path: fullPass) { n in [frame(torso: max(0.4, 20 - n))] }.count == 1)
}

@Test func routeEndFlushesAnOpenPass() {
    var t = WaymarkEvidenceTracker()
    _ = walk(&t, labels: [label(1, .obstacle, at(20))], path: metres(0, 15)) { _ in [frame()] }
    let v = t.routeEnded()
    #expect(v.count == 1 && v.first?.outcome == .unverifiable && v.first?.reason == "route_end")
}

@Test func resetForgetsEverything() {
    // Review H2: the feature switched off mid-pass leaves nothing to judge later.
    var t = WaymarkEvidenceTracker()
    _ = walk(&t, labels: [label(1, .obstacle, at(20))], path: metres(0, 15)) { _ in [frame()] }
    t.reset()
    #expect(t.routeEnded().isEmpty)
}

@Test func aCurbEventConfirmsOnlyAMissingRampAhead() {
    // Review H4: a drop or step at a curb_ramp label is not evidence the ramp is there.
    let labels = [label(1, .missingCurbRamp, at(6)), label(3, .obstacle, at(5))]
    var t = WaymarkEvidenceTracker()
    let v = t.groundEvent(labels: labels, at: at(0), headingDeg: 0, legs: nil, gates: gates())
    #expect(v?.labelID == "ps:1" && v?.outcome == .confirmed && v?.sensor == .ground)
    var u = WaymarkEvidenceTracker()
    #expect(u.groundEvent(labels: [label(2, .curbRamp, at(6))], at: at(0), headingDeg: 0, legs: nil, gates: gates()) == nil)
    #expect(u.groundEvent(labels: [label(4, .missingCurbRamp, at(6))], at: at(0), headingDeg: 0, legs: nil, gates: gates(false)) == nil)
    #expect(u.groundEvent(labels: [label(5, .missingCurbRamp, at(6, east: 9))], at: at(0), headingDeg: 0, legs: nil, gates: gates()) == nil)
}

@Test func theSpotterTargetsTheNearestSpeakableLabelWithin15m() {
    let labels = [label(1, .obstacle, at(12)), label(2, .surfaceProblem, at(-4)), label(3, .crosswalk, at(1)),
                  label(4, .noSidewalk, at(40))]
    let target = WaymarkSpotter.target(labels: labels, at: at(0), headingDeg: 0)
    #expect(target?.prior.id == "ps:2")             // just passed, 4 m; crosswalk has no line
    #expect(abs((target?.alongM ?? 0) - -4) < 0.5)
    #expect(WaymarkSpotter.target(labels: [label(4, .noSidewalk, at(40))], at: at(0), headingDeg: 0) == nil)
}
