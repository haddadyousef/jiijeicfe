//
//  CampusGate.swift
//  CaneKitLogic
//
//  waymark (owner, 2026-10-17): the default build never shows or speaks the University of Illinois.
//  The base app's UIUC content — the `CampusPlaces` gazetteer, the ISR indoor script and the ISR → CIF
//  route — stays in the code and its tests unchanged, but the app reaches it only through this gate,
//  which is open only under `WAYMARK_DEMO_ROUTE=isr_cif` (the XCUITests and `ios/scripts/e2e.py` set
//  it and assert on UIUC strings). The indoor half is also open under `CANEKIT_INDOOR_ROUTE=1`, the
//  existing indoor automation hook (e2e `indoor_isr`).
//
//  Callers (app, main actor): `RouteSource.uiucDemo` (= `enabled`), `IndoorGuide.campusIndoor`
//  (= `indoorEnabled`), `ConversationCoordinator.handleQuery` (`allows` + `rewrite`), `RouteSource.mapKit`
//  (`match`), `DestinationSearch` (`suggestions`, `searchCentre`), `IndoorGuide` / `AppModel+Indoor` /
//  `IndoorRecordCard` (`loadsRecorded`, `outdoorLeg`, `recordingOutdoorPlaceID`, `defaultRecordingID`,
//  `sanitizedRecordingID`, the two hints).
//
//  Key invariants:
//    · With the gate open every function returns exactly what the base app computed before
//      (`closedGateOffersNoCampusRows`, `indoorHintsKeepTheIsrWordingOnlyWhenOpen`, …).
//    · ⚠ `FastPathIntentClassifier` is not touched: the gate rewrites a classified campus route after
//      the fact (`rewrite`: a MapKit search in the walker's words), so the voice shell's tests stay
//      byte-identical.
//  Pure: Foundation only, stateless. Tests: CampusGateTests.swift.
//

import Foundation

/// The one switch between the default (Seattle) build and the UIUC demo, and what follows from it.
public enum CampusGate {

    /// The environment variable that selects the demo route (`RouteSource.bundled`).
    public static let demoRouteKey = "WAYMARK_DEMO_ROUTE"
    /// Its value for the original UIUC route, ISR Townsend Hall → CIF.
    public static let uiucDemoValue = "isr_cif"
    /// The existing indoor automation hook (`IndoorGuide.attach` starts the ISR script at launch).
    public static let indoorRouteKey = "CANEKIT_INDOOR_ROUTE"
    /// The id a new indoor recording gets in the default build (the UIUC build keeps the ISR draft's).
    public static let neutralRecordingID = "indoor_route"

    // MARK: The switch

    /// True only when `WAYMARK_DEMO_ROUTE` is exactly `isr_cif`. Read once by `RouteSource.uiucDemo`.
    /// - Parameter environment: the process environment.
    public static func enabled(environment: [String: String]) -> Bool {
        environment[demoRouteKey] == uiucDemoValue
    }

    /// The indoor ISR script (bundled `indoor_isr.json`, hand-over to the UIUC route): open with
    /// `enabled`, or with `CANEKIT_INDOOR_ROUTE=1`, so the indoor automation keeps today's behaviour.
    /// - Parameter environment: the process environment.
    public static func indoorEnabled(environment: [String: String]) -> Bool {
        enabled(environment: environment) || environment[indoorRouteKey] == "1"
    }

    // MARK: Voice fast path

    /// Whether a fast-path result runs as classified. False only with the gate closed and a route to or
    /// from a gazetteer place ("take me to the union" → `.startRoute("the Illini Union")`, "take me from
    /// ISR to CIF"); the coordinator then runs `rewrite` instead and logs `conv_campus_gated`.
    /// - Parameters:
    ///   - action: `FastPathIntentClassifier.classify(query:)`'s result.
    ///   - campusEnabled: `RouteSource.uiucDemo`.
    public static func allows(_ action: ConversationAction, campusEnabled: Bool) -> Bool {
        guard !campusEnabled else { return true }
        switch action {
        case .startRoute(let destination):
            return CampusPlaces.match(destination) == nil
        case .routeFromTo(let from, let to):
            return CampusPlaces.match(from) == nil && CampusPlaces.match(to) == nil
        default:
            return true
        }
    }

