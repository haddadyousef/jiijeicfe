//
//  WaymarkEvidence.swift
//  CaneKitLogic
//
//  Waymark E1 (plan v1.1 board, design doc §9): turns a walk past a label into at most one
//  `waymark.evidence.v1` outcome per label per route.
//
//  · LiDAR (§9.1 row 1, obstacles only), after the E1 review. Geometry is signed: `along` (metres
//    ahead, negative = behind) and `cross` (metres to the side) from the walker along the first route
//    leg, else the heading. A label is judged only when it is within `lateralM` (3 m) of the line of
//    travel — the lanes see about ±1.5 m. Window = ±(`windowM` 8 m label error + GPS accuracy, ≤ 12 m).
//    A pass opens only when the label is first seen in front of the window (approached from the
//    front); frames taken between fixes are counted only while the label is inside the window and
//    only when the §9.2 gates hold at that fix (walking, GPS ≤ 20 m, fresh). Verdict when the label
//    leaves: any gated trusted reading under `confirmBelowM` (2.0 m; torso when covered, head only
//    when covered) → confirmed, with `along_m` where that reading was taken. Contradicted only for a
//    finished pass — exited behind the window, walked ≥ 1.8 × 8 m, no reversal (> 3 m back), no
//    GPS jump (> 25 m between fixes), every counted frame trusted and torso-covered, ≥ `minFrames`
//    frames, nothing under `clearAboveM` (2.5 m). Anything else → unverifiable with a `reason`
//    (lateral, left, reversed, gps_jump, unclean, few_frames, short_pass, between, route_end).
//  · Ground (§9.1 row 2, narrowed by the E1 review; W to confirm): a LiDAR curb-like event (drop or
//    step) confirms the nearest *missing* curb ramp within −8 … +11.5 m along and 4 m sideways, when the
//    gates hold. A drop or step at a `curb_ramp` label is not evidence the ramp is there, so it is skipped.
//  · Spotter (§9.3): `WaymarkSpotter.target` picks the nearest label with a spoken line within
//    15 m (ahead or just passed) for the Confirm / Not there buttons.
//
//  Pure: no clock (the engine passes gates computed from the fix), no I/O. The two clocks never
//  meet here: depth frames are only counted and folded, never timed.
//  Owner: `WaymarkEngine`. Tests: WaymarkEvidenceTests.swift.
//

import Foundation

/// One LiDAR frame as Waymark needs it (built by the engine from a `LaneReport`).
public struct WaymarkDepthSample: Sendable, Equatable {
    /// The base gyro gate accepted the frame (`LaneReport.isTrusted`) and depth was live.
    public var trusted: Bool
    /// Nearest torso-band reading across the three lanes, metres (`.infinity` = nothing).
    public var torsoMinM: Double
    /// Nearest head-band reading across the three lanes, metres.
    public var headMinM: Double
    /// The camera sees the torso band (centre lane, `LaneGrid.torsoCoverage`).
    public var torsoCover: Bool
    /// The camera sees the head band (centre lane, `LaneGrid.headCoverage`).
    public var headCover: Bool
    /// Camera tilt below horizontal, degrees, if known.
    public var tiltDeg: Double?

    /// Memberwise.
    public init(trusted: Bool, torsoMinM: Double, headMinM: Double, torsoCover: Bool, headCover: Bool, tiltDeg: Double?) {
        self.trusted = trusted; self.torsoMinM = torsoMinM; self.headMinM = headMinM
        self.torsoCover = torsoCover; self.headCover = headCover; self.tiltDeg = tiltDeg
    }
}

/// The §9.2 gates that come with a GPS fix.
public struct WaymarkEvidenceGates: Sendable, Equatable {
    /// Ground speed, m/s.
    public var speedMps: Double
    /// Horizontal accuracy, metres (negative = invalid).
    public var gpsAccuracyM: Double
    /// The fix is fresh (`NavigationHealth.isFresh`).
    public var fixFresh: Bool

