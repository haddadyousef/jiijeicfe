//
//  AppModel+Waymark.swift
//  CaneKit
//
//  Waymark A1: the AppModel side of sidewalk memory, kept out of AppModel.swift so the base file
//  changes only by marked one-liners (`// waymark:`). `wireWaymark()` runs once in `init`;
//  `ingestWaymark(_:)` runs on every GPS fix from `wireNavigation()`'s `location.onFix`.
//
//  Speech (A1 review H1–H3): `.scene` priority, the lowest band, so every base-app line (obstacle
//  names, fallback cue words, signs, route, safety) pre-empts it; spoken only when the queue is idle
//  (`SpeechQueue.isIdle`); never resumed after a cut (`SpeechQueue.nonResumable`); 6 s ttl.
//

import Foundation
import CaneKitLogic

extension AppModel {

    /// Wires the engine's speech, log and loaded outputs and marks its lines non-resumable. Called
    /// once from `init`, after `waymark` exists. Starts nothing: the stored switch is applied in
    /// `start()` (`applyWaymarkSwitch()`), so an App Intent wake or a preview never loads the bundle.
    func wireWaymark() {
        speech.nonResumable = Set(WaymarkLines.all)
        waymark.onSpeak = { [weak self] line in
            guard let self else { return false }
            let spoken = self.speech.say(line, .scene, ttl: 6)
            if spoken {
                self.logger.event("speech", ["text": line, "priority": "scene", "source": "waymark"])
            }
            return spoken
        }
        waymark.onLog = { [weak self] kind, fields in
            self?.logger.event(kind, fields)
        }
        // The first line must come out in the natural voice and on time (A1 review M3).
        waymark.onLoaded = { [weak self] in
            self?.speech.prefetch(WaymarkLines.all)
        }
    }

    /// Applies the stored "Sidewalk memory" switch. Called once from `start()`.
    func applyWaymarkSwitch() {
        waymark.enabled = waymarkEnabled
    }

    /// E1: one `LaneReport` into the evidence tracker. Trusted = the gyro gate, depth live and
    /// normal tracking; minima only over lanes whose band the camera can see (`…Coverage`);
    /// coverage flags are the centre lane's.
    /// - Parameter report: the frame `handle(_:)` just received.
    func ingestWaymarkDepth(_ report: LaneReport) {
        guard waymarkEnabled else { return }
        let g = report.grid
        func nearest(_ values: [Float], _ cover: [Bool]) -> Double {
            var m = Double.infinity
            for i in values.indices where i < cover.count && cover[i] && values[i].isFinite {
                m = min(m, Double(values[i]))
            }
            return m
        }
        waymark.ingest(depth: WaymarkDepthSample(
            trusted: report.isTrusted && report.depthAvailable && report.trackingNormal,
            torsoMinM: nearest(g.torso, g.torsoCoverage), headMinM: nearest(g.head, g.headCoverage),
            torsoCover: g.torsoCoverage.count > 1 && g.torsoCoverage[1],
            headCover: g.headCoverage.count > 1 && g.headCoverage[1],
            tiltDeg: report.cameraTiltDownDeg.map(Double.init)))
    }

    /// One GPS fix into the Waymark engine with the base app's current gating state.
    /// - Parameter fix: the fix `location.onFix` just delivered.
    func ingestWaymark(_ fix: GeoFix) {
        // `gpsWeak` only while navigating: `NavigationEngine.stop()` leaves the flag set and nothing
        // clears it off-route (A1 review M1). An indoor script counts as indoors (review M2).
        waymark.ingest(fix: fix, route: nav.isNavigating ? nav.route : nil, waypointIndex: nav.waypointIndex,
                       crossingSettle: nav.isCrossingSettle, voiceHeld: speech.isVoiceHeld,
                       speechIdle: speech.isIdle, gpsWeak: nav.isNavigating && nav.gpsWeak,
                       cueLevel: cueLevel.rawValue,
                       cuePlace: indoor.isActive ? CuePlace.indoors.rawValue : cuePlace.rawValue)
    }
}