    /// What the coordinator runs for a fast-path result (review of f02771d, finding 1). Open, or an
    /// action that touches no campus place: `action` unchanged. Closed:
    ///   · a campus `.startRoute` ("take me to the union" → `.startRoute("the Illini Union")`) becomes
    ///     a MapKit search in the walker's own words, `.startRoute("Union")` — the longest alias of
    ///     that place found word-for-word in `query`, as said, each word's first letter upper-cased
    ///     except an inner "the" / "and"; never the canonical UIUC name. Words not found → nil (the
    ///     coordinator then treats the query as unclassified).
    ///   · a `.routeFromTo` passes unchanged: the classifier already keeps both ends as said, and with
    ///     the gate closed the app consults no gazetteer for it (no ISR script loads —
    ///     `loadsRecorded`; `outdoorLeg` navigates to the words).
    /// - Parameters:
    ///   - action: `FastPathIntentClassifier.classify(query:)`'s result.
    ///   - query: the walker's utterance it came from.
    ///   - campusEnabled: `RouteSource.uiucDemo`.
    public static func rewrite(_ action: ConversationAction, query: String, campusEnabled: Bool) -> ConversationAction? {
        guard !campusEnabled, case .startRoute(let destination) = action,
              let place = CampusPlaces.match(destination) else { return action }
        return saidWords(for: place, in: query).map { .startRoute(destination: $0) }
    }