    /// Memberwise.
    public init(speedMps: Double, gpsAccuracyM: Double, fixFresh: Bool) {
        self.speedMps = speedMps; self.gpsAccuracyM = gpsAccuracyM; self.fixFresh = fixFresh
    }

    /// Walking (≥ `WaymarkAhead.minSpeedMps`), accuracy in [0, 20] m, fresh.
    public var hold: Bool {
        speedMps.isFinite && speedMps >= WaymarkAhead.minSpeedMps && gpsAccuracyM >= 0
            && gpsAccuracyM <= WaymarkAlertPolicy.maxGpsAccuracyM && fixFresh
    }
}

/// One outcome, with the context fields of a `waymark.evidence.v1` line.
public struct WaymarkEvidenceVerdict: Sendable, Equatable {
    /// The label.
    public var labelID: String
    /// Confirmed / contradicted / unverifiable.
    public var outcome: WaymarkOutcome
    /// Which sensor decided.
    public var sensor: WaymarkSensor
    /// The deciding reading (LiDAR) or the label's distance along the path (ground, spotter), metres.
    public var distM: Double?
    /// Distance along the path to the label when decided, metres (negative = passed).
    public var alongM: Double?
    /// GPS accuracy at the last fix of the pass.
    public var gpsAccuracyM: Double?
    /// Speed at the last fix of the pass.
    public var speedMps: Double?
    /// Camera tilt at the last frame.
    public var tiltDeg: Double?
    /// Torso coverage at the last frame.
    public var torsoCover: Bool?
    /// Head coverage at the last frame.
    public var headCover: Bool?
    /// Why an outcome is unverifiable (trip log only; the evidence schema has no field for it).
    public var reason: String?

    /// Memberwise (public: the app builds spotter verdicts).
    public init(labelID: String, outcome: WaymarkOutcome, sensor: WaymarkSensor, distM: Double?, alongM: Double?,
                gpsAccuracyM: Double?, speedMps: Double?, tiltDeg: Double?, torsoCover: Bool?, headCover: Bool?,
                reason: String? = nil) {
        self.labelID = labelID; self.outcome = outcome; self.sensor = sensor; self.distM = distM
        self.alongM = alongM; self.gpsAccuracyM = gpsAccuracyM; self.speedMps = speedMps
        self.tiltDeg = tiltDeg; self.torsoCover = torsoCover; self.headCover = headCover; self.reason = reason
    }
}

/// Follows labels through their along-track window and decides each once per route.
public struct WaymarkEvidenceTracker: Sendable {
    /// Label position error, metres; the window is this plus the GPS accuracy (capped).
    public static let windowM = WaymarkAlertPolicy.labelErrorM
    /// Most GPS accuracy added to the window, metres.
    public static let maxGpsWidenM = 12.0
    /// Farthest sideways a judged label may be from the line of travel (the lanes see ~±1.5 m) `[H]`.
    public static let lateralM = 3.0
    /// A trusted reading under this confirms an obstacle (design doc §9.1 `[H]`).
    public static let confirmBelowM = 2.0
    /// A clean pass with nothing under this contradicts an obstacle (§9.1 `[H]`).
    public static let clearAboveM = 2.5
    /// Fewest counted frames for a contradiction (~0.5 s at 30 Hz).
    public static let minFrames = 15
    /// Moving back more than this between fixes is a reversal, metres.
    public static let reverseM = 3.0
    /// Along-track change between two fixes above this is a GPS jump, metres.
    public static let jumpM = 25.0
    /// A ground hazard is detected 1.5–3.5 m ahead of the walker.
    public static let groundLeadM = 3.5
    /// Farthest sideways for a ground event's label, metres.
    public static let groundLateralM = 4.0

