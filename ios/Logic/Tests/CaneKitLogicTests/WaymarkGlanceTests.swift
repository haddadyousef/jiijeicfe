//
//  WaymarkGlanceTests.swift
//  CaneKitLogicTests
//
//  Pins `WaymarkGlance` (the words the Guide's Sidewalk memory card shows) and
//  `WaymarkSession.Step.nearest` (which label that card describes): the nearest label ahead is the
//  first `WaymarkAhead` hit in the session's own order (along, then id), with its belief p. The card
//  shows that first hit whatever the policy decides; the spoken line is the first hit the policy
//  lets speak, so the two can differ (e.g. a curb ramp shown, an obstacle behind it spoken).
//  Source pinned: `ios/Logic/Sources/CaneKitLogic/Waymark/WaymarkGlance.swift`, `WaymarkSession.swift`.
//

import Foundation
import Testing
@testable import CaneKitLogic

private let origin = Coordinate(latitude: 47.6540, longitude: -122.3050)
private let t0 = 1_792_200_000.0

/// Metres north / east of the origin.
private func at(north: Double, east: Double = 0) -> Coordinate {
    let m = 6_371_000.0 * .pi / 180
    return Coordinate(latitude: origin.latitude + north / m,
                      longitude: origin.longitude + east / (m * cos(origin.latitude * .pi / 180)))
}

private func prior(_ n: Int, _ type: WaymarkLabelType, _ c: Coordinate, agree: Int = 1, disagree: Int = 0) -> WaymarkPrior {
    WaymarkPrior(id: "ps:\(n)", type: type, lat: c.latitude, lng: c.longitude, severity: 2, tags: [],
                 nAgree: agree, nDisagree: disagree, nUnsure: 0, clusterSize: 1, streetEdgeID: nil,
                 intersectionID: nil, osmWayID: nil, imageryDate: nil, labelDate: nil, sourceClusterID: n)
}

private func session(_ labels: [WaymarkPrior]) -> WaymarkSession {
    WaymarkSession(priors: WaymarkPriorSet(generatedAt: "x", sourceName: "SYNTHETIC test",
                                           bboxLngLat: [-123, 47, -122, 48], labels: labels))
}

private func context(now: Double, speechIdle: Bool = true) -> WaymarkSession.Context {
    WaymarkSession.Context(cueLevel: "detailed", cuePlace: "outdoors", crossingSettle: false, voiceHeld: false,
                           gpsWeak: false, fixFresh: true, secondsSinceLidarCue: nil, nowUTC: now,
                           headingDeg: 0, legs: nil, speechIdle: speechIdle)
}

private func fix(north: Double, speed: Double = 1.3) -> GeoFix {
    GeoFix(coordinate: at(north: north), accuracy: 5, speed: speed, timestamp: 0)
}

// MARK: - Words

@Test func everyTypeHasPlainWords() {
    #expect(WaymarkGlance.words(.obstacle) == "obstacle")
    #expect(WaymarkGlance.words(.missingCurbRamp) == "missing curb ramp")
    #expect(WaymarkGlance.words(.curbRamp) == "curb ramp")
    #expect(WaymarkGlance.words(.surfaceProblem) == "rough surface")   // the spoken line's word
    #expect(WaymarkGlance.words(.noSidewalk) == "no sidewalk")
    #expect(WaymarkGlance.words(.crosswalk) == "crosswalk")
    #expect(WaymarkGlance.words(.other) == "sidewalk issue")
    // Unique, so the card never names two types the same.
    #expect(Set(WaymarkLabelType.allCases.map(WaymarkGlance.words)).count == WaymarkLabelType.allCases.count)
}

@Test func reportedNeverSaysDetected() {
    for t in WaymarkLabelType.allCases {
        #expect(WaymarkGlance.reported(t).hasPrefix("Reported "))
        #expect(!WaymarkGlance.reported(t).lowercased().contains("detect"))
    }
}

