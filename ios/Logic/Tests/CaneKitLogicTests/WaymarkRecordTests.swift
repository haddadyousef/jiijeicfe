//
//  WaymarkRecordTests.swift
//  CaneKitLogicTests
//
//  Pins `WaymarkRecord` (design doc v1.0 4.3, 7.2): trip-log payloads never use the `t` or `kind`
//  keys (TripLogRecord would rename them `field_t` / `field_kind`, and `ios/scripts/e2e.py` fails
//  a run on `field_kind`), and evidence lines are `waymark.evidence.v1` with the label id, never the
//  walker's coordinates or identity.
//  Source pinned: `ios/Logic/Sources/CaneKitLogic/Waymark/WaymarkRecord.swift`.
//

import Foundation
import Testing
@testable import CaneKitLogic

@Test func cuePayloadHasNoReservedKeys() {
    let spoken = WaymarkRecord.cue(labelID: "ps:1", type: .obstacle, p: 0.75, tau: 1.0 / 6, alongM: 11.24,
                                   decision: .speak(.obstacle, labelID: "ps:1"))
    let silent = WaymarkRecord.cue(labelID: "ps:2", type: .curbRamp, p: 0.4, tau: nil, alongM: 9,
                                   decision: .silent(reason: "level_detailed_only"))
    for payload in [spoken, silent] {
        #expect(payload["t"] == nil && payload["kind"] == nil)
        #expect(payload["label_id"] != nil && payload["label_type"] != nil)
    }
    #expect(spoken["line"] == "Reported obstacle ahead.")
    #expect(spoken["suppressed_reason"] == nil)
    #expect(silent["suppressed_reason"] == "level_detailed_only")
    #expect(spoken["p"] == "0.75" && spoken["tau"] == "0.166667" && spoken["dist_m"] == "11.2")
    #expect(silent["tau"] == nil)
}

@Test func evidenceLineIsVersionOneJSONWithoutCoordinates() throws {
    let line = WaymarkRecord.evidence(labelID: "ps:123456", outcome: .confirmed, sensor: .lidarTorso,
                                      distM: 0.9, alongM: 1.4, gpsAccuracyM: 8, speedMps: 1.1, tiltDeg: 5,
                                      torsoCover: true, headCover: true, build: "waymark-0.1",
                                      timestampUTC: 1_792_273_331)
    #expect(!line.contains("\n"))
    let obj = try #require(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
    #expect(obj["schema"] as? String == "waymark.evidence.v1")
    #expect(obj["label_id"] as? String == "ps:123456")
    #expect(obj["outcome"] as? String == "confirmed")
    #expect(obj["sensor"] as? String == "lidar_torso")
    #expect(obj["dist_m"] as? Double == 0.9 && obj["along_m"] as? Double == 1.4)
    #expect(obj["gps_acc_m"] as? Double == 8 && obj["speed_mps"] as? Double == 1.1 && obj["tilt_deg"] as? Double == 5)
    #expect(obj["torso_cover"] as? Bool == true && obj["head_cover"] as? Bool == true)
    #expect(obj["build"] as? String == "waymark-0.1")
    #expect(obj["ts"] as? String == "2026-10-17T21:42:11Z")
    for banned in ["lat", "lng", "lon", "latitude", "longitude", "t", "kind", "device", "user"] {
        #expect(obj[banned] == nil, "\(banned) must not be in an evidence line")
    }
}

@Test func evidenceLineMatchesTheDesignExampleByteForByte() {
    // Design doc v1.0 §7.2 example, keys in the order written there.
    let expected = #"{"schema":"waymark.evidence.v1","label_id":"ps:123456","outcome":"confirmed","sensor":"lidar_torso","dist_m":0.9,"along_m":1.4,"gps_acc_m":8.0,"speed_mps":1.1,"tilt_deg":5.0,"torso_cover":true,"head_cover":true,"build":"waymark-0.1","ts":"2026-10-17T21:42:11Z"}"#
    let line = WaymarkRecord.evidence(labelID: "ps:123456", outcome: .confirmed, sensor: .lidarTorso,
                                      distM: 0.9, alongM: 1.4, gpsAccuracyM: 8, speedMps: 1.1, tiltDeg: 5,
                                      torsoCover: true, headCover: true, build: "waymark-0.1",
                                      timestampUTC: 1_792_273_331)
    #expect(line == expected)
}

@Test func evidenceNullsAreExplicit() {
    let line = WaymarkRecord.evidence(labelID: "ps:1", outcome: .unverifiable, sensor: .spotter, distM: nil,
                                      alongM: nil, gpsAccuracyM: nil, speedMps: nil, tiltDeg: nil,
                                      torsoCover: nil, headCover: nil, build: "waymark-0.1", timestampUTC: 0)
    #expect(line == #"{"schema":"waymark.evidence.v1","label_id":"ps:1","outcome":"unverifiable","sensor":"spotter","dist_m":null,"along_m":null,"gps_acc_m":null,"speed_mps":null,"tilt_deg":null,"torso_cover":null,"head_cover":null,"build":"waymark-0.1","ts":"1970-01-01T00:00:00Z"}"#)
}

@Test func evidenceNeverWritesNegativeOrNoisyNumbers() {
    // E1 review B3: GeoFix uses -1 for "invalid" (standing still); the schema needs >= 0 or null.
    // Float-derived readings are rounded to 2 decimals.
    let line = WaymarkRecord.evidence(labelID: "ps:1", outcome: .confirmed, sensor: .spotter, distM: 0.8999999761581421,
                                      alongM: -1.2345, gpsAccuracyM: -1, speedMps: -1, tiltDeg: 5.300000190734863,
                                      torsoCover: nil, headCover: nil, build: "b", timestampUTC: 1_792_200_000)
    #expect(line.contains("\"speed_mps\":null") && line.contains("\"gps_acc_m\":null"))
    #expect(line.contains("\"dist_m\":0.9") && line.contains("\"tilt_deg\":5.3") && line.contains("\"along_m\":-1.23"))
}
