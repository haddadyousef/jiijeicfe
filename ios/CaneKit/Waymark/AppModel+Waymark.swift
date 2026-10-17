//
//  AppModel+Waymark.swift
//  CaneKit
//
//  Waymark A1: the AppModel side of sidewalk memory, kept out of AppModel.swift so the base file
//  changes only by marked one-liners (`// waymark:`). `wireWaymark()` runs once in `init`;
//  `ingestWaymark(_:)` runs on every GPS fix from `wireNavigation()`'s `location.onFix`.
//
//  Speech: `.obstacle` priority, 6 s ttl — below `.nav` and `.safety`, so a turn or a safety cue
//  always wins, and a stale line expires instead of playing late.
//

import Foundation
import CaneKitLogic

extension AppModel {

    /// Wires the engine's speech and log outputs, then applies the stored switch (which loads the
    /// bundle only when it is on). Called once from `init`, after `waymark` exists.
    func wireWaymark() {
        waymark.onSpeak = { [weak self] line in
            guard let self else { return }
            self.speech.say(line, .obstacle, ttl: 6)
            self.logger.event("speech", ["text": line, "priority": "obstacle", "source": "waymark"])
        }
        waymark.onLog = { [weak self] kind, fields in
            self?.logger.event(kind, fields)
        }
        waymark.enabled = waymarkEnabled
    }

    /// One GPS fix into the Waymark engine with the base app's current gating state.
    /// - Parameter fix: the fix `location.onFix` just delivered.
    func ingestWaymark(_ fix: GeoFix) {
        waymark.ingest(fix: fix, route: nav.isNavigating ? nav.route : nil, waypointIndex: nav.waypointIndex,
                       crossingSettle: nav.isCrossingSettle, voiceHeld: speech.isVoiceHeld,
                       gpsWeak: nav.gpsWeak, cueLevel: cueLevel.rawValue, cuePlace: cuePlace.rawValue)
    }
}
