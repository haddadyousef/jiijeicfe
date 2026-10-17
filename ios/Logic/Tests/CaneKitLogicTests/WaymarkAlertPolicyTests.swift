//
//  WaymarkAlertPolicyTests.swift
//  CaneKitLogicTests
//
//  Pins Waymark L3: the fixed spoken lines (`WaymarkLines`, design doc Appendix A) and the cue
//  policy (`WaymarkAlertPolicy`, design doc 8.1 / 8.3 as amended by WAYMARK_PLAN 5.2 and 5.4).
//  One test per rule. Waymark speaks rarely and only as a report ("Reported …"), never a detection,
//  and it never talks over the base app's safety channel.
//  Sources pinned: `ios/Logic/Sources/CaneKitLogic/Waymark/WaymarkLines.swift`, `WaymarkAlertPolicy.swift`.
//

import Foundation
import Testing
@testable import CaneKitLogic

private let t0 = 1_792_200_000.0

private func prior(_ n: Int, _ type: WaymarkLabelType) -> WaymarkPrior {
    WaymarkPrior(id: "ps:\(n)", type: type, lat: 47.654, lng: -122.305, severity: 2, tags: [], nAgree: 1,
                 nDisagree: 0, nUnsure: 0, clusterSize: 1, streetEdgeID: nil, intersectionID: nil,
                 osmWayID: nil, imageryDate: nil, labelDate: nil, sourceClusterID: n)
}

private func hit(_ n: Int, _ type: WaymarkLabelType = .obstacle, along: Double = 10) -> WaymarkAhead.Hit {
    WaymarkAhead.Hit(prior: prior(n, type), alongM: along, crossM: 0)
}

/// Inputs where everything allows speech; tests change one field each.
private func ok(now: Double = t0, level: String = "detailed", place: String = "outdoors",
                crossing: Bool = false, voice: Bool = false, gpsWeak: Bool = false, fresh: Bool = true,
                lidar: Double? = nil, speed: Double = 1.2, accuracy: Double = 5) -> WaymarkAlertInputs {
    WaymarkAlertInputs(cueLevel: level, cuePlace: place, crossingSettle: crossing, voiceHeld: voice,
                       gpsWeak: gpsWeak, fixFresh: fresh, secondsSinceLidarCue: lidar,
                       speedMps: speed, gpsAccuracyM: accuracy, nowUTC: now)
}

private func reason(_ d: WaymarkDecision) -> String? { if case .silent(let r) = d { r } else { nil } }

// MARK: Lines

@Test func linesAreTheAppendixAReports() {
    #expect(WaymarkLine.obstacle.text == "Reported obstacle ahead.")
    #expect(WaymarkLine.missingCurbRamp.text == "Reported missing curb ramp ahead.")
    #expect(WaymarkLine.noSidewalk.text == "Reported no sidewalk ahead.")
    #expect(WaymarkLine.surfaceProblem.text == "Reported rough surface ahead.")
    #expect(WaymarkLine.curbRamp.text == "Reported curb ramp ahead.")
}

@Test func linesAreShortUniqueNumberFreeReports() {
    let all = WaymarkLines.all
    #expect(all.count == WaymarkLine.allCases.count)
    #expect(Set(all).count == all.count)
    for line in all {
        #expect(!line.isEmpty && line.count < 40)
        #expect(line.hasPrefix("Reported "))
        #expect(!line.lowercased().contains("detect"))
        #expect(line.rangeOfCharacter(from: .decimalDigits) == nil)
    }
}

@Test func everyLineIsInThePrefetchList() {
    // Referenced, never retyped (design doc 8.3 trap): the warm-up list carries the same bytes.
    #expect(Set(WaymarkLines.all).isSubset(of: Set(SpokenPhrases.warningLines)))
}

@Test func typesMapToTheirLines() {
    #expect(WaymarkLine(for: .obstacle) == .obstacle)
    #expect(WaymarkLine(for: .missingCurbRamp) == .missingCurbRamp)
    #expect(WaymarkLine(for: .noSidewalk) == .noSidewalk)
    #expect(WaymarkLine(for: .surfaceProblem) == .surfaceProblem)
    #expect(WaymarkLine(for: .curbRamp) == .curbRamp)
    #expect(WaymarkLine(for: .crosswalk) == nil)    // D-15: never spoken
    #expect(WaymarkLine(for: .other) == nil)
}

// MARK: Policy: the happy path

@Test func speaksAnObstacleAboveItsThreshold() {
    var policy = WaymarkAlertPolicy()
    #expect(policy.decide(hit(1), p: 0.75, inputs: ok()) == .speak(.obstacle, labelID: "ps:1"))
}

// MARK: Policy: one rule each

@Test func quietLevelIsSilent() {
    var policy = WaymarkAlertPolicy()
    #expect(reason(policy.decide(hit(1), p: 0.9, inputs: ok(level: "quiet"))) == "level_quiet")
}

