//
//  WaymarkBeliefTests.swift
//  CaneKitLogicTests
//
//  Pins `WaymarkBelief` and `WaymarkThreshold` to WAYMARK_PLAN v1.1 §5.3 and §5.4, which are
//  normative (D-16): Python and Swift must agree to 1e-9. Every row of the plan's worked table is
//  a test. When `waymark/contracts/golden/belief_vectors.json` lands, a test reads it too.
//  Sources pinned: `ios/Logic/Sources/CaneKitLogic/Waymark/WaymarkBelief.swift`.
//

import Foundation
import Testing
@testable import CaneKitLogic

private let day = 86_400.0
private let t0 = 1_792_200_000.0   // 2026-10-17-ish, UTC seconds; any fixed value works

private func prior(_ type: WaymarkLabelType, agree: Int, disagree: Int) -> WaymarkPrior {
    WaymarkPrior(id: "ps:1", type: type, lat: 47.654, lng: -122.305, severity: 2, tags: [],
                 nAgree: agree, nDisagree: disagree, nUnsure: 0, clusterSize: 1, streetEdgeID: nil,
                 intersectionID: nil, osmWayID: nil, imageryDate: nil, labelDate: nil, sourceClusterID: 1)
}

private func close(_ x: Double, _ y: Double, tol: Double = 1e-9) -> Bool { abs(x - y) <= tol }

// MARK: Plan 5.3 worked table, obstacle rows

@Test func obstaclePriorOnly() {
    let r = WaymarkBelief().read(prior: prior(.obstacle, agree: 2, disagree: 0), now: t0)
    #expect(close(r.a, 3) && close(r.b, 1) && close(r.p, 0.75))
    #expect(close(r.nEff, 2))
}

@Test func obstacleSpotterContradictedAtT0() {
    let p = prior(.obstacle, agree: 2, disagree: 0)
    var b = WaymarkBelief()
    b.update(.contradicted, sensor: .spotter, type: p.type, now: t0)
    let r = b.read(prior: p, now: t0)
    #expect(close(r.a, 3) && close(r.b, 3) && close(r.p, 0.5))
    #expect(b.tLast == t0)
}

@Test func obstacleContradictionDecaysWithASixtyDayHalfLife() {
    let p = prior(.obstacle, agree: 2, disagree: 0)
    var b = WaymarkBelief()
    b.update(.contradicted, sensor: .spotter, type: p.type, now: t0)
    let r60 = b.read(prior: p, now: t0 + 60 * day)
    #expect(close(r60.a, 3) && close(r60.b, 2) && close(r60.p, 0.6))
    let r120 = b.read(prior: p, now: t0 + 120 * day)
    #expect(close(r120.a, 3) && close(r120.b, 1.5) && close(r120.p, 3 / 4.5))
    #expect(close(r120.p, 0.666667, tol: 1e-6))
    // Reading never changes the state.
    #expect(b.tLast == t0 && b.eB == 2)
}

// MARK: Plan 5.3 worked table, missing curb ramp rows

@Test func missingCurbRampPriorThenLidarThenSpotter() {
    let p = prior(.missingCurbRamp, agree: 1, disagree: 1)
    var b = WaymarkBelief()
    let r0 = b.read(prior: p, now: t0)
    #expect(close(r0.a, 2) && close(r0.b, 2) && close(r0.p, 0.5))
    b.update(.confirmed, sensor: .lidarTorso, type: p.type, now: t0)
    let r1 = b.read(prior: p, now: t0)
    #expect(close(r1.a, 3) && close(r1.b, 2) && close(r1.p, 0.6))
    b.update(.confirmed, sensor: .spotter, type: p.type, now: t0)
    let r2 = b.read(prior: p, now: t0)
    #expect(close(r2.a, 5) && close(r2.b, 2) && close(r2.p, 5.0 / 7.0))
    #expect(close(r2.p, 0.714286, tol: 1e-6))
}

// MARK: Rules

@Test func unverifiableChangesNothingIncludingTLast() {
    var b = WaymarkBelief()
    b.update(.confirmed, sensor: .ground, type: .obstacle, now: t0)
    let before = b
    b.update(.unverifiable, sensor: .spotter, type: .obstacle, now: t0 + 30 * day)
    #expect(b == before)
    // And on a fresh belief it does not start the clock.
    var fresh = WaymarkBelief()
    fresh.update(.unverifiable, sensor: .lidarTorso, type: .obstacle, now: t0)
    #expect(fresh.tLast == nil && fresh.eA == 0 && fresh.eB == 0)
}

