//
//  WaymarkEvidence.swift
//  CaneKitLogic
//
//  Waymark E1 (plan v1.1 board, design doc §9): turns a walk past a label into at most one
//  `waymark.evidence.v1` outcome per label per route.
//
//  · LiDAR (§9.1 row 1, obstacles only). A pass opens when the label is within `windowM` (8 m,
//    the label position error) ahead along the path and inside the corridor, and closes when it is
//    not any more (passed or left). Depth frames between fixes (`add`) are folded into every open
//    pass. Verdict at close: any trusted reading under `confirmBelowM` (2.0 m; torso when the torso
//    band is covered, head only when the head band is covered) → confirmed (`lidar_torso` /
//    `lidar_head`); else a clean pass — every frame trusted and torso-covered, every fix walking,
//    GPS ≤ 20 m and fresh (§9.2), at least `minFrames` frames — with nothing under `clearAboveM`
//    (2.5 m) → contradicted; else unverifiable. A route end closes open passes: confirmed if
//    already seen, else unverifiable (the pass never finished).
//  · Ground (§9.1 row 2): a LiDAR curb event confirms the nearest curb-ramp / missing-curb-ramp
//    label ahead within `windowM + groundLeadM` (the hazard is seen 1.5–3.5 m ahead).
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

    /// Memberwise (public: the app builds spotter verdicts; Mac make sim, 16:44).
    public init(labelID: String, outcome: WaymarkOutcome, sensor: WaymarkSensor, distM: Double?, alongM: Double?,
                gpsAccuracyM: Double?, speedMps: Double?, tiltDeg: Double?, torsoCover: Bool?, headCover: Bool?) {
        self.labelID = labelID; self.outcome = outcome; self.sensor = sensor; self.distM = distM
        self.alongM = alongM; self.gpsAccuracyM = gpsAccuracyM; self.speedMps = speedMps
        self.tiltDeg = tiltDeg; self.torsoCover = torsoCover; self.headCover = headCover
    }
}

/// Follows labels through their along-track window and decides each once per route.
public struct WaymarkEvidenceTracker: Sendable {
    /// Along-track window around a label (the label position error, 8 m).
    public static let windowM = WaymarkAlertPolicy.labelErrorM
    /// A trusted reading under this confirms an obstacle (design doc §9.1 `[H]`).
    public static let confirmBelowM = 2.0
    /// A clean pass with nothing under this contradicts an obstacle (§9.1 `[H]`).
    public static let clearAboveM = 2.5
    /// Fewest trusted frames for a contradiction (a pass that saw almost nothing proves nothing).
    public static let minFrames = 5
    /// A ground hazard is detected 1.5–3.5 m ahead of the walker, so its label can be that much
    /// beyond the window.
    public static let groundLeadM = 3.5

    /// Frames since the last fix, not yet folded into a pass.
    private var pending = Pass()
    /// Open passes by label id.
    private var open: [String: Pass] = [:]
    /// Labels already decided this route.
    private var decided: Set<String> = []

    /// What one pass has seen.
    struct Pass: Sendable {
        var frames = 0
        var trustedFrames = 0
        var clean = true
        var minM = Double.infinity
        var minSensor = WaymarkSensor.lidarTorso
        var alongM: Double?
        var gps: Double?
        var speed: Double?
        var tilt: Double?
        var torsoCover: Bool?
        var headCover: Bool?

        /// Folds another pass's frames into this one.
        mutating func absorb(_ o: Pass) {
            frames += o.frames
            trustedFrames += o.trustedFrames
            clean = clean && o.clean
            if o.minM < minM { minM = o.minM; minSensor = o.minSensor }
            if o.tilt != nil { tilt = o.tilt }
            if o.torsoCover != nil { torsoCover = o.torsoCover }
            if o.headCover != nil { headCover = o.headCover }
        }
    }

    /// Empty tracker.
    public init() {}

    /// One LiDAR frame (any rate; the engine forwards every `LaneReport`).
    public mutating func add(_ s: WaymarkDepthSample) {
        pending.frames += 1
        pending.tilt = s.tiltDeg
        pending.torsoCover = s.torsoCover
        pending.headCover = s.headCover
        // An untrusted frame proves nothing and spoils a contradiction; an uncovered torso band
        // spoils a contradiction but a covered head band can still confirm.
        guard s.trusted else { pending.clean = false; return }
        if !s.torsoCover { pending.clean = false }
        pending.trustedFrames += 1
        if s.torsoCover, s.torsoMinM < pending.minM { pending.minM = s.torsoMinM; pending.minSensor = .lidarTorso }
        if s.headCover, s.headMinM < pending.minM { pending.minM = s.headMinM; pending.minSensor = .lidarHead }
    }

