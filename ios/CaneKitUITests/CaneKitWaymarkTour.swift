//
//  CaneKitWaymarkTour.swift
//  CaneKitUITests
//
//  Judge-demo camera for sidewalk memory (`make tour-waymark` → ios/build/shots-waymark). Runs on
//  the default demo route (the Seattle Ave walk; no WAYMARK_DEMO_ROUTE) with the bundled Project
//  Sidewalk priors, starting from the shipped default: sidewalk memory OFF.
//
//  Shots, in order (each "wm-NN-…"):
//    01 guide-off          the Guide chip "Sidewalk memory off · Turn on"
//    02 sheet-off          the chip opens the existing Sidewalk memory card in a sheet
//    03 sheet-on           after flipping its switch: "N sidewalk reports loaded."
//    04 map                "Map of reports": the Ave route's reports, coloured and shaped by belief
//    05 map-pin            the first obstacle pin tapped: type, confidence, street-imagery date,
//                          Project Sidewalk votes
//    06 guide-on           the chip now says how many reports are loaded
//    07 walking-ahead      Simulate walk: the card under Stop names the nearest report ahead
//    08 learning-card      task 3: walk stopped, GPS parked 3 m from the fire-hydrant obstacle
//                          ps:13292406 (5 agree / 5 disagree → 50 %), spotter "Not there", undo window
//                          over: the card's learning row "Not there · 50 % → 43 % · spotter" (6 / 14)
//    09 learning-pin       the same report on the map: dot badge, details with the learning line
//    10 learning-relaunch  after terminate + relaunch with `-waymarkEnabled YES`: the pin still 43 %
//                          likely, "Checked on this phone before" (beliefs.json restored by
//                          WaymarkSession.restore)
//
//  Task 3 store isolation: every run gets its own `WAYMARK_STORE_SUBDIR` ("wm-ui-" + 8 characters
//  of a UUID, short so the card's caption stays one line; honoured only with CANEKIT_UITEST=1), kept
//  across the relaunch, so the tour starts from the bundled priors and never reads or writes the
//  real Documents/waymark/beliefs.json. Folders left by earlier runs are deleted at load
//  (`WaymarkStore.removeStaleTestFolders`, UI tests only). The spotter tap here is a real
//  (non-simulated) idle GPS fix, so it is recorded like field evidence — in the throwaway folder only.
//  VoiceOver words, not the visible ones, are what XCUITest reads where a view sets them: the
//  learning row is asserted as "Spotter said not there. Confidence went from 50 to 43 percent.",
//  the confidence line as "43 percent likely".
//
//  ⚠ Simulator only. "Simulate walk" fixes never become evidence (WaymarkEngine.simulating), so
//  these pictures show the interface, not field data. The switch this test turns on is turned off
//  again in `tearDown` from a fresh launch, whatever state the test body ended in (review 4); the
//  other UI test classes also launch with `-waymarkEnabled NO`. That launch-argument mask only
//  works since the task 3 review: the argument domain hands "NO" / "YES" over as a String, which
//  `Settings.bool` used to read (`as? Bool`) as unset; it now goes through `StoredBool.parse`, so a
//  run killed before `tearDown` (switch left on) no longer leaks into the next class.
//  New accessibility labels used here: "Sidewalk memory off. Turn on" (the chip), "Done" (sheet);
//  task 3: identifiers "waymark-learning" (card row), "waymark-pin-learning" (map details),
//  "waymark-pin-ps:13292406" (the pin, task 2's identifier scheme).
//

import XCTest
import CoreLocation

/// Screenshot tour of sidewalk memory. Keeps going after a failure so one missing control does not
/// cost the remaining shots.
final class CaneKitWaymarkTour: XCTestCase {

    /// The app under test.
    private var app: XCUIApplication!
    /// Running shot counter.
    private var shotIndex = 0
    /// Task 3: the fire-hydrant obstacle on the Ave route (5 agree / 5 disagree → p = 0.5).
    private let hydrantID = "ps:13292406"