@Test func indoorsIsSilent() {
    var policy = WaymarkAlertPolicy()
    #expect(reason(policy.decide(hit(1), p: 0.9, inputs: ok(place: "indoors"))) == "indoors")
}

@Test func standardSpeaksOnlyTheThreeBarrierTypes() {
    for t in [WaymarkLabelType.obstacle, .missingCurbRamp, .noSidewalk] {
        var policy = WaymarkAlertPolicy()
        #expect(policy.decide(hit(1, t), p: 0.9, inputs: ok(level: "standard")) == .speak(WaymarkLine(for: t)!, labelID: "ps:1"))
    }
    for t in [WaymarkLabelType.surfaceProblem, .curbRamp] {
        var policy = WaymarkAlertPolicy()
        #expect(reason(policy.decide(hit(1, t), p: 0.9, inputs: ok(level: "standard"))) == "level_detailed_only")
    }
}

@Test func detailedAlsoSpeaksSurfaceAndCurbRamps() {
    var a = WaymarkAlertPolicy(), b = WaymarkAlertPolicy()
    #expect(a.decide(hit(1, .surfaceProblem), p: 0.5, inputs: ok()) == .speak(.surfaceProblem, labelID: "ps:1"))
    #expect(b.decide(hit(2, .curbRamp), p: 0.5, inputs: ok()) == .speak(.curbRamp, labelID: "ps:2"))
}

@Test func crosswalkAndOtherAreNeverSpoken() {
    for t in [WaymarkLabelType.crosswalk, .other] {
        var policy = WaymarkAlertPolicy()
        #expect(reason(policy.decide(hit(1, t), p: 1, inputs: ok())) == "not_spoken_type")
    }
}

@Test func belowThresholdIsSilentAtAndAboveSpeaks() {
    let tau = WaymarkThreshold.tau(for: .surfaceProblem)!   // 1/3
    var below = WaymarkAlertPolicy(), at = WaymarkAlertPolicy()
    #expect(reason(below.decide(hit(1, .surfaceProblem), p: tau - 1e-9, inputs: ok())) == "below_threshold")
    #expect(at.decide(hit(1, .surfaceProblem), p: tau, inputs: ok()) == .speak(.surfaceProblem, labelID: "ps:1"))
}

@Test func crossingSettleIsSilent() {
    var policy = WaymarkAlertPolicy()
    #expect(reason(policy.decide(hit(1), p: 0.9, inputs: ok(crossing: true))) == "crossing")
}

@Test func voiceHoldIsSilent() {
    var policy = WaymarkAlertPolicy()
    #expect(reason(policy.decide(hit(1), p: 0.9, inputs: ok(voice: true))) == "voice_hold")
}

@Test func weakOrStaleGPSIsSilent() {
    var a = WaymarkAlertPolicy(), b = WaymarkAlertPolicy(), c = WaymarkAlertPolicy()
    #expect(reason(a.decide(hit(1), p: 0.9, inputs: ok(gpsWeak: true))) == "gps_weak")
    #expect(reason(b.decide(hit(1), p: 0.9, inputs: ok(fresh: false))) == "gps_stale")
    #expect(reason(c.decide(hit(1), p: 0.9, inputs: ok(accuracy: 25))) == "gps_weak")
}

@Test func aRecentLidarWarningSilencesWaymark() {
    var a = WaymarkAlertPolicy(), b = WaymarkAlertPolicy()
    #expect(reason(a.decide(hit(1), p: 0.9, inputs: ok(lidar: 4.9))) == "lidar_recent")
    #expect(b.decide(hit(1), p: 0.9, inputs: ok(lidar: 5.0)) == .speak(.obstacle, labelID: "ps:1"))
}

@Test func tooFarAheadWaitsUntilTheTriggerDistance() {
    // Trigger = clamp(speed × 8 s, 12, 35) m + uncertainty margin; 1.2 m/s → 9.6 → 12 m, plus margin.
    let trigger = WaymarkAlertPolicy.triggerDistanceM(speedMps: 1.2, gpsAccuracyM: 5)
    var policy = WaymarkAlertPolicy()
    #expect(reason(policy.decide(hit(1, along: trigger + 0.5), p: 0.9, inputs: ok())) == "not_yet")
    #expect(policy.decide(hit(1, along: trigger - 0.5), p: 0.9, inputs: ok()) == .speak(.obstacle, labelID: "ps:1"))
}

@Test func triggerDistanceFollowsTheDesignFormula() {
    func base(_ v: Double) -> Double { min(max(v * 8, 12), 35) }
    let margin = { (acc: Double) in (acc * acc + 8 * 8).squareRoot() }
    for v in [0.5, 1.0, 1.5, 2.0, 3.0, 5.0] {
        let expected = min(WaymarkAhead.lookaheadMaxM, base(v) + margin(5))
        #expect(abs(WaymarkAlertPolicy.triggerDistanceM(speedMps: v, gpsAccuracyM: 5) - expected) < 1e-12)
    }
    #expect(WaymarkAlertPolicy.triggerDistanceM(speedMps: 9, gpsAccuracyM: 3) == WaymarkAhead.lookaheadMaxM)
}

