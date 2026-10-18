//
//  CampusGateTests.swift
//  CaneKitLogicTests
//
//  Waymark: the default build never shows or speaks the University of Illinois. `CampusGate` is the
//  one pure switch — open only under `WAYMARK_DEMO_ROUTE=isr_cif` (the XCUITests and e2e.py set it),
//  plus `CANEKIT_INDOOR_ROUTE=1` for the indoor ISR script — and the decisions the app takes from it:
//  which fast-path routes survive, which destination rows are offered, whether the gazetteer
//  answers a typed place, where the completer is centred with no fix, and the indoor card's id and
//  hints. With the gate open every answer is exactly the base app's (the UIUC tests stay green).
//

import Foundation
import Testing
@testable import CaneKitLogic

/// Words that must never reach the default build's screen or voice (owner, 2026-10-17).
private let uiucWords = ["UIUC", "University of Illinois", "Illinois", "Illini", "Urbana", "Champaign",
                         "Townsend", "ISR", "CIF", "Grainger", "Siebel", "ARC", "Main Library",
                         "Goodwin", "Green Street", "campus"]

/// True when `text` contains any `uiucWords` entry, case-insensitively.
private func mentionsUIUC(_ text: String) -> Bool {
    uiucWords.contains { text.range(of: $0, options: .caseInsensitive) != nil }
}

// MARK: - The switch

@Test func gateOpensOnlyForTheIsrCifDemoRoute() {
    #expect(CampusGate.enabled(environment: [:]) == false)
    #expect(CampusGate.enabled(environment: ["WAYMARK_DEMO_ROUTE": "isr_cif"]) == true)
    #expect(CampusGate.enabled(environment: ["WAYMARK_DEMO_ROUTE": "ave"]) == false)
    #expect(CampusGate.enabled(environment: ["WAYMARK_DEMO_ROUTE": ""]) == false)
    #expect(CampusGate.enabled(environment: ["WAYMARK_DEMO_ROUTE": "ISR_CIF"]) == false)
    // The indoor automation hook alone does not open the outdoor gate.
    #expect(CampusGate.enabled(environment: ["CANEKIT_INDOOR_ROUTE": "1"]) == false)
}

@Test func indoorGateAlsoOpensForTheIndoorAutomationHook() {
    #expect(CampusGate.indoorEnabled(environment: [:]) == false)
    #expect(CampusGate.indoorEnabled(environment: ["CANEKIT_INDOOR_ROUTE": "1"]) == true)
    #expect(CampusGate.indoorEnabled(environment: ["CANEKIT_INDOOR_ROUTE": "0"]) == false)
    #expect(CampusGate.indoorEnabled(environment: ["WAYMARK_DEMO_ROUTE": "isr_cif"]) == true)
}

// MARK: - Fast path

@Test func campusFastPathRoutesTouchTheGazetteer() throws {
    let queries = ["take me to the union", "take me to CIF", "go to Grainger", "I'm heading to Siebel",
                   "navigate to the Main Library", "take me from ISR to CIF",
                   "take me from Townsend to Starbucks", "take me to Grainger from the lab"]
    for q in queries {
        let action = try #require(FastPathIntentClassifier.classify(query: q), "\(q)")
        #expect(CampusGate.allows(action, campusEnabled: false) == false, "\(q) → \(action)")
        #expect(CampusGate.allows(action, campusEnabled: true) == true, "\(q) → \(action)")
    }
    #expect(CampusGate.allows(.startRoute(destination: "the Illini Union"), campusEnabled: false) == false)
    #expect(CampusGate.allows(.routeFromTo(from: "the lab", to: "CIF"), campusEnabled: false) == false)
}

/// Review of f02771d (finding 1): with the gate closed a campus alias is not dropped to the cloud /
/// "I need a network model" line — it becomes a MapKit search in the walker's own words, never the
/// UIUC canonical name ("Union", not "the Illini Union").
@Test func closedGateSendsCampusRoutesToMapKitInTheWalkersWords() throws {
    let cases: [(String, String)] = [
        ("take me to the Union", "Union"),
        ("take me to the union", "Union"),
        ("go to the ARC", "ARC"),
        ("navigate to University Library", "University Library"),
        ("take me to Main Library", "Main Library"),
        ("I'm heading to Siebel", "Siebel"),
        ("take me to the Activities and Recreation Center please", "Activities and Recreation Center"),
        ("take me to the union from here", "Union"),
    ]
    for (q, words) in cases {
        let action = try #require(FastPathIntentClassifier.classify(query: q), "\(q)")
        guard case .startRoute(let canonical) = action else { Issue.record("\(q) → \(action)"); continue }
        let rewritten = CampusGate.rewrite(action, query: q, campusEnabled: false)
        #expect(rewritten == .startRoute(destination: words), "\(q) → \(String(describing: rewritten))")
        #expect(words != canonical)
        // Gate open: today's action, unchanged.
        #expect(CampusGate.rewrite(action, query: q, campusEnabled: true) == action)
    }
    // "the union" never becomes the Illini Union.
    let union = CampusGate.rewrite(.startRoute(destination: "the Illini Union"), query: "take me to the union",
                                   campusEnabled: false)
    if case .startRoute(let d) = union { #expect(!mentionsUIUC(d) && !d.contains("Illini")) } else { Issue.record("dropped") }
}

/// A `.routeFromTo` already carries both ends as the walker said them, so it passes unchanged (the
/// app consults no gazetteer for it with the gate closed); non-campus actions pass unchanged too.
@Test func closedGateRewriteLeavesEverythingElseAlone() throws {
    for q in ["take me from ISR to CIF", "take me to Grainger from the lab", "take me from Townsend to Starbucks",
              "take me to Starbucks", "route", "help", "stop"] {
        let action = try #require(FastPathIntentClassifier.classify(query: q), "\(q)")
        #expect(CampusGate.rewrite(action, query: q, campusEnabled: false) == action, "\(q) → \(action)")
    }
    #expect(CampusGate.rewrite(.routeFromTo(from: "ISR", to: "CIF"), query: "take me from ISR to CIF",
                               campusEnabled: false) == .routeFromTo(from: "ISR", to: "CIF"))
}

