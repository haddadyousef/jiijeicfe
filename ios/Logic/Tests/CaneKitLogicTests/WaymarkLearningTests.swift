//
//  WaymarkLearningTests.swift
//  CaneKitLogicTests
//
//  Pins "make learning visible" (judge demo, task 3): recording an outcome returns the label's
//  confidence before and after (`WaymarkSession.record` → `WaymarkLearning`), unverifiable stays a
//  no-op and says so, the words name the source (`WaymarkGlance.learningLine`), and beliefs survive
//  the same JSON round trip `WaymarkStore` uses for `Documents/waymark/beliefs.json`.
//  Numbers are plan 5.3 (normative): obstacle half-life 60 days, spotter weight 2, LiDAR 1.
//  Source pinned: `WaymarkSession.swift`, `WaymarkGlance.swift`, `WaymarkBelief.swift`.
//

import Foundation
import Testing
@testable import CaneKitLogic

private let t0 = 1_792_200_000.0

private func prior(_ n: Int, _ type: WaymarkLabelType, agree: Int, disagree: Int) -> WaymarkPrior {
    WaymarkPrior(id: "ps:\(n)", type: type, lat: 47.66, lng: -122.31, severity: nil, tags: [],
                 nAgree: agree, nDisagree: disagree, nUnsure: 0, clusterSize: 1, streetEdgeID: nil,
                 intersectionID: nil, osmWayID: nil, imageryDate: "2018-10", labelDate: nil, sourceClusterID: n)
}

private func session(_ labels: [WaymarkPrior]) -> WaymarkSession {
    WaymarkSession(priors: WaymarkPriorSet(generatedAt: "x", sourceName: "SYNTHETIC test",
                                           bboxLngLat: [-123, 47, -122, 48], labels: labels))
}

@Test func spotterNotThereLowersAndReportsBeforeAndAfter() {
    // The Ave route's fire-hydrant obstacle shape: 5 agree, 5 disagree → p = 6 / 12 = 0.5.
    var s = session([prior(1, .obstacle, agree: 5, disagree: 5)])
    let l = s.record(.contradicted, sensor: .spotter, labelID: "ps:1", nowUTC: t0)
    #expect(l?.labelID == "ps:1" && l?.type == .obstacle && l?.sensor == .spotter)
    #expect(abs((l?.pBefore ?? 0) - 0.5) < 1e-12)
    // a = 6, b = 6 + 2 → 6 / 14.
    #expect(abs((l?.pAfter ?? 0) - 6.0 / 14.0) < 1e-12)
    #expect(l?.changed == true)
    #expect(abs((s.confidence(of: "ps:1", nowUTC: t0) ?? 0) - 6.0 / 14.0) < 1e-12)
}

@Test func lidarConfirmRaisesByItsWeight() {
    // Plan 5.3 worked row: missing curb ramp 1 / 1 (p 0.5), LiDAR confirm → a = 3, b = 2, p = 0.6.
    var s = session([prior(2, .missingCurbRamp, agree: 1, disagree: 1)])
    let l = s.record(.confirmed, sensor: .lidarTorso, labelID: "ps:2", nowUTC: t0)
    #expect(abs((l?.pBefore ?? 0) - 0.5) < 1e-12)
    #expect(abs((l?.pAfter ?? 0) - 0.6) < 1e-12)
}

@Test func unverifiableIsANoOpAndSaysSo() {
    var s = session([prior(1, .obstacle, agree: 5, disagree: 5)])
    s.record(.contradicted, sensor: .spotter, labelID: "ps:1", nowUTC: t0)
    let before = s.beliefs
    let l = s.record(.unverifiable, sensor: .lidarTorso, labelID: "ps:1", nowUTC: t0 + 86_400)
    #expect(s.beliefs == before)                    // nothing stored changed, not even the clock
    #expect(l?.changed == false)
    #expect(l?.pBefore == l?.pAfter)
    #expect(WaymarkGlance.learningLine(l!) == "Couldn't check · confidence unchanged at \(WaymarkGlance.percent(l!.pAfter)!) % · LiDAR")
}

@Test func unknownLabelRecordsNothing() {
    var s = session([prior(1, .obstacle, agree: 1, disagree: 0)])
    #expect(s.record(.confirmed, sensor: .spotter, labelID: "ps:999", nowUTC: t0) == nil)
    #expect(s.beliefs.isEmpty)
}

@Test func learningWordsNameTheSource() {
    let l = WaymarkLearning(labelID: "ps:1", type: .obstacle, outcome: .contradicted, sensor: .spotter,
                            pBefore: 0.5, pAfter: 6.0 / 14.0)
    #expect(WaymarkGlance.learningLine(l) == "Not there · 50 % → 43 % · spotter")
    #expect(WaymarkGlance.learningSpoken(l)
            == "Spotter said not there. Confidence went from 50 to 43 percent.")
    let c = WaymarkLearning(labelID: "ps:2", type: .missingCurbRamp, outcome: .confirmed, sensor: .lidarTorso,
                            pBefore: 0.5, pAfter: 0.6)
    #expect(WaymarkGlance.learningLine(c) == "Confirmed · 50 % → 60 % · LiDAR")
    #expect(WaymarkGlance.source(.lidarHead) == "LiDAR")
    #expect(WaymarkGlance.source(.ground) == "LiDAR curb check")
    #expect(WaymarkGlance.source(.vision) == "camera")
}

@Test func beliefsSurviveTheStoreRoundTrip() throws {
    // Same encoder settings as WaymarkStore.saveBeliefs; same decode as loadBeliefs; restore as on load.
    var s = session([prior(1, .obstacle, agree: 5, disagree: 5), prior(2, .curbRamp, agree: 7, disagree: 0)])
    s.record(.contradicted, sensor: .spotter, labelID: "ps:1", nowUTC: t0)
    s.record(.confirmed, sensor: .lidarTorso, labelID: "ps:2", nowUTC: t0 + 10)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(s.beliefs)
    let decoded = try JSONDecoder().decode([String: WaymarkBelief].self, from: data)
    var relaunched = session([prior(1, .obstacle, agree: 5, disagree: 5), prior(2, .curbRamp, agree: 7, disagree: 0)])
    relaunched.restore(decoded)
    for id in ["ps:1", "ps:2"] {
        let later = t0 + 30 * 86_400
        #expect(abs((relaunched.confidence(of: id, nowUTC: later) ?? -1) - (s.confidence(of: id, nowUTC: later) ?? -2)) < 1e-12)
    }
}
