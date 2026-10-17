//
//  WaymarkPriorTests.swift
//  CaneKitLogicTests
//
//  Pins the `waymark.priors.v1` decoder (WAYMARK_PLAN v1.1 §5.2): the shipped example decodes
//  exactly, unknown label types become `.other` instead of failing, and every field rule rejects
//  the whole bundle (an inert feature is safer than a half-trusted one).
//  Source pinned: `ios/Logic/Sources/CaneKitLogic/Waymark/WaymarkPrior.swift`.
//  The inline `example` is the plan's §5.2 JSON verbatim. When `waymark/contracts/golden/
//  priors_sample.json` lands, a test reads that file too; the two must agree (plan 7.3).
//

import Foundation
import Testing
@testable import CaneKitLogic

/// WAYMARK_PLAN v1.1 §5.2, verbatim.
private let example = #"""
{
  "schema": "waymark.priors.v1",
  "generated_at": "2026-10-17T21:00:00Z",
  "source": {
    "name": "Project Sidewalk",
    "license": "CC0-1.0",
    "base_url": "https://sidewalk-sea.cs.washington.edu",
    "street_geometry": "OpenStreetMap contributors, ODbL"
  },
  "bbox_lnglat": [-122.3080, 47.6520, -122.3020, 47.6560],
  "labels": [
    {
      "id": "ps:13290420",
      "type": "curb_ramp",
      "lat": 47.652233,
      "lng": -122.306389,
      "severity": 1,
      "tags": [],
      "n_agree": 2,
      "n_disagree": 0,
      "n_unsure": 0,
      "cluster_size": 1,
      "street_edge_id": 20109,
      "intersection_id": null,
      "osm_way_id": 283038445,
      "imagery_date": "2019-05",
      "label_date": "2019-07",
      "source_cluster_id": 13290420
    }
  ]
}
"""#

/// A bundle around `labels` (JSON label objects), with optional schema and bbox overrides.
private func bundle(labels: [String], schema: String = "waymark.priors.v1",
                    bbox: String = "[-122.3080, 47.6520, -122.3020, 47.6560]") -> Data {
    Data(#"{"schema":"\#(schema)","generated_at":"2026-10-17T21:00:00Z","source":{"name":"Project Sidewalk"},"bbox_lnglat":\#(bbox),"labels":[\#(labels.joined(separator: ","))]}"#.utf8)
}

/// A minimal valid label; `extra` is appended inside the object (a leading comma included).
private func label(id: Int = 1, type: String = "obstacle", lat: String = "47.654", lng: String = "-122.305",
                   severity: String = "2", extra: String = "") -> String {
    #"{"id":"ps:\#(id)","type":"\#(type)","lat":\#(lat),"lng":\#(lng),"severity":\#(severity),"tags":[],"n_agree":1,"n_disagree":0,"n_unsure":0,"cluster_size":1,"street_edge_id":null,"intersection_id":null,"osm_way_id":null,"imagery_date":null,"label_date":null,"source_cluster_id":\#(id)\#(extra)}"#
}

@Test func planExampleDecodesExactly() throws {
    let set = try WaymarkPriorSet.decode(Data(example.utf8))
    #expect(set.generatedAt == "2026-10-17T21:00:00Z")
    #expect(set.sourceName == "Project Sidewalk")
    #expect(set.bboxLngLat == [-122.3080, 47.6520, -122.3020, 47.6560])
    #expect(set.labels.count == 1)
    let p = try #require(set.labels.first)
    #expect(p.id == "ps:13290420")
    #expect(p.type == .curbRamp)
    #expect(p.lat == 47.652233 && p.lng == -122.306389)
    #expect(p.severity == 1)
    #expect(p.tags == [])
    #expect(p.nAgree == 2 && p.nDisagree == 0 && p.nUnsure == 0 && p.clusterSize == 1)
    #expect(p.streetEdgeID == 20109 && p.intersectionID == nil && p.osmWayID == 283038445)
    #expect(p.imageryDate == "2019-05" && p.labelDate == "2019-07")
    #expect(p.sourceClusterID == 13290420)
    #expect(p.coordinate == Coordinate(latitude: 47.652233, longitude: -122.306389))
}

@Test func everyLabelTypeRoundTrips() throws {
    #expect(WaymarkLabelType.allCases.count == 7)
    for t in WaymarkLabelType.allCases {
        let data = try JSONEncoder().encode(t)
        #expect(try JSONDecoder().decode(WaymarkLabelType.self, from: data) == t)
    }
    #expect(WaymarkLabelType.allCases.map(\.rawValue) ==
            ["curb_ramp", "missing_curb_ramp", "obstacle", "surface_problem", "no_sidewalk", "crosswalk", "other"])
}

@Test func unknownLabelTypeDecodesToOther() throws {
    let set = try WaymarkPriorSet.decode(bundle(labels: [label(type: "Signal"), label(id: 2, type: "pothole_v4")]))
    #expect(set.labels.map(\.type) == [.other, .other])
}

@Test func unknownExtraFieldsAreIgnored() throws {
    let set = try WaymarkPriorSet.decode(bundle(labels: [label(extra: #","future_field":{"x":1}"#)]))
    #expect(set.labels.count == 1)
}

@Test func optionalCountsTakeTheirDefaults() throws {
    let bare = #"{"id":"ps:9","type":"obstacle","lat":47.654,"lng":-122.305,"severity":null,"n_agree":0,"n_disagree":0,"source_cluster_id":9}"#
    let p = try #require(try WaymarkPriorSet.decode(bundle(labels: [bare])).labels.first)
    #expect(p.nUnsure == 0 && p.clusterSize == 1 && p.tags == [] && p.severity == nil)
    #expect(p.streetEdgeID == nil && p.imageryDate == nil)
}

@Test func fractionalSeverityIsKept() throws {
    // D-19: severity is a number in [1, 3], no rounding.
    let p = try #require(try WaymarkPriorSet.decode(bundle(labels: [label(severity: "1.5")])).labels.first)
    #expect(p.severity == 1.5)
}

@Test func rejectsWrongSchema() {
    #expect(throws: WaymarkPriorError.wrongSchema("waymark.priors.v0")) {
        try WaymarkPriorSet.decode(bundle(labels: [label()], schema: "waymark.priors.v0"))
    }
}

@Test func rejectsOutOfRangeCoordinates() {
    for (lat, lng) in [("91", "-122.3"), ("-90.5", "0"), ("47.6", "181"), ("47.6", "-180.01")] {
        #expect(throws: WaymarkPriorError.badCoordinate(id: "ps:1")) {
            try WaymarkPriorSet.decode(bundle(labels: [label(lat: lat, lng: lng)]))
        }
    }
}

@Test func rejectsSeverityOutsideOneToThree() {
    for s in ["0", "0.99", "3.01", "4", "-1"] {
        #expect(throws: WaymarkPriorError.badSeverity(id: "ps:1")) {
            try WaymarkPriorSet.decode(bundle(labels: [label(severity: s)]))
        }
    }
    // Both ends are inside.
    #expect(throws: Never.self) { try WaymarkPriorSet.decode(bundle(labels: [label(severity: "1"), label(id: 2, severity: "3")])) }
}

@Test func rejectsMoreThanTwentyThousandLabels() {
    let many = (1...20_001).map { label(id: $0) }
    #expect(throws: WaymarkPriorError.tooManyLabels(20_001)) {
        try WaymarkPriorSet.decode(bundle(labels: many), byteLimit: .max)
    }
}

@Test func acceptsExactlyTwentyThousandLabels() throws {
    let many = (1...20_000).map { label(id: $0) }
    #expect(try WaymarkPriorSet.decode(bundle(labels: many), byteLimit: .max).labels.count == 20_000)
}

@Test func rejectsFilesOverThreeMegabytes() {
    var data = bundle(labels: [label()])
    data.append(Data(repeating: 0x20, count: WaymarkPriorSet.maxBytes))  // trailing whitespace is still valid JSON
    #expect(throws: WaymarkPriorError.tooLarge(bytes: data.count)) { try WaymarkPriorSet.decode(data) }
}

@Test func rejectsABadBoundingBox() {
    for bbox in ["[-122.3, 47.6, -122.4, 47.7]",   // min lng after max lng
                 "[-122.4, 47.7, -122.3, 47.6]",   // min lat after max lat
                 "[47.6, -122.4, 47.7, -122.3]",   // lat-first (the v1.0 order): lat 47.6 is a fine lng, -122.4 is not a lat
                 "[-122.4, 47.6, -122.3]"] {       // three numbers
        #expect(throws: WaymarkPriorError.badBBox) { try WaymarkPriorSet.decode(bundle(labels: [label()], bbox: bbox)) }
    }
}

@Test func rejectsAnIDThatDisagreesWithTheClusterID() {
    let wrong = label(id: 5).replacingOccurrences(of: #""source_cluster_id":5"#, with: #""source_cluster_id":6"#)
    #expect(throws: WaymarkPriorError.idMismatch(id: "ps:5")) { try WaymarkPriorSet.decode(bundle(labels: [wrong])) }
}

@Test func rejectsDuplicateIDs() {
    #expect(throws: WaymarkPriorError.duplicateID("ps:1")) { try WaymarkPriorSet.decode(bundle(labels: [label(), label()])) }
}

@Test func rejectsNegativeCounts() {
    let bad = label().replacingOccurrences(of: #""n_agree":1"#, with: #""n_agree":-1"#)
    #expect(throws: WaymarkPriorError.badCount(id: "ps:1")) { try WaymarkPriorSet.decode(bundle(labels: [bad])) }
}

@Test func rejectsAMalformedMonth() {
    for date in [#""2019-5""#, #""2019-13""#, #""May 2019""#, #""2019-05-01""#] {
        let bad = label().replacingOccurrences(of: #""imagery_date":null"#, with: #""imagery_date":\#(date)"#)
        #expect(throws: WaymarkPriorError.badDate(id: "ps:1")) { try WaymarkPriorSet.decode(bundle(labels: [bad])) }
    }
}

@Test func rejectsJSONThatIsNotABundle() {
    #expect(throws: WaymarkPriorError.self) { try WaymarkPriorSet.decode(Data("[]".utf8)) }
    #expect(throws: WaymarkPriorError.self) { try WaymarkPriorSet.decode(Data("not json".utf8)) }
    // A required label field missing (lat).
    let noLat = label().replacingOccurrences(of: #""lat":47.654,"#, with: "")
    #expect(throws: WaymarkPriorError.self) { try WaymarkPriorSet.decode(bundle(labels: [noLat])) }
}

@Test func anEmptyLabelListIsAValidBundle() throws {
    #expect(try WaymarkPriorSet.decode(bundle(labels: [])).labels.isEmpty)
}
