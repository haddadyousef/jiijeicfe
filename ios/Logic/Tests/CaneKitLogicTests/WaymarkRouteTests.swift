//
//  WaymarkRouteTests.swift
//  CaneKitLogicTests
//
//  Waymark D-35: the Seattle demo route shipped in the app bundle
//  (`ios/CaneKit/Resources/route_ave_seattle.json`) is byte-identical to the pipeline's
//  `waymark/demo/route.json` (W owns that file; the bundle is a copy so the untethered phone can
//  walk it), decodes with the base app's `Route.load`, and keeps the facts the demo depends on.
//  When W regenerates the route (`wm_pipeline.run demo`), copy the file again; this test fails
//  until you do. The UIUC route and its tests (RouteTests.swift) are untouched.
//

import Foundation
import Testing
@testable import CaneKitLogic

/// ios/ (this file is ios/Logic/Tests/CaneKitLogicTests/…).
private let iosDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

@Test func seattleRouteBundleMatchesThePipelineFile() throws {
    let bundled = try Data(contentsOf: iosDir.appendingPathComponent("CaneKit/Resources/route_ave_seattle.json"))
    let source = try Data(contentsOf: iosDir.appendingPathComponent("../waymark/demo/route.json").standardized)
    #expect(bundled == source, "copy waymark/demo/route.json to ios/CaneKit/Resources/route_ave_seattle.json")
}

@Test func seattleRouteIsTheAveWalk() throws {
    let r = try Route.load(from: Data(contentsOf: iosDir.appendingPathComponent("CaneKit/Resources/route_ave_seattle.json")))
    #expect(r.name == "The Ave and NE 42nd to The Ave and NE 50th")
    #expect(r.waypoints.count == 9)
    #expect(r.waypoints.map(\.id) == Array(1...9))
    #expect(r.waypoints.filter(\.crossing).count == 3)
    let start = try #require(r.waypoints.first)
    // D-35: the simulator parks here (ios/Makefile SIM_LAT / SIM_LON).
    #expect(abs(start.lat - 47.658324) < 1e-9 && abs(start.lon - -122.313219) < 1e-9)
    // Straight north on University Way NE: every leg heads within 20° of north.
    for (a, b) in zip(r.waypoints, r.waypoints.dropFirst()) {
        let bearing = GeoMath.bearingDegrees(from: a.coordinate, to: b.coordinate)
        #expect(min(bearing, 360 - bearing) < 20, "leg \(a.id)→\(b.id) bearing \(bearing)")
    }
    let length = zip(r.waypoints, r.waypoints.dropFirst())
        .map { GeoMath.distanceMeters($0.coordinate, $1.coordinate) }.reduce(0, +)
    #expect(abs(length - 727) < 40, "D-34 says 727 m; got \(length)")
}