@Test func eachLabelIsSpokenOncePerRoute() {
    var policy = WaymarkAlertPolicy()
    #expect(policy.decide(hit(1), p: 0.9, inputs: ok(now: t0)) == .speak(.obstacle, labelID: "ps:1"))
    #expect(reason(policy.decide(hit(1), p: 0.9, inputs: ok(now: t0 + 600))) == "already_announced")
    policy.routeStarted()
    #expect(policy.decide(hit(1), p: 0.9, inputs: ok(now: t0 + 700)) == .speak(.obstacle, labelID: "ps:1"))
}

@Test func linesAreAtLeastTwentySecondsApart() {
    var policy = WaymarkAlertPolicy()
    #expect(policy.decide(hit(1), p: 0.9, inputs: ok(now: t0)) == .speak(.obstacle, labelID: "ps:1"))
    #expect(reason(policy.decide(hit(2), p: 0.9, inputs: ok(now: t0 + 19.9))) == "spacing")
    #expect(policy.decide(hit(2), p: 0.9, inputs: ok(now: t0 + 20)) == .speak(.obstacle, labelID: "ps:2"))
}

@Test func atMostSixLinesPerRoute() {
    var policy = WaymarkAlertPolicy()
    policy.routeStarted()
    for n in 1...6 {
        #expect(policy.decide(hit(n), p: 0.9, inputs: ok(now: t0 + Double(n) * 30)) == .speak(.obstacle, labelID: "ps:\(n)"))
    }
    #expect(reason(policy.decide(hit(7), p: 0.9, inputs: ok(now: t0 + 300))) == "route_cap")
    policy.routeEnded()
    #expect(policy.decide(hit(7), p: 0.9, inputs: ok(now: t0 + 400)) == .speak(.obstacle, labelID: "ps:7"))
}

@Test func aSilentDecisionChangesNoState() {
    var policy = WaymarkAlertPolicy()
    _ = policy.decide(hit(1), p: 0.9, inputs: ok(crossing: true))
    #expect(policy.decide(hit(1), p: 0.9, inputs: ok()) == .speak(.obstacle, labelID: "ps:1"))
}

@Test func unknownCueLevelOrPlaceIsSilent() {
    // Fail quiet: a renamed base-app level must not make Waymark louder.
    var a = WaymarkAlertPolicy(), b = WaymarkAlertPolicy()
    #expect(reason(a.decide(hit(1), p: 0.9, inputs: ok(level: "loud"))) == "level_unknown")
    #expect(reason(b.decide(hit(1), p: 0.9, inputs: ok(place: "space"))) == "place_unknown")
}

@Test func nonFiniteBeliefIsSilent() {
    var policy = WaymarkAlertPolicy()
    #expect(reason(policy.decide(hit(1), p: .nan, inputs: ok())) == "below_threshold")
}

@Test func policyConstantsAreThePlanDefaults() {
    #expect(WaymarkAlertPolicy.minSpacingS == 20)
    #expect(WaymarkAlertPolicy.maxPerRoute == 6)
    #expect(WaymarkAlertPolicy.lidarQuietS == 5)
    #expect(WaymarkAlertPolicy.labelErrorM == 8)
    #expect(WaymarkAlertPolicy.maxGpsAccuracyM == 20)
}

// MARK: R1 / D-29 follow-ups

@Test func curbRampsNeedAtLeastAnEvenBelief() {
    // D-29 (1): curb ramps have no tau; at Detailed they speak only when p >= 0.5.
    var low = WaymarkAlertPolicy(), even = WaymarkAlertPolicy()
    #expect(reason(low.decide(hit(1, .curbRamp), p: 0.4999, inputs: ok())) == "below_threshold")
    #expect(even.decide(hit(1, .curbRamp), p: 0.5, inputs: ok()) == .speak(.curbRamp, labelID: "ps:1"))
    #expect(WaymarkAlertPolicy.curbRampMinP == 0.5)
}

@Test func aBackwardsClockDoesNotSilenceWaymarkForever() {
    // R1 finding: `now - last < 20` stayed true forever after the wall clock stepped back.
    var policy = WaymarkAlertPolicy()
    #expect(policy.decide(hit(1), p: 0.9, inputs: ok(now: t0)) == .speak(.obstacle, labelID: "ps:1"))
    #expect(reason(policy.decide(hit(2), p: 0.9, inputs: ok(now: t0 - 5))) == "spacing")     // small step back: still spaced
    #expect(policy.decide(hit(2), p: 0.9, inputs: ok(now: t0 - 3600)) == .speak(.obstacle, labelID: "ps:2"))
}