@Test func percentRoundsAndClamps() {
    #expect(WaymarkGlance.percent(0.72) == 72)
    #expect(WaymarkGlance.percent(0.725) == 73)
    #expect(WaymarkGlance.percent(0.0) == 0)
    #expect(WaymarkGlance.percent(1.0) == 100)
    #expect(WaymarkGlance.percent(1.4) == 100)
    #expect(WaymarkGlance.percent(-0.2) == 0)
    #expect(WaymarkGlance.percent(.nan) == nil)
}

@Test func metresRoundAndNeverGoNegative() {
    #expect(WaymarkGlance.metres(40.4) == 40)
    #expect(WaymarkGlance.metres(40.5) == 41)
    #expect(WaymarkGlance.metres(-3) == 0)
    #expect(WaymarkGlance.metres(.infinity) == nil)
}

@Test func aheadLineMatchesTheCard() {
    #expect(WaymarkGlance.aheadLine(type: .obstacle, alongM: 40.4, p: 0.72)
            == "Reported obstacle · 40 m · 72 % likely")
    #expect(WaymarkGlance.aheadLine(type: .surfaceProblem, alongM: 7.6, p: 0.5)
            == "Reported rough surface · 8 m · 50 % likely")
    // VoiceOver hears words, not middle dots.
    #expect(WaymarkGlance.aheadSpoken(type: .obstacle, alongM: 40.4, p: 0.72)
            == "Reported obstacle, 40 meters ahead, 72 percent likely.")
    // A bad number drops the part, never prints "nan".
    #expect(WaymarkGlance.aheadLine(type: .obstacle, alongM: 12, p: .nan) == "Reported obstacle · 12 m")
}

@Test func aheadFactsAreTheLineWithoutTheType() {
    // The card shows the type on one line and these facts under it, so "72 % likely" never wraps.
    #expect(WaymarkGlance.aheadFacts(alongM: 40.4, p: 0.72) == "40 m · 72 % likely")
    #expect(WaymarkGlance.aheadLine(type: .obstacle, alongM: 40.4, p: 0.72)
            == WaymarkGlance.reported(.obstacle) + " · " + WaymarkGlance.aheadFacts(alongM: 40.4, p: 0.72))
    #expect(WaymarkGlance.aheadFacts(alongM: .nan, p: .nan) == "")
}

@Test func chipWordsSayOffAndHowToTurnOn() {
    #expect(WaymarkGlance.chip(enabled: false, loadedLabels: nil) == "Sidewalk memory off · Turn on")
    #expect(WaymarkGlance.chip(enabled: true, loadedLabels: nil) == "Sidewalk memory loading")
    #expect(WaymarkGlance.chip(enabled: true, loadedLabels: 3405) == "Sidewalk memory on · 3,405 reports")
    // Review 6: a failed load is not "loading" forever.
    #expect(WaymarkGlance.chip(enabled: true, loadedLabels: nil, failed: true) == "Sidewalk memory unavailable")
    #expect(WaymarkGlance.chip(enabled: false, loadedLabels: nil, failed: true) == "Sidewalk memory off · Turn on")
}

@Test func groupedHandlesEdges() {
    #expect(WaymarkGlance.grouped(0) == "0")
    #expect(WaymarkGlance.grouped(999) == "999")
    #expect(WaymarkGlance.grouped(1000) == "1,000")
    #expect(WaymarkGlance.grouped(1_000_000) == "1,000,000")
    #expect(WaymarkGlance.grouped(-12_345) == "-12,345")
}

@Test func cardStatusLinesAreFixed() {
    // Review 10: the card's non-report lines live here, not in the view.
    #expect(WaymarkGlance.noneAhead == "Nothing reported in the next 35 m")
    #expect(WaymarkGlance.waitingForGPS == "Waiting for a fresh GPS fix")
    #expect(WaymarkGlance.loadingLine == "Loading sidewalk reports…")
    #expect(WaymarkGlance.failedLine == "Reports could not be loaded")
}

// MARK: - Session: the nearest label ahead

