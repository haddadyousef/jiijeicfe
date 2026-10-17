//
//  WaymarkGoldenTests.swift
//  CaneKitLogicTests
//
//  Python/Swift parity (WAYMARK_PLAN 5.3, 5.4, D-16, D-26): the Swift Waymark types must agree with
//  the Windows reference (`waymark/contracts/ref/belief.py`) on the generated golden files in
//  `waymark/contracts/golden/`, and must decode the real shipped bundle
//  (`ios/CaneKit/Resources/waymark_priors.json`, built by the pipeline P4).
//  The golden files are owned by Windows (contracts README: change the generator, not the file).
//  If one of these tests fails after a golden change, the Swift code or the golden file is wrong,
//  and the Mac says which in STATUS_M before changing anything.
//  Files are read through `#filePath`, like `RouteTests.shippedRouteFileIsConsistent`.
//

import Foundation
import Testing
@testable import CaneKitLogic

/// `ios/` (three directories up from this file).
private let iosDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent()

/// A file in `waymark/contracts/golden/`.
private func golden(_ name: String) throws -> Data {
    try Data(contentsOf: iosDir.appendingPathComponent("../waymark/contracts/golden/\(name)").standardized)
}

/// The top-level JSON object of a golden file.
private func goldenObject(_ name: String) throws -> [String: Any] {
    let any = try JSONSerialization.jsonObject(with: golden(name))
    return try #require(any as? [String: Any])
}

/// ISO 8601 UTC ("2026-10-17T21:00:00Z") → UTC seconds.
private func utc(_ s: String) throws -> Double {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    let d = f.date(from: s)
    return try #require(d).timeIntervalSince1970
}

/// A missing or mistyped golden field.
private struct GoldenFieldError: Error { let key: String }

/// `d[key]` as `T`, or throws (no nested `#require`, which the macro cannot expand recursively).
private func field<T>(_ d: [String: Any], _ key: String, as: T.Type = T.self) throws -> T {
    guard let v = d[key] as? T else { throw GoldenFieldError(key: key) }
    return v
}

/// A raw-value enum from `d[key]`.
private func enumField<E: RawRepresentable>(_ d: [String: Any], _ key: String, _: E.Type) throws -> E where E.RawValue == String {
    guard let e = E(rawValue: try field(d, key, as: String.self)) else { throw GoldenFieldError(key: key) }
    return e
}

// MARK: Priors

@Test func goldenPriorsSampleDecodes() throws {
    let set = try WaymarkPriorSet.decode(golden("priors_sample.json"))
    #expect(set.labels.count == 7)
    #expect(set.labels.map(\.type) == [.curbRamp, .obstacle, .missingCurbRamp, .surfaceProblem, .noSidewalk, .crosswalk, .other])
    // Label 1 is the real Project Sidewalk label of plan 5.2, field for field.
    let real = try #require(set.labels.first)
    #expect(real.id == "ps:13290420" && real.lat == 47.652233 && real.lng == -122.306389)
    #expect(real.severity == 1 && real.nAgree == 2 && real.streetEdgeID == 20109 && real.osmWayID == 283038445)
    #expect(real.imageryDate == "2019-05" && real.labelDate == "2019-07")
}

@Test func goldenUnknownTypeDecodesToOther() throws {
    let set = try WaymarkPriorSet.decode(golden("priors_unknown_type.json"))
    #expect(set.labels.map(\.type) == [.curbRamp, .other])
}

@Test func goldenInvalidCasesAreRejectedWhereTheContractSaysMust() throws {
    let cases = try field(try goldenObject("priors_invalid_cases.json"), "cases", as: [[String: Any]].self)
    #expect(cases.count == 12)
    for c in cases {
        let name = try field(c, "name", as: String.self)
        let mustReject = try field(c, "decoder_must_reject", as: Bool.self)
        let doc = try JSONSerialization.data(withJSONObject: try field(c, "doc", as: [String: Any].self))
        if mustReject {
            #expect(throws: WaymarkPriorError.self, "\(name) must be rejected") { try WaymarkPriorSet.decode(doc) }
        }
        // decoder_must_reject == false: either answer is allowed; this decoder is stricter on
        // bad_month, bbox_wrong_order and id_mismatch, and accepts unsorted_labels.
    }
}

