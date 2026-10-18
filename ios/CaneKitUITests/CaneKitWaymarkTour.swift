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
//
//  ⚠ Simulator only. "Simulate walk" fixes never become evidence (WaymarkEngine.simulating), so
//  these pictures show the interface, not field data. The switch this test turns on is turned off
//  again in `tearDown` from a fresh launch, whatever state the test body ended in (review 4); the
//  other UI test classes also launch with `-waymarkEnabled NO`.
//  New accessibility labels used here: "Sidewalk memory off. Turn on" (the chip), "Done" (sheet).
//

import XCTest

/// Screenshot tour of sidewalk memory. Keeps going after a failure so one missing control does not
/// cost the remaining shots.
final class CaneKitWaymarkTour: XCTestCase {

    /// The app under test.
    private var app: XCUIApplication!
    /// Running shot counter.
    private var shotIndex = 0

    /// Fresh launch on the default route, sidewalk memory forced to its shipped default (off) for
    /// this launch through the argument domain.
    override func setUp() {
        continueAfterFailure = true
        allowLocationPrompts()
        app = XCUIApplication()
        app.launchEnvironment["CANEKIT_UITEST"] = "1"
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
