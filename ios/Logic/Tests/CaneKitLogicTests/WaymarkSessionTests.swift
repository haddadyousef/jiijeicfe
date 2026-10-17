//
//  WaymarkSessionTests.swift
//  CaneKitLogicTests
//
//  Pins `WaymarkSession` (A1): one GPS fix in, at most one spoken line out, with every decision
//  logged once per label and reason (not once per fix) so the trip log stays readable at 1 Hz.
//  The session is the pure core of the app's `WaymarkEngine`; the engine only loads the file,
//  measures time and hands lines to the speech queue.
//  Source pinned: `ios/Logic/Sources/CaneKitLogic/Waymark/WaymarkSession.swift`.
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

private func context(now: Double, level: String = "detailed", crossing: Bool = false) -> WaymarkSession.Context {
    WaymarkSession.Context(cueLevel: level, cuePlace: "outdoors", crossingSettle: crossing, voiceHeld: false,
                           gpsWeak: false, fixFresh: true, secondsSinceLidarCue: nil, nowUTC: now,
                           headingDeg: 0, legs: nil)
}

private func fix(north: Double, speed: Double = 1.3, accuracy: Double = 5) -> GeoFix {
    GeoFix(coordinate: at(north: north), accuracy: accuracy, speed: speed, timestamp: 0)
}

@Test func walkingTowardAnObstacleSpeaksOnceAtTheTriggerDistance() {
    var s = session([prior(1, .obstacle, at(north: 60))])
    var spokenAt: [Double] = []
    var north = 0.0, now = t0
    while north < 70 {
        let step = s.step(fix: fix(north: north), context: context(now: now))
        if let line = step.spoken { spokenAt.append(north); #expect(line == .obstacle) }
        north += 1.3; now += 1
    }
    #expect(spokenAt.count == 1)
    // Trigger = clamp(1.3 × 8, 12, 35) + √(5² + 8²) ≈ 12 + 9.43 = 21.4 m before the label.
    let trigger = WaymarkAlertPolicy.triggerDistanceM(speedMps: 1.3, gpsAccuracyM: 5)
    #expect(abs((60 - spokenAt[0]) - trigger) <= 1.3)
}

@Test func atMostOneLinePerFix() {
    var s = session([prior(1, .obstacle, at(north: 10)), prior(2, .noSidewalk, at(north: 11))])
    let step = s.step(fix: fix(north: 0), context: context(now: t0))
    #expect(step.spoken == .obstacle && step.spokenLabelID == "ps:1")
    // The second label is not spoken in the same fix, and the 20 s spacing holds it afterwards.
    #expect(s.step(fix: fix(north: 1), context: context(now: t0 + 1)).spoken == nil)
    #expect(s.step(fix: fix(north: 1.5), context: context(now: t0 + 21)).spokenLabelID == "ps:2")
}

@Test func eachSilenceIsLoggedOncePerLabelAndReason() {
    var s = session([prior(1, .obstacle, at(north: 10))])
    let first = s.step(fix: fix(north: 0), context: context(now: t0, crossing: true))
    #expect(first.records.count == 1)
    #expect(first.records.first?["suppressed_reason"] == "crossing")
    for k in 1...5 {
        #expect(s.step(fix: fix(north: Double(k) * 0.2), context: context(now: t0 + Double(k), crossing: true)).records.isEmpty)
    }
    // A new reason for the same label is logged.
    let quiet = s.step(fix: fix(north: 1.5), context: context(now: t0 + 10, level: "quiet"))
    #expect(quiet.records.first?["suppressed_reason"] == "level_quiet")
}

@Test func aSpokenLineIsAlwaysLogged() {
    var s = session([prior(1, .obstacle, at(north: 10))])
    let step = s.step(fix: fix(north: 0), context: context(now: t0))
    #expect(step.records.count == 1)
    #expect(step.records.first?["line"] == "Reported obstacle ahead.")
    #expect(step.records.first?["label_id"] == "ps:1")
}

@Test func notYetIsNotLogged() {
    // "not_yet" happens on every fix while approaching; logging it would flood the trip log.
    var s = session([prior(1, .obstacle, at(north: 34))])
    #expect(s.step(fix: fix(north: 0), context: context(now: t0)).records.isEmpty)
}

@Test func standingStillDoesNothing() {
    var s = session([prior(1, .obstacle, at(north: 5))])
    let step = s.step(fix: fix(north: 0, speed: 0.2), context: context(now: t0))
    #expect(step.spoken == nil && step.records.isEmpty && step.candidates == 0)
}

@Test func evidenceChangesWhatIsSaid() {
    // A surface problem nobody validated (p = 0.5) is spoken; after two spotter contradictions
    // (p = 1/6 < tau 1/3) it is not (the D-31 stale-label story).
    let label = prior(1, .surfaceProblem, at(north: 10), agree: 0, disagree: 0)
    var fresh = session([label])
    #expect(fresh.step(fix: fix(north: 0), context: context(now: t0)).spoken == .surfaceProblem)
    var stale = session([label])
    stale.record(.contradicted, sensor: .spotter, labelID: "ps:1", nowUTC: t0 - 60)
    stale.record(.contradicted, sensor: .spotter, labelID: "ps:1", nowUTC: t0 - 30)
    let step = stale.step(fix: fix(north: 0), context: context(now: t0))
    #expect(step.spoken == nil)
    #expect(step.records.first?["suppressed_reason"] == "below_threshold")
}

@Test func recordIgnoresUnknownLabels() {
    var s = session([prior(1, .obstacle, at(north: 10))])
    s.record(.confirmed, sensor: .spotter, labelID: "ps:999", nowUTC: t0)
    #expect(s.beliefs.isEmpty)
}

@Test func routeBoundariesResetAnnouncementsAndLogDedupe() {
    var s = session([prior(1, .obstacle, at(north: 10))])
    #expect(s.step(fix: fix(north: 0), context: context(now: t0)).spoken == .obstacle)
    #expect(s.step(fix: fix(north: 0.5), context: context(now: t0 + 30)).spoken == nil)   // already announced
    s.routeStarted()
    #expect(s.step(fix: fix(north: 0.5), context: context(now: t0 + 60)).spoken == .obstacle)
}

@Test func routeLegsAreUsedWhenGiven() {
    // Route goes east; a label 20 m north (outside the 12 m corridor) is not ahead even though
    // the heading says north, where it would be the closest hit.
    var s = session([prior(1, .obstacle, at(north: 20)), prior(2, .obstacle, at(north: 0, east: 10))])
    var ctx = context(now: t0)
    ctx.legs = [at(north: 0, east: 60)]
    #expect(s.step(fix: fix(north: 0), context: ctx).spokenLabelID == "ps:2")
}

@Test func waymarkSettingIsClearedAfterACrashLoop() {
    #expect(LaunchRecovery.optionalFeatureKeys.contains("waymarkEnabled"))
}