@Test func nearestAheadIsTheClosestHitWithItsBelief() {
    var s = session([prior(1, .obstacle, at(north: 30), agree: 2), prior(2, .noSidewalk, at(north: 20))])
    let step = s.step(fix: fix(north: 0), context: context(now: t0))
    #expect(step.nearest?.labelID == "ps:2")
    #expect(step.nearest?.type == .noSidewalk)
    #expect(abs((step.nearest?.alongM ?? 0) - 20) < 0.01)
    // p from the prior only: a = 1 + 1, b = 1 → 2/3.
    #expect(abs((step.nearest?.p ?? 0) - 2.0 / 3.0) < 1e-9)
}

@Test func nearestAheadTiesBreakByID() {
    var s = session([prior(9, .obstacle, at(north: 15)), prior(3, .obstacle, at(north: 15))])
    #expect(s.step(fix: fix(north: 0), context: context(now: t0)).nearest?.labelID == "ps:3")
}

@Test func nearestAheadIsReportedEvenWhileSpeechIsBusy() {
    // The card is a picture of what is ahead; the speech queue being busy changes nothing about it.
    var s = session([prior(1, .obstacle, at(north: 10))])
    let step = s.step(fix: fix(north: 0), context: context(now: t0, speechIdle: false))
    #expect(step.spoken == nil)
    #expect(step.nearest?.labelID == "ps:1")
}

@Test func nothingAheadWhileStandingOrPastEveryLabel() {
    var s = session([prior(1, .obstacle, at(north: 10))])
    #expect(s.step(fix: fix(north: 0, speed: 0.2), context: context(now: t0)).nearest == nil)
    #expect(s.step(fix: fix(north: 20), context: context(now: t0 + 1)).nearest == nil)
}

@Test func standingStillKeepsTheLastReportWithItsCurrentBelief() {
    // Review 1: stopping at a curb must not blank the card ("Nothing reported") while the obstacle is
    // still 8 m ahead; and a spotter tap made while standing shows at once (p is read again).
    var s = session([prior(1, .obstacle, at(north: 10), agree: 2)])
    #expect(s.step(fix: fix(north: 2), context: context(now: t0)).nearest?.labelID == "ps:1")
    let stopped = s.step(fix: fix(north: 2, speed: 0.1), context: context(now: t0 + 1)).nearest
    #expect(stopped?.labelID == "ps:1")
    #expect(abs((stopped?.alongM ?? 0) - 8) < 0.01)
    #expect(abs((stopped?.p ?? 0) - 0.75) < 1e-9)
    s.record(.contradicted, sensor: .spotter, labelID: "ps:1", nowUTC: t0 + 2)
    let invalidSpeed = s.step(fix: fix(north: 2, speed: -1), context: context(now: t0 + 2)).nearest
    #expect(abs((invalidSpeed?.p ?? 0) - 0.5) < 1e-9)
    // Walking on past it: cleared.
    #expect(s.step(fix: fix(north: 12), context: context(now: t0 + 3)).nearest == nil)
}

@Test func aRouteBoundaryForgetsTheKeptReport() {
    var s = session([prior(1, .obstacle, at(north: 10))])
    _ = s.step(fix: fix(north: 0), context: context(now: t0))
    s.routeEnded()
    #expect(s.step(fix: fix(north: 0, speed: 0), context: context(now: t0 + 1)).nearest == nil)
    _ = s.step(fix: fix(north: 0), context: context(now: t0 + 2))
    s.routeStarted()
    #expect(s.step(fix: fix(north: 0, speed: 0), context: context(now: t0 + 3)).nearest == nil)
}

@Test func nearestAheadReflectsFieldEvidence() {
    var s = session([prior(1, .obstacle, at(north: 25), agree: 2)])
    s.record(.contradicted, sensor: .spotter, labelID: "ps:1", nowUTC: t0)
    // Plan 5.3 worked row: obstacle 2/0 after one spotter contradiction → a = 3, b = 3, p = 0.5.
    #expect(abs((s.step(fix: fix(north: 0), context: context(now: t0)).nearest?.p ?? 0) - 0.5) < 1e-9)
}
