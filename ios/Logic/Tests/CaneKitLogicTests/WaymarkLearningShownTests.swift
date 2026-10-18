//
//  WaymarkLearningShownTests.swift
//  CaneKitLogicTests
//
//  Pins the app-side rules of "make learning visible" (judge demo, task 3), written before the
//  code: the trip-log p_before / p_after numbers (3 dp, never NaN), "checked on this phone" (a
//  stored belief = field evidence, restored across launches), the pin's words, the storage caption,
//  and the UI-test-only store folder (`WAYMARK_STORE_SUBDIR`: letters, digits, - and _ only).
//  Source pinned: `WaymarkLearningShown.swift`, `WaymarkStoreFolder.swift`.
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

// MARK: Trip-log numbers

@Test func tripLogFieldsAreRoundedToThreePlaces() {
    let l = WaymarkLearning(labelID: "ps:1", type: .obstacle, outcome: .contradicted, sensor: .spotter,
                            pBefore: 0.5, pAfter: 6.0 / 14.0)
    #expect(l.tripLogFields == ["p_before": 0.5, "p_after": 0.429])
    #expect(WaymarkLearning.round3(0.66666) == 0.667)
    #expect(WaymarkLearning.round3(0.0004) == 0)
}

@Test func tripLogFieldsDropNonFiniteNumbers() {
    let l = WaymarkLearning(labelID: "ps:1", type: .obstacle, outcome: .unverifiable, sensor: .lidarTorso,
                            pBefore: .nan, pAfter: .infinity)
    #expect(l.tripLogFields.isEmpty)        // JSONSerialization would throw on NaN
}

@Test func unverifiableTripLogShowsTheSameNumberTwice() {
    var s = session([prior(1, .obstacle, agree: 5, disagree: 5)])
    let l = s.record(.unverifiable, sensor: .lidarTorso, labelID: "ps:1", nowUTC: t0)
    #expect(l?.tripLogFields == ["p_before": 0.5, "p_after": 0.5])
    #expect(s.isChecked("ps:1") == false)   // unverifiable is not field evidence
}

// MARK: Checked on this phone

@Test func checkedMeansAStoredBeliefAndSurvivesRestore() {
    var s = session([prior(1, .obstacle, agree: 5, disagree: 5), prior(2, .curbRamp, agree: 3, disagree: 0)])
    #expect(!s.isChecked("ps:1") && !s.isChecked("ps:2") && !s.isChecked("ps:999"))
    s.record(.contradicted, sensor: .spotter, labelID: "ps:1", nowUTC: t0)
    #expect(s.isChecked("ps:1") && !s.isChecked("ps:2"))
    var relaunched = session([prior(1, .obstacle, agree: 5, disagree: 5), prior(2, .curbRamp, agree: 3, disagree: 0)])
    relaunched.restore(s.beliefs)
    #expect(relaunched.isChecked("ps:1") && !relaunched.isChecked("ps:2"))
}

@Test func pinWordsSayCheckedOnlyWhenChecked() {
    #expect(WaymarkGlance.pinSpoken(type: .obstacle, p: 6.0 / 14.0, checked: false)
            == "Reported obstacle, 43 percent likely, uncertain")
    #expect(WaymarkGlance.pinSpoken(type: .obstacle, p: 6.0 / 14.0, checked: true)
            == "Reported obstacle, 43 percent likely, uncertain, checked on this phone")
    #expect(WaymarkGlance.checkedBefore == "Checked on this phone before")
}

@Test func pinDetailPrefersThisLaunchsLearning() {
    let l = WaymarkLearning(labelID: "ps:1", type: .obstacle, outcome: .contradicted, sensor: .spotter,
                            pBefore: 0.5, pAfter: 6.0 / 14.0)
    #expect(WaymarkGlance.pinLearningDetail(learning: l, checked: true) == "Not there · 50 % → 43 % · spotter")
    #expect(WaymarkGlance.pinLearningDetail(learning: nil, checked: true) == "Checked on this phone before")
    #expect(WaymarkGlance.pinLearningDetail(learning: nil, checked: false) == nil)
}

@Test func storageCaptionNamesTheFile() {
    #expect(WaymarkGlance.storedCaption(folder: "waymark", savedLabels: 1) == "Saved on this phone: Documents/waymark/beliefs.json")
}

// MARK: Store folder

@Test func storeFolderIsWaymarkOutsideUITests() {
    #expect(WaymarkStoreFolder.standard == "waymark")
    #expect(WaymarkStoreFolder.name(subdir: nil, uiTest: false) == "waymark")
    #expect(WaymarkStoreFolder.name(subdir: "waymark-uitest-1", uiTest: false) == "waymark")   // ignored
    #expect(WaymarkStoreFolder.name(subdir: nil, uiTest: true) == "waymark")
    #expect(WaymarkStoreFolder.name(subdir: "", uiTest: true) == "waymark")
}

@Test func storeFolderTakesASafeUITestName() {
    let uuid = "waymark-uitest-3F2504E0-4F89-11D3-9A0C-0305E82C3301"
    #expect(WaymarkStoreFolder.name(subdir: uuid, uiTest: true) == uuid)
    #expect(WaymarkStoreFolder.name(subdir: "a_b-C9", uiTest: true) == "a_b-C9")
}

@Test func storeFolderIgnoresUnsafeNames() {
    for bad in ["../waymark", "a/b", "a b", ".", "..", "x.json", "é", "a\u{0}b", "~", String(repeating: "a", count: 65)] {
        #expect(WaymarkStoreFolder.sanitized(bad) == nil, "\(bad)")
        #expect(WaymarkStoreFolder.name(subdir: bad, uiTest: true) == "waymark", "\(bad)")
    }
    #expect(WaymarkStoreFolder.sanitized(String(repeating: "a", count: 64)) != nil)
}