    /// Frames since the last fix, not yet counted.
    private var pending = Frames()
    /// Open passes by label id.
    private var open: [String: Pass] = [:]
    /// Labels already decided this route (or this run, off-route).
    private var decided: Set<String> = []
    /// The last LiDAR frame (fills tilt / cover on ground and spotter lines; review M2).
    public private(set) var lastSample: WaymarkDepthSample?

    /// What the frames between two fixes showed.
    struct Frames: Sendable {
        var count = 0
        var trusted = 0
        var clean = true
        var minM = Double.infinity
        var minSensor = WaymarkSensor.lidarTorso
    }

    /// What one pass has seen.
    struct Pass: Sendable {
        var lastAlong: Double
        var walked = 0.0
        var reversed = false
        var jumped = false
        var inside = false
        var trusted = 0
        var clean = true
        var minM = Double.infinity
        var minSensor = WaymarkSensor.lidarTorso
        var alongAtMin: Double?
        var gps: Double?
        var speed: Double?
    }

    /// Empty tracker.
    public init() {}

    /// One LiDAR frame (any rate; the engine forwards every `LaneReport`).
    public mutating func add(_ s: WaymarkDepthSample) {
        lastSample = s
        pending.count += 1
        // An untrusted frame proves nothing and spoils a contradiction; an uncovered torso band
        // spoils a contradiction but a covered head band can still confirm.
        guard s.trusted else { pending.clean = false; return }
        if !s.torsoCover { pending.clean = false }
        pending.trusted += 1
        if s.torsoCover, s.torsoMinM < pending.minM { pending.minM = s.torsoMinM; pending.minSensor = .lidarTorso }
        if s.headCover, s.headMinM < pending.minM { pending.minM = s.headMinM; pending.minSensor = .lidarHead }
    }

    /// The direction of travel: toward the first route leg (when ≥ 3 m away), else the heading.
    static func direction(at position: Coordinate, headingDeg: Double?, legs: [Coordinate]?) -> Double? {
        if let first = legs?.first, GeoMath.distanceMeters(position, first) >= 3 {
            return GeoMath.bearingDegrees(from: position, to: first)
        }
        guard let h = headingDeg, h.isFinite else { return nil }
        return h
    }

    /// Signed along / cross metres of `p` from `position` facing `dirDeg`.
    static func alongCross(_ p: Coordinate, from position: Coordinate, dirDeg: Double) -> (along: Double, cross: Double) {
        let m = WaymarkAhead.metresPerDegree
        let x = (p.longitude - position.longitude) * m * cos(position.latitude * .pi / 180)
        let y = (p.latitude - position.latitude) * m
        let r = dirDeg * .pi / 180
        let (ux, uy) = (sin(r), cos(r))
        return (x * ux + y * uy, x * uy - y * ux)
    }

    /// The window half-width at this fix: label error + GPS accuracy (capped).
    static func window(_ gates: WaymarkEvidenceGates) -> Double {
        let acc = gates.gpsAccuracyM.isFinite && gates.gpsAccuracyM > 0 ? min(gates.gpsAccuracyM, maxGpsWidenM) : 0
        return windowM + acc
    }