    /// Fresh launch on the default route, sidewalk memory forced to its shipped default (off) for
    /// this launch through the argument domain (`-waymarkEnabled NO`, read by `StoredBool.parse`;
    /// the stored value is not touched).
    override func setUp() {
        continueAfterFailure = true
        allowLocationPrompts()
        app = XCUIApplication()
        app.launchEnvironment["CANEKIT_UITEST"] = "1"
        // Task 3: a fresh throwaway store per run, kept across the relaunch in the test body
        // (review: a short name, so the judge-facing caption is one line, not a UUID over three).
        app.launchEnvironment["WAYMARK_STORE_SUBDIR"] = "wm-ui-" + String(UUID().uuidString.prefix(8))
        app.launchArguments += ["-waymarkEnabled", "NO"]
        app.launch()
    }

    /// Off chip → sheet → on → Guide chip → simulated walk with the ahead card.
    func testWaymarkTour() {
        XCTAssertTrue(app.buttons["Start route"].waitForExistence(timeout: 10))
        let offChip = app.buttons["Sidewalk memory off. Turn on"]
        XCTAssertTrue(offChip.waitForExistence(timeout: 5), "the Guide offers sidewalk memory while it is off")
        snap("guide-off")

        offChip.tap()
        let toggle = app.switches["Sidewalk memory"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "the chip opens the existing switch")
        snap("sheet-off")
        flip(toggle)
        XCTAssertTrue(text(containing: "sidewalk reports loaded").waitForExistence(timeout: 15))
        pause(0.5); snap("sheet-on")

        // Task 2: the map of reports, then one pin's details.
        let mapButton = app.buttons["Map of reports"]
        XCTAssertTrue(mapButton.waitForExistence(timeout: 5))
        mapButton.tap()
        XCTAssertTrue(text(containing: "on this map").waitForExistence(timeout: 10))
        pause(2.5); snap("map")
        // Pins are buttons with identifier "waymark-pin-<id>" (review 5); a hittable obstacle one.
        let obstacles = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@", "waymark-pin-", "Reported obstacle"))
        _ = obstacles.firstMatch.waitForExistence(timeout: 5)
        if let obstacle = obstacles.allElementsBoundByIndex.first(where: { $0.isHittable }) {
            obstacle.tap()
            XCTAssertTrue(text(containing: "Street imagery").waitForExistence(timeout: 5))
            pause(0.8); snap("map-pin")
        } else {
            XCTFail("no obstacle pin on the map")
        }
        // Each sheet's own Done (review 4: two Done buttons are in the tree while the map is up).
        app.navigationBars["Map of reports"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Map of reports"].waitForNonExistence(timeout: 5))
        app.navigationBars["Sidewalk memory"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Sidewalk memory"].waitForNonExistence(timeout: 5))

        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Sidewalk memory on")).firstMatch
                        .waitForExistence(timeout: 5))
        snap("guide-on")

        // Simulate walk: synthetic fixes along the Ave; the card names the first report ahead.
        scrollTo(app.buttons["Simulate walk"]).tap()
        XCTAssertTrue(app.buttons["Stop route"].waitForExistence(timeout: 10))
        let ahead = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Sidewalk memory. Reported")).firstMatch
        XCTAssertTrue(ahead.waitForExistence(timeout: 30), "the ahead card names a report while walking")
        scrollToTop(); pause(0.5)
        snap("walking-ahead")

        learningShots()
    }

    /// Task 3: a spotter "Not there" on the fire hydrant, its learning on the card and the map, and
    /// the belief still there after a relaunch.
    private func learningShots() {
        // Stop the simulation and the route (two taps, as the other tours do).
        scrollTo(app.buttons["Stop route"]).tap()
        if app.buttons["Stop route"].exists { app.buttons["Stop route"].tap() }
        XCTAssertTrue(app.buttons["Start route"].waitForExistence(timeout: 10), "the walk stopped")
        // Park the GPS 3 m south of the hydrant; a fresh real fix (spotter taps need one < 5 s old).
        XCUIDevice.shared.location = XCUILocation(location: CLLocation(latitude: 47.66021, longitude: -122.313309))
        pause(2)
        scrollToTop()
        let onChip = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Sidewalk memory on")).firstMatch
        XCTAssertTrue(onChip.waitForExistence(timeout: 5), "the idle chip is back")
        onChip.tap()
        let notThere = app.buttons["Not there"]
        XCTAssertTrue(notThere.waitForExistence(timeout: 5), "the sheet shows the spotter buttons")
        // The tap needs a fix younger than 5 s. Review: scroll first (up to 12 swipes, ~1 s each),
        // then nudge the GPS, then tap without scrolling, so the fix cannot age past 5 s.
        scrollTo(notThere)
        XCUIDevice.shared.location = XCUILocation(location: CLLocation(latitude: 47.660211, longitude: -122.313309))
        pause(1.5)
        notThere.tap()
        XCTAssertTrue(text(containing: "Not there: obstacle").waitForExistence(timeout: 5), "the undo toast names the obstacle")
        pause(11)                                               // undo window (10 s) → committed
        let row = app.descendants(matching: .any).matching(identifier: "waymark-learning").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the card shows what the tap did")
        let rowLabel = row.exists ? row.label : ""
        XCTAssertTrue(rowLabel.contains("Spotter said not there"), rowLabel)
        XCTAssertTrue(rowLabel.contains("from 50 to 43 percent"), rowLabel)   // 6 / 14 = 0.4286
        XCTAssertTrue(text(containing: "beliefs.json").exists, "the card says where the belief is saved")
        scrollTo(row); pause(0.5)
        snap("learning-card")

        // The same report on the map.
        scrollTo(app.buttons["Map of reports"]).tap()
        XCTAssertTrue(text(containing: "on this map").waitForExistence(timeout: 10))
        pause(2.5)
        XCTAssertTrue(selectHydrantPin(), "the hydrant pin opens its details")
        let detail = app.descendants(matching: .any).matching(identifier: "waymark-pin-learning").firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 5), "the pin's details show what was learned")
        let detailLabel = detail.exists ? detail.label : ""
        XCTAssertTrue(detailLabel.contains("from 50 to 43 percent"), detailLabel)
        let pin = app.buttons["waymark-pin-\(hydrantID)"]
        XCTAssertTrue(pin.exists && pin.label.hasSuffix("checked on this phone"), pin.exists ? pin.label : "no pin")
        pause(0.8); snap("learning-pin")
        app.navigationBars["Map of reports"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Map of reports"].waitForNonExistence(timeout: 5))
        app.navigationBars["Sidewalk memory"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Sidewalk memory"].waitForNonExistence(timeout: 5))

        // Persistence: a fresh process, same store folder, sidewalk memory forced on for this launch
        // (`-waymarkEnabled YES`; `StoredBool.parse` reads the argument domain's "YES" string since
        // the task 3 review — before it, this read as unset → off, run j3-tour 21:19).
        app.terminate()
        app.launchArguments = ["-waymarkEnabled", "YES"]
        app.launch()
        let chip = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Sidewalk memory on")).firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 15), "sidewalk memory is on after the relaunch")
        chip.tap()
        let mapButton = app.buttons["Map of reports"]
        XCTAssertTrue(mapButton.waitForExistence(timeout: 15))
        mapButton.tap()
        XCTAssertTrue(text(containing: "on this map").waitForExistence(timeout: 10))
        pause(2.5)
        XCTAssertTrue(selectHydrantPin(), "the hydrant pin opens its details after the relaunch")
        XCTAssertTrue(text(containing: "43 percent likely").waitForExistence(timeout: 5), "the belief survived")
        XCTAssertTrue(text(containing: "Checked on this phone before").waitForExistence(timeout: 5))
        pause(0.8); snap("learning-relaunch")
        app.navigationBars["Map of reports"].buttons["Done"].tap()
        _ = app.navigationBars["Map of reports"].waitForNonExistence(timeout: 5)
        app.navigationBars["Sidewalk memory"].buttons["Done"].tap()
    }

    /// Zooms the map in around the hydrant pin (the Ave's pins overlap at route zoom, which hid it
    /// under a neighbour in the first shots) and taps it; if another pin still took the tap, zooms
    /// further and taps again. True once the hydrant pin is the selected one.
    private func selectHydrantPin() -> Bool {
        let pin = app.buttons["waymark-pin-\(hydrantID)"]
        guard pin.waitForExistence(timeout: 5) else { return false }
        for attempt in 0..<3 {
            if app.buttons["Close details"].exists { app.buttons["Close details"].tap() }
            pin.pinch(withScale: attempt == 0 ? 3 : 2, velocity: 2)
            pause(1.5)
            pin.tap()
            pause(0.8)
            if pin.isSelected { return true }
        }
        return false
    }

    /// Turns the stored switch back off from a fresh, idle launch (no route), whatever the test left.
    override func tearDown() {
        if let app {
            // Same app object, relaunched without the "-waymarkEnabled NO" mask (a second
            // XCUIApplication launched right after terminate raced: "No such process", 20:31).
            app.terminate()
            app.launchArguments = []
            app.launch()
            let clean = app
            let on = clean.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Sidewalk memory on")).firstMatch
            if on.waitForExistence(timeout: 8) {
                on.tap()
                let toggle = clean.switches["Sidewalk memory"]
                if toggle.waitForExistence(timeout: 5) { flip(toggle) }
                XCTAssertTrue(clean.buttons["Sidewalk memory off. Turn on"].waitForExistence(timeout: 5)
                              || clean.staticTexts["Off."].waitForExistence(timeout: 2))
                if clean.buttons["Done"].exists { clean.buttons["Done"].tap() }
            }
            clean.terminate()
        }
        super.tearDown()
    }

    // MARK: Helpers (same behaviour as CaneKitVisualTour's)

    /// A static text whose label contains `words`.
    private func text(containing words: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", words)).firstMatch
    }

    /// Full-screen PNG as "wm-NN-<name>" into `$CANEKIT_SHOTS` and the .xcresult.
    private func snap(_ name: String) {
        shotIndex += 1
        let png = XCUIScreen.main.screenshot().pngRepresentation
        let file = String(format: "wm-%02d-%@", shotIndex, name)
        if let dir = ProcessInfo.processInfo.environment["CANEKIT_SHOTS"] {
            try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(file).png"))
        }
        let a = XCTAttachment(uniformTypeIdentifier: "public.png", name: file, payload: png)
        a.lifetime = .keepAlways
        add(a)
    }

    /// Swipes until `element` is hittable (four up, then eight down).
    @discardableResult
    private func scrollTo(_ element: XCUIElement) -> XCUIElement {
        var ups = 0
        while ups < 4, !(element.exists && element.isHittable) { app.swipeUp(); ups += 1 }
        var downs = 0
        while downs < 8, !(element.exists && element.isHittable) { app.swipeDown(); downs += 1 }
        return element
    }

    /// Four swipes down plus a settle.
    private func scrollToTop() {
        for _ in 0..<4 { app.swipeDown() }
        pause(0.4)
    }

    /// Spins the run loop for `s` seconds.
    private func pause(_ s: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(s))
    }

    /// Toggle tap helper; identical to `CaneKitUITests.flip(_:)`.
    private func flip(_ toggle: XCUIElement) {
        let knob = toggle.switches.firstMatch
        if knob.exists, knob != toggle { knob.tap() }
        else { toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap() }
    }
}