@Test func theShippedBundleDecodesAndIndexes() throws {
    let url = iosDir.appendingPathComponent("CaneKit/Resources/waymark_priors.json")
    let data = try Data(contentsOf: url)
    #expect(data.count <= WaymarkPriorSet.maxBytes)
    let set = try WaymarkPriorSet.decode(data)
    #expect(!set.labels.isEmpty && set.labels.count <= WaymarkPriorSet.maxLabels)
    #expect(set.sourceName == "Project Sidewalk")
    let types = Set(set.labels.map(\.type))
    for t in [WaymarkLabelType.obstacle, .missingCurbRamp, .noSidewalk, .surfaceProblem, .curbRamp] {
        #expect(types.contains(t), "the real bundle should hold some \(t.rawValue) labels")
    }
    // Every label sits inside the bundle's own box (lng first, D-13).
    let b = set.bboxLngLat
    #expect(set.labels.allSatisfy { $0.lng >= b[0] && $0.lat >= b[1] && $0.lng <= b[2] && $0.lat <= b[3] })
    // Sorted by numeric cluster id (D-27).
    #expect(zip(set.labels, set.labels.dropFirst()).allSatisfy { $0.sourceClusterID < $1.sourceClusterID })
    // The interim simulator point (D-07) has labels around it.
    let index = WaymarkIndex(set.labels)
    #expect(!index.within(150, of: Coordinate(latitude: 47.6540, longitude: -122.3050)).isEmpty)
}

// MARK: Belief (plan 5.3)

@Test func goldenBeliefVectorsMatchToOneInABillion() throws {
    let root = try goldenObject("belief_vectors.json")
    let cases = try field(root, "cases", as: [[String: Any]].self)
    #expect(cases.count >= 8)
    for c in cases {
        let name = try field(c, "name", as: String.self)
        let type = try enumField(c, "type", WaymarkLabelType.self)
        let prior = WaymarkPrior(id: "ps:1", type: type, lat: 47.654, lng: -122.305, severity: nil, tags: [],
                                 nAgree: try field(c, "n_agree", as: Int.self), nDisagree: try field(c, "n_disagree", as: Int.self),
                                 nUnsure: 0, clusterSize: 1, streetEdgeID: nil, intersectionID: nil, osmWayID: nil,
                                 imageryDate: nil, labelDate: nil, sourceClusterID: 1)
        var events: [(at: Double, outcome: WaymarkOutcome, sensor: WaymarkSensor)] = []
        for e in try field(c, "events", as: [[String: Any]].self) {
            events.append((try utc(try field(e, "at", as: String.self)),
                           try enumField(e, "outcome", WaymarkOutcome.self),
                           try enumField(e, "sensor", WaymarkSensor.self)))
        }
        // Time order, ties keep the listed order (contracts README).
        let ordered = events.enumerated().sorted { $0.element.at != $1.element.at ? $0.element.at < $1.element.at : $0.offset < $1.offset }.map(\.element)
        for r in try field(c, "reads", as: [[String: Any]].self) {
            let atText = try field(r, "at", as: String.self)
            let at = try utc(atText)
            var belief = WaymarkBelief()
            for e in ordered where e.at <= at { belief.update(e.outcome, sensor: e.sensor, type: type, now: e.at) }
            let got = belief.read(prior: prior, now: at)
            for (key, value) in [("a", got.a), ("b", got.b), ("p", got.p), ("n_eff", got.nEff)] {
                let want = try field(r, key, as: Double.self)
                #expect(abs(value - want) <= 1e-9, "\(name) @\(atText) \(key): \(value) vs \(want)")
            }
        }
    }
}