    /// One GPS fix: counts the frames since the last fix into the passes whose label is inside the
    /// window, opens passes for obstacle labels approached from the front, and decides passes whose
    /// label left (behind the window, sideways, out of range) or that jumped.
    /// - Parameters:
    ///   - labels: candidates near the fix (`WaymarkIndex.within`).
    ///   - position, headingDeg, legs: where the walker is and which way they go.
    ///   - gates: the §9.2 gates at this fix.
    /// - Returns: the verdicts decided at this fix, sorted by label id.
    public mutating func step(labels: [WaymarkPrior], at position: Coordinate, headingDeg: Double?,
                              legs: [Coordinate]?, gates: WaymarkEvidenceGates) -> [WaymarkEvidenceVerdict] {
        var frames = pending
        pending = Frames()
        if !gates.hold { frames.clean = false; frames.minM = .infinity; frames.trusted = 0 }   // review H1
        guard let dir = Self.direction(at: position, headingDeg: headingDeg, legs: legs) else {
            for id in open.keys { open[id]?.clean = false }
            return []
        }
        let w = Self.window(gates)
        var out: [WaymarkEvidenceVerdict] = []
        var seen: Set<String> = []
        for p in labels where p.type == .obstacle && !decided.contains(p.id) {
            let (along, cross) = Self.alongCross(p.coordinate, from: position, dirDeg: dir)
            seen.insert(p.id)
            guard var pass = open[p.id] else {
                // Opens only when approached from the front, in line, not already inside the window.
                if along >= w, along <= w + 15, abs(cross) <= Self.lateralM {
                    open[p.id] = Pass(lastAlong: along, gps: gates.gpsAccuracyM, speed: gates.speedMps)
                }
                continue
            }
            let delta = along - pass.lastAlong
            if delta > Self.reverseM { pass.reversed = true }
            if abs(delta) > Self.jumpM { pass.jumped = true }
            if delta < 0 { pass.walked -= delta }
            pass.lastAlong = along
            pass.gps = gates.gpsAccuracyM
            pass.speed = gates.speedMps
            if abs(cross) > Self.lateralM || pass.jumped {
                out.append(close(p.id, pass, finished: false, reason: pass.jumped ? "gps_jump" : "lateral"))
                continue
            }
            if abs(along) < w {
                pass.inside = true
                pass.trusted += frames.trusted
                pass.clean = pass.clean && frames.clean
                if frames.minM < pass.minM { pass.minM = frames.minM; pass.minSensor = frames.minSensor; pass.alongAtMin = along }
            }
            if along <= -w {
                out.append(close(p.id, pass, finished: true, reason: nil))
            } else {
                open[p.id] = pass
            }
        }
        for (id, pass) in open where !seen.contains(id) {
            out.append(close(id, pass, finished: false, reason: "left"))
        }
        return out.sorted { $0.labelID < $1.labelID }
    }

    /// Decides and forgets one pass.
    private mutating func close(_ id: String, _ pass: Pass, finished: Bool, reason: String?) -> WaymarkEvidenceVerdict {
        open[id] = nil
        decided.insert(id)
        return Self.decide(id, pass, finished: finished, reason: reason, sample: lastSample)
    }

    /// A LiDAR curb-like event (drop or step) at this fix: confirms the nearest missing-curb-ramp
    /// label from 8 m behind to 11.5 m ahead and within 4 m sideways, when the gates hold; once per route.
    /// - Returns: the verdict, or nil when no such label is there or the gates fail.
    public mutating func groundEvent(labels: [WaymarkPrior], at position: Coordinate, headingDeg: Double?,
                                     legs: [Coordinate]?, gates: WaymarkEvidenceGates) -> WaymarkEvidenceVerdict? {
        guard gates.hold, let dir = Self.direction(at: position, headingDeg: headingDeg, legs: legs) else { return nil }
        var best: (prior: WaymarkPrior, along: Double)?
        for p in labels where p.type == .missingCurbRamp && !decided.contains(p.id) {
            let (along, cross) = Self.alongCross(p.coordinate, from: position, dirDeg: dir)
            guard along >= -Self.windowM, along <= Self.windowM + Self.groundLeadM, abs(cross) <= Self.groundLateralM else { continue }
            if let b = best, (abs(b.along), b.prior.id) <= (abs(along), p.id) { continue }
            best = (p, along)
        }
        guard let hit = best else { return nil }
        decided.insert(hit.prior.id)
        return WaymarkEvidenceVerdict(labelID: hit.prior.id, outcome: .confirmed, sensor: .ground, distM: abs(hit.along),
                                      alongM: hit.along, gpsAccuracyM: gates.gpsAccuracyM, speedMps: gates.speedMps,
                                      tiltDeg: lastSample?.tiltDeg, torsoCover: lastSample?.torsoCover,
                                      headCover: lastSample?.headCover)
    }