/// When the walker's words for a campus route cannot be found in the query, drop it (nil) rather
/// than search MapKit for the canonical UIUC name.
@Test func closedGateDropsACampusRouteItCannotPhrase() {
    #expect(CampusGate.rewrite(.startRoute(destination: "the Illini Union"), query: "something else",
                               campusEnabled: false) == nil)
    #expect(CampusGate.rewrite(.startRoute(destination: "the Illini Union"), query: "",
                               campusEnabled: false) == nil)
}

@Test func nonCampusActionsPassTheClosedGate() throws {
    for q in ["take me to Starbucks", "take me from the lab to Starbucks", "route", "help", "stop",
              "status", "next"] {
        let action = try #require(FastPathIntentClassifier.classify(query: q), "\(q)")
        #expect(CampusGate.allows(action, campusEnabled: false) == true, "\(q) → \(action)")
    }
    let others: [ConversationAction] = [.stopRoute, .startDefaultRoute, .help, .indoorOutside,
                                        .recordMarker(name: "Bench"), .startRoute(destination: "Cafe Allegro")]
    for a in others { #expect(CampusGate.allows(a, campusEnabled: false) == true, "\(a)") }
}

// MARK: - Typed destination

@Test func closedGateNeverAnswersFromTheGazetteer() {
    #expect(CampusGate.match("CIF", campusEnabled: false) == nil)
    #expect(CampusGate.match("the Illini Union", campusEnabled: false) == nil)
    #expect(CampusGate.match("CIF", campusEnabled: true)?.id == "cif")
    #expect(CampusGate.match("Starbucks", campusEnabled: true) == nil)
}

@Test func closedGateOffersNoCampusRows() {
    let none: [CompletionLine] = []
    // Gate open: exactly the base ranking (campus rows first).
    let open = CampusGate.suggestions(query: "Grainger", completions: none, from: nil, campusEnabled: true)
    #expect(open == DestinationSuggestions.suggestions(query: "Grainger", completions: none, from: nil))
    #expect(open.first?.kind == .campus)
    // Gate closed: the gazetteer offers nothing.
    #expect(CampusGate.suggestions(query: "Grainger", completions: none, from: nil, campusEnabled: false).isEmpty)
    #expect(CampusGate.suggestions(query: "union", completions: none, from: nil, campusEnabled: false).isEmpty)

    // MapKit rows are kept in MapKit's order (none dropped as a campus duplicate) and never badged.
    let lines = [CompletionLine(title: "Cafe Allegro", subtitle: "4214 University Way NE, Seattle, WA"),
                 CompletionLine(title: "Union Coffee", subtitle: "1910 E Union St, Seattle, WA"),
                 CompletionLine(title: "Union Station", subtitle: "Toronto, Canada")]
    let rows = CampusGate.suggestions(query: "union", completions: lines, from: nil,
                                      locality: Locality(countryCode: "US"), campusEnabled: false)
    #expect(rows.map(\.title) == ["Cafe Allegro", "Union Coffee"])   // the foreign row is dropped
    #expect(rows.allSatisfy { $0.kind == .map && $0.placeId == nil })
    for r in rows { #expect(!mentionsUIUC(r.voiceOverLabel + r.detailLine), "\(r.voiceOverLabel)") }

    // Cap and minimum length are the base ones.
    let many = (1...9).map { CompletionLine(title: "Cafe \($0)", subtitle: "") }
    #expect(CampusGate.suggestions(query: "cafe", completions: many, from: nil, campusEnabled: false).count
            == DestinationSuggestions.maxSuggestions)
    #expect(CampusGate.suggestions(query: "c", completions: many, from: nil, campusEnabled: false).isEmpty)
}

@Test func searchCentreNeverFallsBackToTheCampusWhenClosed() {
    let fix = Coordinate(latitude: 47.66, longitude: -122.31)
    let demo = Coordinate(latitude: 47.658324, longitude: -122.313219)
    #expect(CampusGate.searchCentre(fix: fix, campusEnabled: false, fallback: demo) == fix)
    #expect(CampusGate.searchCentre(fix: fix, campusEnabled: true, fallback: demo) == fix)
    #expect(CampusGate.searchCentre(fix: nil, campusEnabled: true, fallback: demo) == CampusPlaces.center)
    #expect(CampusGate.searchCentre(fix: nil, campusEnabled: false, fallback: demo) == demo)
    #expect(CampusGate.searchCentre(fix: nil, campusEnabled: false, fallback: nil) == nil)
}

// MARK: - Indoor card

@Test func recordingIdIsNeutralWhenClosed() {
    #expect(CampusGate.defaultRecordingID(campusEnabled: true) == IndoorScriptCatalog.defaultRecordingID)
    #expect(CampusGate.defaultRecordingID(campusEnabled: false) == "indoor_route")
    #expect(CampusGate.sanitizedRecordingID("", campusEnabled: false) == "indoor_route")
    #expect(CampusGate.sanitizedRecordingID("   ", campusEnabled: true) == IndoorScriptCatalog.defaultRecordingID)
    #expect(CampusGate.sanitizedRecordingID("My Route", campusEnabled: false) == IndoorScriptCatalog.sanitizedID("My Route"))
    #expect(CampusGate.sanitizedRecordingID("My Route", campusEnabled: true) == "my_route")
    #expect(!mentionsUIUC(CampusGate.defaultRecordingID(campusEnabled: false)))
}

/// The bundled ISR draft, read from the repo (ios/CaneKit/Resources/indoor_isr.json).
private func isrDraft() throws -> IndoorScript {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("../CaneKit/Resources/indoor_isr.json").standardized
    return try IndoorScript.load(from: Data(contentsOf: url))
}

/// Review of f02771d (finding 2): a recording already on the phone under the old ISR id, or tied to
/// the ISR outdoor place, carries "Townsend Hall to the ISR front doors" — skipped when closed.
@Test func recordedIsrScriptsAreSkippedWhenClosed() throws {
    let draft = try isrDraft()
    #expect(CampusGate.loadsRecorded(draft, campusEnabled: false) == false)
    #expect(CampusGate.loadsRecorded(draft, campusEnabled: true) == true)
    var renamed = draft
    renamed.id = "my_route"                         // still outdoorPlaceID "isr"
    #expect(CampusGate.loadsRecorded(renamed, campusEnabled: false) == false)
    var sameID = draft
    sameID.outdoorPlaceID = ""                      // still the old default id
    #expect(CampusGate.loadsRecorded(sameID, campusEnabled: false) == false)
    var neutral = draft
    neutral.id = "indoor_route"
    neutral.outdoorPlaceID = CampusGate.recordingOutdoorPlaceID(campusEnabled: false)
    #expect(CampusGate.loadsRecorded(neutral, campusEnabled: false) == true)
}

@Test func newRecordingsNameNoCampusPlaceWhenClosed() {
    #expect(CampusGate.recordingOutdoorPlaceID(campusEnabled: true) == "isr")
    #expect(CampusGate.recordingOutdoorPlaceID(campusEnabled: false) == "")
}

/// With the gate closed a named outdoor leg is always a MapKit route in the walker's words ("CIF"
/// included); only no destination walks the demo route. Open: `IndoorScriptCatalog.outdoorLeg`.
@Test func closedGateOutdoorLegIsMapKitForAnyNamedDestination() {
    #expect(CampusGate.outdoorLeg(destination: "CIF", campusEnabled: false) == .navigate("CIF"))
    #expect(CampusGate.outdoorLeg(destination: " Starbucks ", campusEnabled: false) == .navigate("Starbucks"))
    #expect(CampusGate.outdoorLeg(destination: nil, campusEnabled: false) == .demoRoute)
    #expect(CampusGate.outdoorLeg(destination: "  ", campusEnabled: false) == .demoRoute)
    for d in ["CIF", "the CIF east entrance", "Starbucks", nil, ""] as [String?] {
        #expect(CampusGate.outdoorLeg(destination: d, campusEnabled: true) == IndoorScriptCatalog.outdoorLeg(destination: d))
    }
}

@Test func indoorHintsKeepTheIsrWordingOnlyWhenOpen() {
    #expect(CampusGate.routeNameHint(campusEnabled: true)
            == "Saved under this name; using the ISR name replaces the floor-plan draft")
    #expect(CampusGate.startIndoorHint(campusEnabled: true)
            == "Walks the saved ISR indoor route, then the route to CIF")
    #expect(CampusGate.routeNameHint(campusEnabled: false) == "Saved under this name")
    #expect(CampusGate.startIndoorHint(campusEnabled: false) == "Walks the saved indoor route, then the demo route")
    #expect(!mentionsUIUC(CampusGate.routeNameHint(campusEnabled: false)))
    #expect(!mentionsUIUC(CampusGate.startIndoorHint(campusEnabled: false)))
}