@Test func goldenBeliefConstantsMatch() throws {
    let k = try field(try goldenObject("belief_vectors.json"), "constants", as: [String: Any].self)
    let h = try field(k, "half_life_days", as: [String: Double].self)
    #expect(WaymarkBelief.halfLifeDays(.obstacle) == h["obstacle"])
    #expect(WaymarkBelief.halfLifeDays(.surfaceProblem) == h["surface_problem"])
    #expect(WaymarkBelief.halfLifeDays(.noSidewalk) == h["default"])
    let w = try field(k, "weights", as: [String: Double].self)
    for s in WaymarkSensor.allCases { #expect(WaymarkBelief.weight(s) == w[s.rawValue], "\(s)") }
}

// MARK: Threshold (plan 5.4)

@Test func goldenThresholdVectorsMatchToOneInATrillion() throws {
    let root = try goldenObject("threshold_vectors.json")
    for g in try field(root, "generic_tau", as: [[String: Any]].self) {
        let tau = WaymarkThreshold.tau(costMiss: try field(g, "c_miss", as: Double.self),
                                       costFalseAlarm: try field(g, "c_fa", as: Double.self))
        let want = try field(g, "tau", as: Double.self)
        #expect(abs(tau - want) <= 1e-12)
    }
    for t in try field(root, "tau", as: [[String: Any]].self) {
        let type = try enumField(t, "type", WaymarkLabelType.self)
        let costs = try #require(WaymarkThreshold.costs(for: type))
        #expect(costs.miss == t["c_miss"] as? Double && costs.falseAlarm == t["c_fa"] as? Double)
        let tau = try #require(WaymarkThreshold.tau(for: type))
        let want = try field(t, "tau", as: Double.self)
        #expect(abs(tau - want) <= 1e-12)
    }
    for a in try field(root, "alerts", as: [[String: Any]].self) {
        let type = try enumField(a, "type", WaymarkLabelType.self)
        let p = try field(a, "p", as: Double.self)
        let consider = WaymarkThreshold.tau(for: type).map { p >= $0 } ?? false
        let want = try field(a, "consider_alert", as: Bool.self)
        #expect(consider == want, "\(type) p=\(p)")
    }
}

// MARK: Evidence (design doc 7.2, D-26: parsed JSON, floats within 1e-9)

@Test func goldenEvidenceLinesReencodeToTheSameJSON() throws {
    let text = try #require(String(data: try golden("evidence_sample.jsonl"), encoding: .utf8))
    let lines = text.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    #expect(lines.count == 8)
    for line in lines {
        let wantAny = try JSONSerialization.jsonObject(with: Data(line.utf8))
        let want = try #require(wantAny as? [String: Any])
        func num(_ k: String) -> Double? { (want[k] as? NSNumber)?.doubleValue }
        func flag(_ k: String) -> Bool? { want[k] is NSNull ? nil : want[k] as? Bool }
        let encoded = WaymarkRecord.evidence(
            labelID: try field(want, "label_id", as: String.self),
            outcome: try enumField(want, "outcome", WaymarkOutcome.self),
            sensor: try enumField(want, "sensor", WaymarkSensor.self),
            distM: num("dist_m"), alongM: num("along_m"), gpsAccuracyM: num("gps_acc_m"),
            speedMps: num("speed_mps"), tiltDeg: num("tilt_deg"),
            torsoCover: flag("torso_cover"), headCover: flag("head_cover"),
            build: try field(want, "build", as: String.self),
            timestampUTC: try utc(try field(want, "ts", as: String.self)))
        let gotAny = try JSONSerialization.jsonObject(with: Data(encoded.utf8))
        let got = try #require(gotAny as? [String: Any])
        #expect(Set(got.keys) == Set(want.keys), "\(line)")
        for (k, w) in want {
            let g = got[k]
            if w is NSNull { #expect(g is NSNull, "\(k) should be null") }
            else if k == "torso_cover" || k == "head_cover" { #expect(g as? Bool == w as? Bool, "\(k)") }
            else if let wn = w as? NSNumber { #expect(abs(((g as? NSNumber)?.doubleValue ?? .nan) - wn.doubleValue) <= 1e-9, "\(k)") }
            else { #expect(g as? String == w as? String, "\(k)") }
        }
    }
}