    /// A new route: every label can be decided again; passes opened off-route are dropped.
    public mutating func routeStarted() {
        open.removeAll(); decided.removeAll(); pending = Frames()
    }

    /// The route ended: open passes close as confirmed (already seen) or unverifiable ("route_end").
    /// - Returns: their verdicts.
    public mutating func routeEnded() -> [WaymarkEvidenceVerdict] {
        let out = open.map { Self.decide($0.key, $0.value, finished: false, reason: "route_end", sample: lastSample) }
            .sorted { $0.labelID < $1.labelID }
        open.removeAll(); decided.removeAll(); pending = Frames()
        return out
    }

    /// Forgets everything without a verdict (the feature was switched off; review H2).
    public mutating func reset() {
        open.removeAll(); decided.removeAll(); pending = Frames(); lastSample = nil
    }

    /// §9.1 row 1 with the review's pass rules.
    static func decide(_ id: String, _ p: Pass, finished: Bool, reason: String?, sample: WaymarkDepthSample?) -> WaymarkEvidenceVerdict {
        let outcome: WaymarkOutcome
        let sensor: WaymarkSensor
        var why: String?
        let w2 = 1.8 * windowM
        if p.minM < confirmBelowM {
            outcome = .confirmed; sensor = p.minSensor
        } else {
            sensor = .lidarTorso
            if !finished { why = reason ?? "unfinished" }
            else if p.reversed { why = "reversed" }
            else if p.jumped { why = "gps_jump" }
            else if !p.clean { why = "unclean" }
            else if p.trusted < minFrames { why = "few_frames" }
            else if p.walked < w2 { why = "short_pass" }
            else if p.minM < clearAboveM { why = "between" }
            outcome = why == nil ? .contradicted : .unverifiable
        }
        return WaymarkEvidenceVerdict(labelID: id, outcome: outcome, sensor: sensor,
                                      distM: p.minM.isFinite ? p.minM : nil,
                                      alongM: outcome == .confirmed ? p.alongAtMin : p.lastAlong,
                                      gpsAccuracyM: p.gps, speedMps: p.speed, tiltDeg: sample?.tiltDeg,
                                      torsoCover: sample?.torsoCover, headCover: sample?.headCover, reason: why)
    }
}

/// Which label the spotter's Confirm / Not there applies to (§9.3).
public enum WaymarkSpotter {
    /// Reach of a spotter tap, metres (§9.3 `[H]`).
    public static let reachM = 15.0

    /// The nearest label with a spoken line (`WaymarkLine(for:)` non-nil) within `reachM` of the
    /// walker, ahead or just passed. Ties by id.
    /// - Parameters:
    ///   - labels: candidates (`WaymarkIndex.within(reachM, of:)`).
    ///   - position: the walker.
    ///   - headingDeg: direction of travel, for the signed along-track distance (nil = unknown).
    /// - Returns: the label, its straight-line distance and the signed along distance (nil without
    ///   a heading); nil when no label is in reach.
    public static func target(labels: [WaymarkPrior], at position: Coordinate, headingDeg: Double?)
        -> (prior: WaymarkPrior, distM: Double, alongM: Double?)? {
        let m = WaymarkAhead.metresPerDegree
        let cosLat = cos(position.latitude * .pi / 180)
        var best: (prior: WaymarkPrior, distM: Double, alongM: Double?)?
        for p in labels where WaymarkLine(for: p.type) != nil {
            let x = (p.lng - position.longitude) * m * cosLat
            let y = (p.lat - position.latitude) * m
            let d = (x * x + y * y).squareRoot()
            guard d <= reachM else { continue }
            if let b = best, (b.distM, b.prior.id) <= (d, p.id) { continue }
            var along: Double?
            if let h = headingDeg, h.isFinite {
                let r = h * .pi / 180
                along = x * sin(r) + y * cos(r)
            }
            best = (p, d, along)
        }
        return best
    }
}