    /// One GPS fix: folds the frames since the last fix into the open passes, opens passes for
    /// obstacle labels that entered the window and closes (decides) the ones that left it.
    /// - Parameters:
    ///   - labels: candidates near the fix (`WaymarkIndex.within`).
    ///   - position, headingDeg, legs: as for `WaymarkAhead.select`.
    ///   - gates: the §9.2 gates at this fix.
    /// - Returns: the verdicts decided at this fix.
    public mutating func step(labels: [WaymarkPrior], at position: Coordinate, headingDeg: Double?,
                              legs: [Coordinate]?, gates: WaymarkEvidenceGates) -> [WaymarkEvidenceVerdict] {
        var frames = pending
        pending = Pass()
        if !gates.hold { frames.clean = false }
        // Geometry needs a direction; speed is a gate, not a geometry input, so it is floored here.
        let hasDirection = (legs?.isEmpty == false) || (headingDeg?.isFinite ?? false)
        guard hasDirection else {
            for id in open.keys { open[id]?.absorb(frames); open[id]?.clean = false }
            return []
        }
        let hits = WaymarkAhead.select(from: labels.filter { $0.type == .obstacle }, at: position,
                                       speedMps: max(gates.speedMps, WaymarkAhead.minSpeedMps),
                                       headingDeg: headingDeg, legs: legs)
        var inWindow: [String: Double] = [:]
        for h in hits where h.alongM <= Self.windowM { inWindow[h.prior.id] = h.alongM }
        for id in open.keys { open[id]?.absorb(frames) }
        var out: [WaymarkEvidenceVerdict] = []
        for (id, pass) in open where inWindow[id] == nil {
            out.append(Self.decide(id, pass, finished: true))
            open[id] = nil
            decided.insert(id)
        }
        for (id, along) in inWindow where !decided.contains(id) {
            if open[id] == nil { var p = Pass(); p.absorb(frames); open[id] = p }
            open[id]?.alongM = along
            open[id]?.gps = gates.gpsAccuracyM
            open[id]?.speed = gates.speedMps
        }
        return out.sorted { $0.labelID < $1.labelID }
    }

    /// A LiDAR curb event at this fix: confirms the nearest curb-ramp or missing-curb-ramp label
    /// ahead within `windowM + groundLeadM`, once per route.
    /// - Returns: the verdict, or nil when no such label is there.
    public mutating func groundEvent(labels: [WaymarkPrior], at position: Coordinate, headingDeg: Double?,
                                     legs: [Coordinate]?, speedMps: Double) -> WaymarkEvidenceVerdict? {
        let ramps = labels.filter { ($0.type == .curbRamp || $0.type == .missingCurbRamp) && !decided.contains($0.id) }
        let hits = WaymarkAhead.select(from: ramps, at: position, speedMps: max(speedMps, WaymarkAhead.minSpeedMps),
                                       headingDeg: headingDeg, legs: legs)
            .filter { $0.alongM <= Self.windowM + Self.groundLeadM }
            .sorted { ($0.alongM, $0.prior.id) < ($1.alongM, $1.prior.id) }
        guard let hit = hits.first else { return nil }
        decided.insert(hit.prior.id)
        return WaymarkEvidenceVerdict(labelID: hit.prior.id, outcome: .confirmed, sensor: .ground, distM: hit.alongM,
                                      alongM: hit.alongM, gpsAccuracyM: nil, speedMps: speedMps, tiltDeg: nil,
                                      torsoCover: nil, headCover: nil)
    }

    /// A new route: every label can be decided again.
    public mutating func routeStarted() {
        open.removeAll(); decided.removeAll(); pending = Pass()
    }

    /// The route ended: open passes close as confirmed (already seen) or unverifiable (unfinished).
    /// - Returns: their verdicts.
    public mutating func routeEnded() -> [WaymarkEvidenceVerdict] {
        let out = open.map { Self.decide($0.key, $0.value, finished: false) }.sorted { $0.labelID < $1.labelID }
        open.removeAll(); decided.removeAll(); pending = Pass()
        return out
    }

    /// §9.1 row 1. `finished`: the walker went through the whole window.
    static func decide(_ id: String, _ p: Pass, finished: Bool) -> WaymarkEvidenceVerdict {
        let outcome: WaymarkOutcome
        let sensor: WaymarkSensor
        if p.minM < confirmBelowM {
            outcome = .confirmed; sensor = p.minSensor
        } else if finished, p.clean, p.trustedFrames >= minFrames, p.minM >= clearAboveM {
            outcome = .contradicted; sensor = .lidarTorso
        } else {
            outcome = .unverifiable; sensor = .lidarTorso
        }
        return WaymarkEvidenceVerdict(labelID: id, outcome: outcome, sensor: sensor,
                                      distM: p.minM.isFinite ? p.minM : nil, alongM: p.alongM,
                                      gpsAccuracyM: p.gps, speedMps: p.speed, tiltDeg: p.tilt,
                                      torsoCover: p.torsoCover, headCover: p.headCover)
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
