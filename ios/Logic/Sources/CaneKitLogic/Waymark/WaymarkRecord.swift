//
//  WaymarkRecord.swift
//  CaneKitLogic
//
//  Waymark L3: the two things Waymark writes down.
//  - `cue(...)`: the payload of a `waymark_cue` trip-log record (design doc 8.5). Never uses the
//    keys `t` or `kind`: `TripLogRecord` would rename them `field_t` / `field_kind`, and
//    `ios/scripts/e2e.py` fails any run whose log contains `field_kind` (design doc 4.3).
//  - `evidence(...)`: one `waymark.evidence.v1` line (design doc 7.2) for
//    `Documents/waymark/evidence.jsonl`. Hand-encoded so the key order and number format are fixed
//    (the eval harness and the golden fixture compare bytes), with explicit nulls. It carries the
//    label id, never the walker's coordinates, device or identity (privacy by design, D-14).
//  Portability (plan 1.4): Foundation only. Pure. Tests: `WaymarkRecordTests.swift`.
//

import Foundation

/// Encoders for Waymark's log records and evidence lines.
public enum WaymarkRecord {
    /// The `waymark_cue` payload: what was decided about one label and why.
    /// - Parameters:
    ///   - labelID, type: the label.
    ///   - p: the belief at decision time; `tau`: its threshold (nil for curb ramps etc.).
    ///   - alongM: distance along the path.
    ///   - decision: the policy's decision.
    /// - Returns: string fields (`label_id`, `label_type`, `p`, `tau`, `dist_m`, then `line` or
    ///   `suppressed_reason`).
    public static func cue(labelID: String, type: WaymarkLabelType, p: Double, tau: Double?, alongM: Double,
                           decision: WaymarkDecision) -> [String: String] {
        var out: [String: String] = [
            "label_id": labelID,
            "label_type": type.rawValue,
            "p": String(format: "%.6g", p),
            "dist_m": String(format: "%.1f", alongM),
        ]
        if let tau { out["tau"] = String(format: "%.6g", tau) }
        switch decision {
        case .speak(let line, _): out["line"] = line.text
        case .silent(let reason): out["suppressed_reason"] = reason
        }
        return out
    }

    /// One `waymark.evidence.v1` JSON line (no trailing newline), keys in the design doc's order.
    /// Nil or non-finite values are written as JSON `null`.
    public static func evidence(labelID: String, outcome: WaymarkOutcome, sensor: WaymarkSensor,
                                distM: Double?, alongM: Double?, gpsAccuracyM: Double?, speedMps: Double?,
                                tiltDeg: Double?, torsoCover: Bool?, headCover: Bool?, build: String,
                                timestampUTC: Double) -> String {
        let fields: [(String, String)] = [
            ("schema", string("waymark.evidence.v1")),
            ("label_id", string(labelID)),
            ("outcome", string(outcome.rawValue)),
            ("sensor", string(sensor.rawValue)),
            // E1 review B3: GeoFix's −1 ("invalid") and non-finite values become null (the schema
            // says ≥ 0 or null); readings are rounded to 2 decimals (Float noise).
            ("dist_m", number(round2(nonNegative(distM)))),
            ("along_m", number(round2(alongM))),
            ("gps_acc_m", number(round2(nonNegative(gpsAccuracyM)))),
            ("speed_mps", number(round2(nonNegative(speedMps)))),
            ("tilt_deg", number(round2(tiltDeg))),
            ("torso_cover", bool(torsoCover)),
            ("head_cover", bool(headCover)),
            ("build", string(build)),
            ("ts", string(isoUTC(timestampUTC))),
        ]
        return "{" + fields.map { "\"\($0.0)\":\($0.1)" }.joined(separator: ",") + "}"
    }

    /// nil for nil, non-finite or negative values.
    static func nonNegative(_ v: Double?) -> Double? {
        guard let v, v.isFinite, v >= 0 else { return nil }
        return v
    }

    /// Rounded to 2 decimals; nil for nil or non-finite values.
    static func round2(_ v: Double?) -> Double? {
        guard let v, v.isFinite else { return nil }
        return (v * 100).rounded() / 100
    }

    /// A JSON string literal (quotes, backslashes and control characters escaped).
    static func string(_ s: String) -> String {
        var out = "\""
        for ch in s.unicodeScalars {
            switch ch {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case _ where ch.value < 0x20: out += String(format: "\\u%04x", ch.value)
            default: out.unicodeScalars.append(ch)
            }
        }
        return out + "\""
    }

    /// Swift's shortest round-trip decimal (`8.0`, `0.9`, `1.1`), or `null`.
    static func number(_ v: Double?) -> String {
        guard let v, v.isFinite else { return "null" }
        return "\(v)"
    }

    /// `true` / `false` / `null`.
    static func bool(_ b: Bool?) -> String { b.map { $0 ? "true" : "false" } ?? "null" }

    /// `YYYY-MM-DDTHH:MM:SSZ` for UTC seconds (whole seconds, fraction dropped).
    static func isoUTC(_ t: Double) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: Date(timeIntervalSince1970: t.rounded(.down)))
    }
}
