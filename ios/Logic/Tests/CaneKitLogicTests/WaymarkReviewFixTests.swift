//
//  WaymarkReviewFixTests.swift
//  CaneKitLogicTests
//
//  Pins the judge-demo task 3 review fixes, written before the code:
//    · `StoredBool.parse` — a launch argument (`-waymarkEnabled NO`) reaches `UserDefaults` as the
//      String "NO", which `as? Bool` read as unset, so the UI tests' mask was a no-op (review M1).
//    · `WaymarkLearning.kept` — an unverifiable pass never replaces a decisive learning (review L3).
//    · `WaymarkGlance.learningDetailSpoken` / `learningSymbol` — the ahead card and map details say
//      what was learned, checked-before included; the icon follows the outcome (review L2, L5).
//    · `WaymarkGlance.storedCaption(folder:savedLabels:)` — no "Saved" caption before anything is
//      saved (review L4).
//    · `WaymarkStoreFolder.testPrefix` / `staleTestFolders` — UI-test folders from earlier runs are
//      removed, never the real `waymark` folder (review L6).
//  Source pinned: `StoredBool.swift`, `WaymarkLearningShown.swift`, `WaymarkStoreFolder.swift`.
//

import Foundation
import Testing
@testable import CaneKitLogic

private func learning(_ outcome: WaymarkOutcome, _ id: String = "ps:1", before: Double = 0.5,
                      after: Double = 6.0 / 14.0, sensor: WaymarkSensor = .spotter) -> WaymarkLearning {
    WaymarkLearning(labelID: id, type: .obstacle, outcome: outcome, sensor: sensor,
                    pBefore: before, pAfter: outcome == .unverifiable ? before : after)
}

// MARK: Stored Bool (launch-argument strings)

@Test func storedBoolReadsRealBools() {
    #expect(StoredBool.parse(true) == true)
    #expect(StoredBool.parse(false) == false)
    #expect(StoredBool.parse(nil) == nil)          // never written → caller's default
}

@Test func storedBoolReadsLaunchArgumentStrings() {
    // `-key NO` / `-key YES` arrive in the argument domain as Strings.
    #expect(StoredBool.parse("NO") == false)
    #expect(StoredBool.parse("YES") == true)
    for yes in ["yes", "Yes", "true", "TRUE", "1"] { #expect(StoredBool.parse(yes) == true, "\(yes)") }
    for no in ["no", "No", "false", "FALSE", "0"] { #expect(StoredBool.parse(no) == false, "\(no)") }
}

@Test func storedBoolIgnoresAnythingElse() {
    for junk: Any in ["", "maybe", "Y E S", "2", 3.5, [true], ["a": true]] {
        #expect(StoredBool.parse(junk) == nil, "\(junk)")
    }
}

// MARK: Kept learning

@Test func decisiveLearningReplacesAnything() {
    let spotter = learning(.contradicted)
    let lidar = learning(.confirmed, before: 6.0 / 14.0, after: 0.5, sensor: .lidarTorso)
    #expect(WaymarkLearning.kept(spotter, over: nil) == spotter)
    #expect(WaymarkLearning.kept(lidar, over: spotter) == lidar)
    #expect(WaymarkLearning.kept(spotter, over: learning(.unverifiable)) == spotter)
}

@Test func unverifiableNeverReplacesADecisiveLearning() {
    let spotter = learning(.contradicted)
    let unsure = learning(.unverifiable, before: 6.0 / 14.0, sensor: .lidarTorso)
    #expect(WaymarkLearning.kept(unsure, over: spotter) == spotter)
    // Different label, same rule (the card's "last learning" keeps the spotter's row).
    #expect(WaymarkLearning.kept(learning(.unverifiable, "ps:2"), over: spotter) == spotter)
    // With nothing decisive kept, the unverifiable one is shown (it says "confidence unchanged").
    #expect(WaymarkLearning.kept(unsure, over: nil) == unsure)
    let newer = learning(.unverifiable, "ps:3")
    #expect(WaymarkLearning.kept(newer, over: unsure) == newer)
}

// MARK: Detail words and icon

@Test func learningDetailSpokenMatchesTheVisibleLine() {
    let l = learning(.contradicted)
    #expect(WaymarkGlance.learningDetailSpoken(learning: l, checked: true)
            == "Spotter said not there. Confidence went from 50 to 43 percent.")
    #expect(WaymarkGlance.learningDetailSpoken(learning: nil, checked: true) == "Checked on this phone before.")
    #expect(WaymarkGlance.learningDetailSpoken(learning: nil, checked: false) == nil)
}

@Test func learningSymbolFollowsTheOutcome() {
    #expect(WaymarkGlance.learningSymbol(learning(.confirmed, after: 0.6)) == "checkmark.seal.fill")
    #expect(WaymarkGlance.learningSymbol(learning(.contradicted)) == "xmark.seal.fill")
    #expect(WaymarkGlance.learningSymbol(learning(.unverifiable)) == "questionmark.circle")
    #expect(WaymarkGlance.learningSymbol(nil) == "clock.arrow.circlepath")     // checked before
}

// MARK: Storage caption

@Test func storageCaptionOnlyOnceSomethingIsSaved() {
    #expect(WaymarkGlance.storedCaption(folder: "waymark", savedLabels: 0) == nil)
    #expect(WaymarkGlance.storedCaption(folder: "waymark", savedLabels: 1)
            == "Saved on this phone: Documents/waymark/beliefs.json")
    #expect(WaymarkGlance.storedCaption(folder: "wm-ui-1A2B3C4D", savedLabels: 3)
            == "Saved on this phone: Documents/wm-ui-1A2B3C4D/beliefs.json")
}

// MARK: Stale UI-test folders

@Test func staleTestFoldersAreEarlierRunsOnly() {
    let names = ["waymark", "wm-ui-AAAA1111", "wm-ui-BBBB2222", "waymark-uitest-3F2504E0-4F89-11D3-9A0C-0305E82C3301",
                 "TripLogs", "wm-uix", "wm-ui-../x", ".DS_Store"]
    #expect(WaymarkStoreFolder.testPrefix == "wm-ui-")
    #expect(Set(WaymarkStoreFolder.staleTestFolders(names, active: "wm-ui-BBBB2222", uiTest: true))
            == ["wm-ui-AAAA1111", "waymark-uitest-3F2504E0-4F89-11D3-9A0C-0305E82C3301"])
}

@Test func staleTestFoldersNeverOutsideUITestsAndNeverTheRealFolder() {
    let names = ["waymark", "wm-ui-AAAA1111"]
    #expect(WaymarkStoreFolder.staleTestFolders(names, active: "waymark", uiTest: false).isEmpty)
    #expect(WaymarkStoreFolder.staleTestFolders(names, active: "wm-ui-CCCC3333", uiTest: false).isEmpty)
    #expect(WaymarkStoreFolder.staleTestFolders(names, active: "waymark", uiTest: true) == ["wm-ui-AAAA1111"])
    #expect(!WaymarkStoreFolder.staleTestFolders(names, active: "wm-ui-CCCC3333", uiTest: true).contains("waymark"))
}