@Test func anUpdateDecaysFirstThenAdds() {
    var b = WaymarkBelief()
    b.update(.confirmed, sensor: .spotter, type: .obstacle, now: t0)          // eA = 2
    b.update(.confirmed, sensor: .lidarTorso, type: .obstacle, now: t0 + 60 * day)  // 2 → 1, + 1
    #expect(close(b.eA, 2) && b.tLast == t0 + 60 * day)
}

@Test func zeroElapsedTimeDoesNotDecay() {
    var b = WaymarkBelief()
    b.update(.contradicted, sensor: .vision, type: .surfaceProblem, now: t0)
    #expect(close(b.read(prior: prior(.surfaceProblem, agree: 0, disagree: 0), now: t0).b, 1.5))
}

@Test func aReadBeforeTLastDoesNotGrowEvidence() {
    // dt = max(0, now − tLast): a clock that steps backwards must not inflate the mass.
    var b = WaymarkBelief()
    b.update(.confirmed, sensor: .spotter, type: .obstacle, now: t0)
    #expect(close(b.read(prior: prior(.obstacle, agree: 0, disagree: 0), now: t0 - 10 * day).a, 3))
}

@Test func halfLivesAndWeightsMatchThePlan() {
    #expect(WaymarkBelief.halfLifeDays(.obstacle) == 60)
    #expect(WaymarkBelief.halfLifeDays(.surfaceProblem) == 120)
    for t in [WaymarkLabelType.curbRamp, .missingCurbRamp, .noSidewalk, .crosswalk, .other] {
        #expect(WaymarkBelief.halfLifeDays(t) == 365)
    }
    #expect(WaymarkBelief.weight(.spotter) == 2.0)
    #expect(WaymarkBelief.weight(.lidarTorso) == 1.0)
    #expect(WaymarkBelief.weight(.lidarHead) == 1.0)
    #expect(WaymarkBelief.weight(.ground) == 0.5)
    #expect(WaymarkBelief.weight(.vision) == 0.5)
}

@Test func evidenceDecaysTowardThePriorNotToZeroConfidence() {
    // After many half-lives the belief is the prior again.
    let p = prior(.obstacle, agree: 2, disagree: 0)
    var b = WaymarkBelief()
    b.update(.contradicted, sensor: .spotter, type: p.type, now: t0)
    #expect(close(b.read(prior: p, now: t0 + 6_000 * day).p, 0.75, tol: 1e-9))
}

@Test func sensorAndOutcomeRawValuesAreTheEvidenceContract() {
    #expect(WaymarkSensor.allCases.map(\.rawValue) == ["spotter", "lidar_torso", "lidar_head", "ground", "vision"])
    #expect(WaymarkOutcome.allCases.map(\.rawValue) == ["confirmed", "contradicted", "unverifiable"])
}

@Test func beliefRoundTripsThroughJSON() throws {
    var b = WaymarkBelief()
    b.update(.confirmed, sensor: .spotter, type: .obstacle, now: t0)
    let back = try JSONDecoder().decode(WaymarkBelief.self, from: JSONEncoder().encode(b))
    #expect(back == b)
}

// MARK: Plan 5.4 thresholds

@Test func thresholdFormulaAndThePlansFourValues() {
    #expect(abs(WaymarkThreshold.tau(costMiss: 5, costFalseAlarm: 1) - 1.0 / 6.0) <= 1e-12)
    #expect(abs(WaymarkThreshold.tau(for: .obstacle)! - 1.0 / 6.0) <= 1e-12)
    #expect(abs(WaymarkThreshold.tau(for: .missingCurbRamp)! - 0.2) <= 1e-12)
    #expect(abs(WaymarkThreshold.tau(for: .noSidewalk)! - 0.2) <= 1e-12)
    #expect(abs(WaymarkThreshold.tau(for: .surfaceProblem)! - 1.0 / 3.0) <= 1e-12)
}

@Test func informationalTypesHaveNoThreshold() {
    #expect(WaymarkThreshold.tau(for: .curbRamp) == nil)
    #expect(WaymarkThreshold.tau(for: .crosswalk) == nil)
    #expect(WaymarkThreshold.tau(for: .other) == nil)
}

@Test func thresholdFallsAsAMissCostsMore() {
    var last = 1.0
    for miss in stride(from: 0.5, through: 20, by: 0.5) {
        let tau = WaymarkThreshold.tau(costMiss: miss, costFalseAlarm: 1)
        #expect(tau < last)
        #expect(tau > 0 && tau < 1)
        last = tau
    }
}