    /// The longest alias of `place` that occurs as whole words in `query` (compared after
    /// `CampusPlaces.normalize`, word by word), returned as the walker said it, or nil.
    static func saidWords(for place: CampusPlace, in query: String) -> String? {
        let edge = CharacterSet.punctuationCharacters.union(.symbols)
        let said = query.split(whereSeparator: \.isWhitespace).map { String($0).trimmingCharacters(in: edge) }
        // One entry per normalized token, remembering which spoken word it came from.
        var tokens: [(key: Substring, word: Int)] = []
        for (i, w) in said.enumerated() {
            for key in CampusPlaces.normalize(w).split(separator: " ") { tokens.append((key, i)) }
        }
        let aliases = place.aliases.map { CampusPlaces.normalize($0).split(separator: " ") }
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }
        for alias in aliases where alias.count <= tokens.count {
            for start in 0...(tokens.count - alias.count)
            where tokens[start..<(start + alias.count)].map(\.key) == alias {
                let words = said[tokens[start].word...tokens[start + alias.count - 1].word]
                return words.enumerated().map { j, w in
                    j > 0 && CampusPlaces.fillerWords.contains(w.lowercased()) ? w : w.prefix(1).uppercased() + w.dropFirst()
                }.joined(separator: " ")
            }
        }
        return nil
    }

    // MARK: Typed destination

    /// `CampusPlaces.match(query)` with the gate open, nil (MapKit searches) with it closed.
    /// Caller: `RouteSource.mapKit(to:from:)`.
    public static func match(_ query: String, campusEnabled: Bool) -> CampusPlace? {
        campusEnabled ? CampusPlaces.match(query) : nil
    }

    /// The destination box's rows. Open: `DestinationSuggestions.suggestions` unchanged. Closed: no
    /// gazetteer rows — the completer rows only, with the same minimum length, country filter,
    /// de-duplication and cap (none dropped as a re-spelling of a campus place).
    /// Caller: `DestinationSearch.republish`.
    public static func suggestions(query: String, completions: [CompletionLine], from origin: Coordinate?,
                                   locality: Locality = .campus, campusEnabled: Bool) -> [DestinationSuggestion] {
        if campusEnabled {
            return DestinationSuggestions.suggestions(query: query, completions: completions, from: origin,
                                                      locality: locality)
        }
        guard CampusPlaces.normalize(query).count >= DestinationSuggestions.minimumQueryLength else { return [] }
        let local = completions.filter { locality.plausiblyNearby(subtitle: $0.subtitle) }
        return Array(DestinationSuggestions.mapRows(local, excluding: []).prefix(DestinationSuggestions.maxSuggestions))
    }

    /// Where the completer is centred: the fix; with none, the campus centre (gate open, today) or
    /// `fallback` (gate closed — the app passes the demo route's first waypoint). Nil = no bias.
    /// Caller: `DestinationSearch.ask`.
    public static func searchCentre(fix: Coordinate?, campusEnabled: Bool, fallback: Coordinate?) -> Coordinate? {
        fix ?? (campusEnabled ? CampusPlaces.center : fallback)
    }

    // MARK: Indoor card

    /// The Settings "Route name" field's default: the ISR draft's id (open) or `neutralRecordingID`.
    public static func defaultRecordingID(campusEnabled: Bool) -> String {
        campusEnabled ? IndoorScriptCatalog.defaultRecordingID : neutralRecordingID
    }

    /// `IndoorScriptCatalog.sanitizedID`, except that a blank name becomes `defaultRecordingID(campusEnabled:)`.
    public static func sanitizedRecordingID(_ raw: String, campusEnabled: Bool) -> String {
        guard raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return IndoorScriptCatalog.sanitizedID(raw)
        }
        return defaultRecordingID(campusEnabled: campusEnabled)
    }

    /// Whether a recorded Documents/indoor script loads (review of f02771d, finding 2). Closed: not
    /// one saved under the ISR draft's id or tied to the ISR outdoor place (`outdoorPlaceID == "isr"`)
    /// — it carries "Townsend Hall to the ISR front doors" and the ISR exit line. Caller:
    /// `IndoorGuide.reloadScripts`, which logs `indoor {action: campus_skipped, id}` for each.
    public static func loadsRecorded(_ script: IndoorScript, campusEnabled: Bool) -> Bool {
        campusEnabled || (script.id != IndoorScriptCatalog.defaultRecordingID && script.outdoorPlaceID != "isr")
    }

    /// `outdoorPlaceID` of a new recording with no catalog script of the same id: "isr" (open, the
    /// base app's) or "" (closed: no campus place, so `loadsRecorded` keeps it). Caller:
    /// `IndoorGuide.saveRecording`.
    public static func recordingOutdoorPlaceID(campusEnabled: Bool) -> String {
        campusEnabled ? "isr" : ""
    }

    /// The outdoor leg after an indoor walk. Open: `IndoorScriptCatalog.outdoorLeg` (a CIF alias →
    /// the UIUC demo route). Closed: any named destination is a MapKit route to the trimmed words, so
    /// "CIF" is searched as said; none → the demo route (`RouteSource.bundled()`).
    /// Callers: `IndoorGuide.start` (trip name) and `IndoorGuide.handOver`.
    public static func outdoorLeg(destination: String?, campusEnabled: Bool) -> IndoorOutdoorLeg {
        if campusEnabled { return IndoorScriptCatalog.outdoorLeg(destination: destination) }
        let text = (destination ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? .demoRoute : .navigate(text)
    }

    /// VoiceOver hint of the "Route name" field.
    public static func routeNameHint(campusEnabled: Bool) -> String {
        campusEnabled ? "Saved under this name; using the ISR name replaces the floor-plan draft"
                      : "Saved under this name"
    }

    /// VoiceOver hint of "Start indoor route".
    public static func startIndoorHint(campusEnabled: Bool) -> String {
        campusEnabled ? "Walks the saved ISR indoor route, then the route to CIF"
                      : "Walks the saved indoor route, then the demo route"
    }
}
