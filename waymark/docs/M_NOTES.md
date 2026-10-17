# M_NOTES — Mac-side answers and design notes

Owner: Mac session (Akash's account). Windows reads, proposes changes in `STATUS_W.md`.
Every answer below was read from source at OpenCane `fe86e10` (plus our rename commit, which does
not change any of these APIs). Plan v1.1 §7.1 items 2 and 3.

---

## 1. Route file format (for P5: `demo/route.gpx` and the route JSON)

### 1.1 Route JSON — the format the app loads (`Route` / `Waypoint` in `ios/Logic/Sources/CaneKitLogic/Waypoint.swift`)

```json
{
  "name": "Allen Center to the HUB",
  "source": "free text, shown nowhere; say where the points came from (OSM, Project Sidewalk streets, walked)",
  "waypoints": [
    {
      "id": 1,
      "name": "the Allen Center doors",
      "lat": 47.65340,
      "lon": -122.30590,
      "radius_m": 15,
      "say": "Leaving the Allen Center. Walk east along the path.",
      "crossing": false,
      "bearing_next_deg": 92.0,
      "curved": false
    }
  ]
}
```

| Key | Type | Required | Meaning |
|---|---|---|---|
| `name` (top) | string | yes | Route name; spoken in the intro ("Route to <destination>") and logged |
| `waypoints` | array | yes | In walking order. **The last one is the arrival fence.** |
| `id` | int | yes | 1-based, ascending. e2e asserts strictly ascending indices |
| `lat`, `lon` | double | yes | WGS84. Note the key is `lon`, not `lng` (our priors bundle uses `lng`) |
| `radius_m` | double | yes | Geofence radius. Base repo uses 15 m, 12 m at turns, 20 m at arrival |
| `say` | string | yes | Spoken once on reaching the waypoint. Its first sentence is also the spoken place name if `name` is absent |
| `crossing` | bool | yes | True = street crossing: wrist `.notification` tap and the beacon goes quiet until the walker stops at the curb (this is the "crossing settle" Waymark must stay silent during) |
| `bearing_next_deg` | double | no | Bearing to the next waypoint. Test-only consistency check (±15°); the app does not need it |
| `curved` | bool | no (default false) | Path between this and the next point is curved; relaxes veer cues |
| `name` | string | no | Short place name for "Passed <name>." |
| `recorded`, `source` (top) | string | no | Ignored by the decoder (extra keys are fine) |

- Decoder: plain `JSONDecoder`, required keys as above, extra keys ignored.
- How the app gets a non-bundled route: env var `CANEKIT_ROUTE_FILE=<absolute path>` (`RouteSource.bundled()`), used by `make e2e` stress scenarios via `SIMCTL_CHILD_CANEKIT_ROUTE_FILE`. Any destination typed in the app goes through MapKit walking directions instead and needs no file.
- Real example in the repo: `ios/CaneKit/Resources/route_isr_cif.json` (9 waypoints, UIUC) and `ios/scripts/stress/routes/*.json` (machine-built, `say` = "Turn right onto the path.").

### 1.2 GPS replay trace — what `ios/scripts/e2e.py --trace FILE` replays

Either a JSON trace:
```json
{
  "name": "waymark_demo",
  "route": "waymark/demo/route.json",
  "source": "where the points came from",
  "length_m": 900,
  "points": [[47.65340, -122.30590], [47.65342, -122.30560]]
}
```
- `points`: `[lat, lon]` pairs in order. e2e densifies to one simulator tick per vertex and can add AR(1) jitter and GPS gaps (`--jitter-m`, `--seed`, `--dropouts`, `--gap-s`).
- `route`: `"bundled"` (the app's bundled route) or a path to a route JSON (1.1), loaded through `CANEKIT_ROUTE_FILE`.

or a GPX 1.1 track (`<trk><trkseg><trkpt lat=".." lon=".."/>…`), which e2e walks **on the bundled route**. So for our Seattle demo, P5 should deliver the **JSON trace plus a route JSON**; the GPX is nice to have (for Xcode's own location simulation and for viewing).

Asserts e2e makes on a trace: route start with the route's waypoint count, arrival, waypoint indices strictly ascending, arrival fix ≤ 25 m from the last waypoint, ≤ `--max-lines-per-min` spoken lines, no identical consecutive lines, no `field_kind` in the log. X-e2e adds `waymark_cue` / `waymark_evidence` checks on top.

### 1.3 Requests to Windows for P5 (route generation)

1. `waymark/demo/route.json` in format 1.1, `lon` key, 600–1,200 m, waypoints at every turn and **every street crossing with `crossing: true`**, arrival waypoint last with `radius_m: 20`.
2. `waymark/demo/route_trace.json` in format 1.2 with `"route": "waymark/demo/route.json"` and points dense enough to follow the sidewalk (≤ 10 m apart), starting at waypoint 1.
3. Optional `waymark/demo/route.gpx` (same points).
4. `waymark/demo/test_priors.json` (`waymark.priors.v1`, labeled SYNTHETIC in `source.name`) with a few labels placed on the trace, so the replay produces cues.

## 2. Does `NavigationEngine` expose the active route polyline? (v1.0 8.4 [VERIFY])

**No polyline. It exposes the waypoints.**
- `NavigationEngine.route: Route?` (`private(set)`), `waypointIndex: Int`, `isNavigating: Bool`, `lastFix: GeoFix?`, `instruction: String`, `distanceToNext`, `isCrossingSettle: Bool`.
- MapKit walking directions are converted to waypoints (`RouteSource.directions` → `RouteStepInput.points` → `RouteBuilder`); the dense `MKPolyline` vertices are used to build waypoints and then dropped.
- **Consequence for `WaymarkAhead`:** use the remaining waypoint legs (current position → `waypoints[waypointIndex]` → … ) as the corridor when a route is running, and the smoothed course (`CourseSmoother`, already in Logic) when it is not. Legs between waypoints are straight chords, so the cross-track corridor must be wide enough for curved legs (`curved: true`), `[H]` 12 m, tune after F1.

## 3. Exact signatures the Waymark types will import (Logic, `fe86e10`)

```swift
public struct Coordinate: Sendable, Equatable, Codable {
    public var latitude: Double
    public var longitude: Double
    public init(latitude: Double, longitude: Double)
}
public struct GeoFix: Sendable, Equatable {
    public var coordinate: Coordinate
    public var accuracy: Double      // metres, negative = invalid
    public var speed: Double         // m/s, negative = invalid (CoreLocation's −1 when still)
    public var timestamp: TimeInterval   // app passes timeIntervalSinceReferenceDate
    public init(coordinate: Coordinate, accuracy: Double, speed: Double, timestamp: TimeInterval)
}
public enum GeoMath {
    public static func distanceMeters(_ a: Coordinate, _ b: Coordinate) -> Double
    public static func bearingDegrees(from a: Coordinate, to b: Coordinate) -> Double   // 0..360
    public static func wrap360(_ deg: Double) -> Double
    public static func wrap180(_ deg: Double) -> Double
    public static func bearingError(target: Double, heading: Double) -> Double
}
```
Notes: `GeoFix` has **no course field**; course comes from `CourseSmoother` or from the waypoint legs. Time on `GeoFix` is the reference-date clock (seconds since 2001-01-01), not Unix time; `WaymarkBelief` uses UTC seconds per plan 5.3, so the engine converts (`Date(timeIntervalSinceReferenceDate:).timeIntervalSince1970`) at the boundary, never inside Logic.

## 4. Does XcodeGen include `ios/CaneKit/Resources/`? How is a JSON resource added?

**Yes, automatically.** `project.yml` lists `- path: CaneKit` as the app target's source (everything under `ios/CaneKit/`, with only `Resources/Secrets.plist` excluded and re-added as an optional resource). XcodeGen puts non-source files (`.json`) in the Copy Bundle Resources phase. `route_isr_cif.json` and `indoor_isr.json` already ship this way and are read with `Bundle.main.url(forResource:withExtension:)`.

To add `waymark_priors.json`: drop it at `ios/CaneKit/Resources/waymark_priors.json`, then **`make gen` once** (the file list changed, so the project must be regenerated; CLAUDE.md rule). No `project.yml` edit needed. The Windows single-file commit should say "Mac: run make gen" in its message.

## 5. Prefetch lists and remaining budget (after the rename)

Measured with the Logic package on Linux (temporary probe test, not committed):

| List | Where | Characters used | Budget | Lines |
|---|---|---|---|---|
| `SpokenPhrases.warningLines` | Logic, pinned by `spokenPhrasesStayInsideTheCharacterBudget` | **1,718** | 2,000 | 74 |
| `SpokenPhrases.shellLines` | Logic, pinned by `shellLinesStayInsideTheirBudget` | **968** | 1,500 | 28 |
| `AppModel.commonLines` | App (`AppModel.swift` ~3697), no character test | — | — | — |

The rename shortened lines by one character each ("OpenCane" 8 → "Waymark" 7), so nothing grew.

The five Appendix-A lines total **138 characters** ("Reported obstacle ahead." 24, "Reported missing curb ramp ahead." 33, "Reported no sidewalk ahead." 27, "Reported rough surface ahead." 29, "Reported curb ramp ahead." 25). Plan: define them once in `WaymarkLines`, append `WaymarkLines.all` to `SpokenPhrases.warningLines` (1,718 + 138 = 1,856 ≤ 2,000, so the existing budget test still passes and still guards us). They are warnings, so `warningLines` is the right list rather than `commonLines`.

## 6. Where the rename touched credits or original-authors' names (D-10)

D-10 was relaxed at 14:20 (in-app credit optional, authors said credit is not required). The findings below stand either way; A3 (About row) becomes optional.

Searched the full rename diff for credit, about, author, team, copyright, hackathon and the original team's names.

- **No in-app credit, about text or author string exists in `ios/`.** OpenCane has no About screen; credits live in the root `README.md`, `AGENTS.md` and `docs/`, which the rename did not touch (it was scoped to `ios/`). So nothing in-app needs restoring, and A3 (new About row) is the right fix.
- **Restored (included in the rename commit):** the external Grok Bot routine is literally named **"OpenCane cane events"** on the original team's bot. The mechanical pass had changed that proper name to "Waymark cane events" in 5 comments (`GrokBotEvent.swift`, `GrokBotEventTests.swift`, `GrokBotClient.swift`, `AppModel.swift:153`, `Secrets.example.plist`). They now say "OpenCane cane events" again, because that is the name of somebody else's system. We don't use that bot (D-03, plan 7.5); family alerts stay disabled without a webhook key.
- Left as is, deliberately: the name "Aritro" in test fixtures (`HazardTests`, `EmergencyContactSeedTests`) and in two ElevenLabs comments ("the voice Aritro chose"). These are not shown to anyone; changing them buys nothing.

## 7. The Profile page photo (D-08)

- Where: `ios/CaneKit/UI/ProfilePage.swift` line ~80, inside the "EMERGENCY MEDICAL ID" card: `UIImage(named: "AritroProfile")`, asset `ios/CaneKit/Resources/Assets.xcassets/AritroProfile.imageset/aritro.jpg` (a photo of a real person from the original team). The Profile tab is the fourth root tab.
- The code already falls back to the SF Symbol `person.crop.circle.fill` when the image is missing.
- **Proposal (one line):** delete the `AritroProfile.imageset` folder from the asset catalog in a `waymark:` commit; the existing fallback then shows a neutral person symbol, with zero code change. Needs Akash to delete the folder in Finder or Terminal (my shell cannot delete). I'd like a W ack before doing it, since it removes original-team content from our tree.
- The profile name defaults to "Not set" (`MedicalProfileStore`), so no other personal data is shown by default.

---

## 8. Integration sketch for A1 and E1 (design note, no code yet)

Goal: the smallest `AppModel` diff, every line marked `// waymark:`. New code lives in `ios/CaneKit/Waymark/` (app) and `ios/Logic/Sources/CaneKitLogic/Waymark/` (pure).

### 8.1 New app files
- `ios/CaneKit/Waymark/WaymarkEngine.swift` — `@MainActor @Observable final class WaymarkEngine`. Owns `WaymarkPriorSet`, `WaymarkIndex`, the per-label beliefs, the alert policy state. Inputs: `ingest(fix: GeoFix, route: Route?, waypointIndex: Int, crossingSettle: Bool, voiceHeld: Bool, cueLevel: CueLevel, cuePlace: CuePlace)`, `ingest(report: LaneReport, now:)`, `ingest(groundHazard:at:)`, `spotter(_ outcome:)`, `routeStarted(_:)`, `routeEnded()`. Output: a closure `onSpeak: (String) -> Void` that AppModel wires to `speech.say(line, .obstacle, ttl: 6, load: .ambientObstacleName)`, plus `onLog: (String, [String: Any]) -> Void` wired to `logger.event`. Contains no literals; every number comes from Logic.
- `ios/CaneKit/Waymark/WaymarkStore.swift` — loads the bundle (`Bundle.main` or `WAYMARK_PRIORS_FILE`), appends `Documents/waymark/evidence.jsonl`, atomically writes `Documents/waymark/beliefs.json`. Never throws to the caller; a bad file logs `waymark_load {error}` and the engine stays inert.
- `ios/CaneKit/Waymark/WaymarkCard.swift`, `WaymarkMapView.swift` (A2).

### 8.2 `AppModel.swift` edit points (by function)

| # | Where (fe86e10 line ≈) | Edit |
|---|---|---|
| 1 | engine properties (`let cloud = CloudSync()` ~160) | `let waymark = WaymarkEngine()  // waymark:` |
| 2 | settings block (`hazardWatchEnabled` ~476) | `var waymarkEnabled: Bool = Settings.bool("waymarkEnabled", default: false) { didSet { Settings.set(…); waymark.enabled = waymarkEnabled } }` |
| 3 | `start()` (where `hazards.watchEnabled = hazardWatchEnabled` ~1035) | `waymark.enabled = waymarkEnabled`; wire `waymark.onSpeak` / `onLog`; `waymark.load()` |
| 4 | `wireNavigation()` → `location.onFix` (~3083), after `self.indoor.ingest(fix)` | `self.waymark.ingest(fix: fix, route: self.nav.route, waypointIndex: self.nav.waypointIndex, crossingSettle: self.nav.isCrossingSettle, voiceHeld: self.speech.isVoiceHeld, cueLevel: self.cueLevel, cuePlace: self.cuePlace)` |
| 5 | `handle(_ report: LaneReport)` (~2027), after the existing decider call | `waymark.ingest(report: report, now: …)` (E1: torso/head coverage, `isTrusted`, grid distances → evidence window) and `waymark.noteLidarCue(activeCue, now:)` so Waymark stays silent within 5 s of a LiDAR warning (v1.0 8.3) |
| 6 | `groundHazardFound(_:now:)` (~2666) | `waymark.ingest(groundHazard: g, at: location.fix)` (E1, curb evidence) |
| 7 | `startRouteNow(_:announce:)` (~4041) and `stopRoute()` (~3547) and `nav.onArrived` (~3234) | `waymark.routeStarted(route)` / `waymark.routeEnded()` (per-route cue cap resets) |
| 8 | `commonLines` (~3697) | nothing; the lines go in `SpokenPhrases.warningLines` (§5) |

Other base-repo edits (each one line, marked):
- `SpeechQueue.swift`: add `var isVoiceHeld: Bool { voiceHeld }` (the stored flag is private today; `setVoiceHold(_:)` is at ~1429).
- `LaunchRecovery.swift` `optionalFeatureKeys` (~98): add `"waymarkEnabled"`, and update its tests (`recoveryClearsEveryPersistedOptionalFeature`).
- `SpokenPhrases.swift`: `warningLines` gets `+ WaymarkLines.all`.
- `ContentView.swift` `SensePage` (~149, next to `HazardsCard()` ~159): `WaymarkCard()`.
- `HazardsCard.swift` or a new Settings card: the "Sidewalk memory" toggle (`CKToggleRow`), new accessibility label, no renames (rule 9).

Clock rule: Logic gets explicit `now` values. Wall clock for GPS/beliefs (`GeoFix.timestamp`, converted to UTC seconds at the engine boundary), AR clock (`report.timestamp`) only for the "LiDAR just warned" window. The two are never compared.

### 8.3 Cue gating inputs that already exist (so Logic can test them)
- Crossing settle: `nav.isCrossingSettle`.
- Voice hold (dictation): `SpeechQueue.voiceHeld` (needs the read accessor above).
- Cue level / place: `AppModel.cueLevel: CueLevel` (`.quiet`, `.standard`, `.detailed`) and `cuePlace: CuePlace` (`.outdoors`, `.indoors`), in Logic (`CueProfile.swift`).
- GPS weak: `nav.gpsWeak` (accuracy worse than `veerMaxAccuracy` for a while; the "GPS weak" pill), and `NavigationHealth.isFresh(timestamp:now:)` in Logic (`maxFixAge = 5` s). Waymark should require both "not `gpsWeak`" and a fresh fix.
- LiDAR active cue: `AppModel.activeCue: CueKind` (`.clear` when nothing is near).

## 9. Linux test loop (plan 7.1.4) — confirmed

- Swift 6.0.3 for Linux in the Mac session's cloud container; `swift test` on `ios/Logic`.
- Baseline `fe86e10`: **912 tests passed, exit 0**, with `HeadNodDetectorTests.swift` moved aside for the run only (Linux's compiler cannot type-check one expression in it in time; unchanged, runs on the Mac).
- With the rename commit applied: **912 passed, exit 0** (same caveat).
- Two caveats: the tests that read `ios/CaneKit/Resources/*.json` need the full `ios/` tree, not a copy of `Logic/` alone; and the Mac (Xcode 27.1's Swift) is the final gate via `make test`.
- The workaround is not committed.

## 10. L1 to L3 type design (design note, written in the prep lane; no code until the hold lifts)

All in `ios/Logic/Sources/CaneKitLogic/Waymark/`, `import Foundation` only, depending on the base
repo only through `Coordinate`, `GeoFix`, `GeoMath` (plan 1.4). Everything `public`, `Sendable`,
value types, no stored clocks.

### L1
```swift
public enum WaymarkLabelType: String, Sendable, Codable, CaseIterable {
    case curbRamp = "curb_ramp", missingCurbRamp = "missing_curb_ramp", obstacle,
         surfaceProblem = "surface_problem", noSidewalk = "no_sidewalk", crosswalk, other
    // init(from:) maps any unknown string to .other (never throws on an unknown value)
}
public struct WaymarkPrior: Sendable, Equatable, Codable, Identifiable {
    public let id: String            // "ps:<source_cluster_id>"
    public let type: WaymarkLabelType
    public let lat: Double, lng: Double
    public let severity: Double?     // D-19: a number in [1, 3], no rounding
    public let tags: [String]
    public let nAgree: Int, nDisagree: Int, nUnsure: Int, clusterSize: Int
    public let streetEdgeID: Int?, intersectionID: Int?, osmWayID: Int?
    public let imageryDate: String?, labelDate: String?   // "YYYY-MM"
    public let sourceClusterID: Int
    public var coordinate: Coordinate { get }
}
public struct WaymarkPriorSet: Sendable, Equatable {
    public static let schemaID = "waymark.priors.v1"
    public static let maxLabels = 20_000
    public static let maxBytes = 3 * 1024 * 1024
    public let generatedAt: String, sourceName: String, bboxLngLat: [Double], labels: [WaymarkPrior]
    public static func decode(_ data: Data) throws(WaymarkPriorError) -> WaymarkPriorSet
}
public enum WaymarkPriorError: Error, Equatable {
    case tooLarge(bytes: Int), wrongSchema(String), malformed(String),
         tooManyLabels(Int), badCoordinate(id: String), badSeverity(id: String),
         badBBox, idMismatch(id: String), duplicateID(String)
}
public struct WaymarkIndex: Sendable {
    public static let cellDegrees = 0.0005          // [H] about 55 m north-south
    public init(_ labels: [WaymarkPrior])
    public func within(_ radiusM: Double, of c: Coordinate) -> [WaymarkPrior]   // sorted by distance, then id
}
```
Tests: golden decode (inline 5.2 copy until `contracts/golden/` lands), unknown type → `.other`,
each rejection, extra fields ignored, index equals brute force on seeded random sets (including
labels exactly on cell edges and the antimeridian-free Seattle box), empty set.

### L2
```swift
public struct WaymarkCourse: Sendable { public let headingDeg: Double }   // from CourseSmoother or route legs
public enum WaymarkAhead {
    public static let lookaheadMaxM = 35.0, corridorHalfWidthM = 12.0     // [H]
    /// along-track 0...lookahead, |cross-track| <= corridor, closest first; [] when speed < 0.5 m/s
    public static func select(from candidates: [WaymarkPrior], at fix: GeoFix,
                              legs: [Coordinate]?, headingDeg: Double?) -> [(prior: WaymarkPrior, alongM: Double, crossM: Double)]
}
public enum WaymarkSensor: String, Sendable, Codable { case spotter, lidarTorso = "lidar_torso", lidarHead = "lidar_head", ground, vision }
public enum WaymarkOutcome: String, Sendable, Codable { case confirmed, contradicted, unverifiable }
public struct WaymarkBelief: Sendable, Equatable, Codable {
    public var eA: Double, eB: Double, tLast: Double?      // UTC seconds
    public static func halfLifeDays(_ t: WaymarkLabelType) -> Double     // 60 / 120 / 365
    public static func weight(_ s: WaymarkSensor) -> Double              // 2 / 1 / 1 / 0.5 / 0.5
    public func read(prior: WaymarkPrior, now: Double) -> (a: Double, b: Double, p: Double, nEff: Double)
    public mutating func update(_ o: WaymarkOutcome, sensor: WaymarkSensor, type: WaymarkLabelType, now: Double)
}
public enum WaymarkThreshold {
    public static func tau(costMiss: Double, costFalseAlarm: Double) -> Double   // C_fa / (C_fa + C_miss)
    public static func tau(for t: WaymarkLabelType) -> Double?                   // nil = never alerts on p alone
}
```
`n_eff` is display-only (D-20). Tests: every row of plan 5.3, `belief_vectors.json` once it lands,
unverifiable leaves `tLast`, monotonic tau, the four exact values to 1e-12.

### L3
```swift
public enum WaymarkLine: String, Sendable, CaseIterable { case obstacle, missingCurbRamp, noSidewalk, surfaceProblem, curbRamp
    public var text: String }                         // Appendix A, the only place the words live
public enum WaymarkLines { public static let all: [String] }   // appended to SpokenPhrases.warningLines
public struct WaymarkAlertInputs: Sendable {           // everything the policy may look at, plain values
    public let cueLevel: String, cuePlace: String       // raw values of CueLevel / CuePlace (portability: no base types)
    public let crossingSettle: Bool, voiceHeld: Bool, gpsWeak: Bool, fixFresh: Bool
    public let secondsSinceLidarCue: Double?, nowUTC: Double
}
public struct WaymarkAlertPolicy: Sendable {
    public static let minSpacingS = 20.0, maxPerRoute = 6          // [H]
    public mutating func decide(_ candidate: (prior: WaymarkPrior, alongM: Double), p: Double,
                                inputs: WaymarkAlertInputs) -> WaymarkDecision
    public mutating func routeStarted(), routeEnded()
}
public enum WaymarkDecision: Equatable, Sendable { case speak(WaymarkLine, labelID: String), silent(reason: String) }
public enum WaymarkRecord {                             // trip-log payloads; never a `t` or `kind` key
    public static func cue(...) -> [String: String], evidence(...) -> String   // evidence = one waymark.evidence.v1 JSON line
}
```
Portability note: `CueLevel` / `CuePlace` live in the base repo's Logic, so the policy takes their raw
strings ("quiet", "standard", "detailed"; "outdoors", "indoors") instead of the types, which keeps the
`Waymark/` folder free of base-repo types other than `Coordinate`, `GeoFix`, `GeoMath` (plan 1.4).
