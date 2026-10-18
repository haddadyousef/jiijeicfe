//
//  GuideCard.swift
//  CaneKit
//
//  The Guide: what the blind user (via VoiceOver) and the sighted teammate both need first.
//
//  UI v3 "Graphite" (owner, 2026-10-17: "reimagine the app — where the buttons are, the icons,
//  more user friendly, cooler, not flashy; same functionality"):
//
//    Idle                                   Walking (a route or the indoor leg)
//    ┌ route card ───────────────────────┐  ┌ compass card ──────────────────────┐
//    │ [route sketch]  Your route        │  │ NEXT STEP                stop 3/9   │
//    │                 To The Ave …      │  │        ◯ compass ring, arrow turns  │
//    │                 731 m · 9 stops   │  │          toward the next stop,      │
//    │ [ Start route              ›  ]   │  │          585 m in the centre        │
//    │ [ Directions from here     ›  ]   │  │ instruction (⚠ test contract)       │
//    │ ▸ Simulate walk · status lines    │  │ chips: On course · ±5 m · Dark      │
//    └───────────────────────────────────┘  └─────────────────────────────────────┘
//    chips: GPS · Light                     ( Repeat )  ( Next )  ( Recenter )
//    ◯ Talk to Waymark (giant microphone)   [ Stop route — tap twice to end    ]
//    [ Where am I — describe what's ahead ] ◯ Talk to Waymark (smaller)
//    describer lines                        Route status card: beacon, AirPods, Simulate
//    Where to? search card (+ error line)   error line
//
//  Why this shape: a sighted helper reads one big direction picture instead of numbers; Stop is
//  always on the first screen; the route is shown before it is started; the microphone stays the
//  largest target (Step 58, a blind tester could not find a small button). Nothing was removed.
//
//  Accessibility contract — everything the XCUITests drive lives here (AGENTS.md rule 9):
//    ⚠ test contract buttons: "Start route", "Directions from here", "Stop route", "Repeat",
//      "Next", "Recenter", "Where am I", "Simulate walk" (queried as `app.buttons[label]`); "Go"
//      and "Destination" are in `DestinationField`.
//    ⚠ test contract texts: the instruction `Text` stays a plain static text whose label is its
//      content (tests match "Townsend" / "Illinois Street" / "Starting the route"); the error line
//      stays a plain `Text` ("Type a destination first"); the describer lines stay plain texts
//      (testWhereAmIWithoutKeyReportsGracefully accepts "camera" or "Scene:").
//  The compass drawing and the route sketch are pictures (hidden from VoiceOver); their facts are
//  spoken by the distance element, the bearing chip and the route card's words.
//
//  Step 62 indoor state (`model.indoor.isActive`): the compass card shows a door symbol and the
//  indoor step line; the deck has Repeat / Next (no Recenter); the status card only the step
//  simulation. Owner / caller: `GuidePage` in ContentView.swift, which passes its `ScrollViewProxy`.
//  Tests: `CaneKitUITests` (start / stop, Next / Repeat / Recenter, Where am I, CIF-from-here,
//  destination field, default route) and both tours. 25° / 15 m thresholds here are display-only.
//

import CaneKitLogic
import SwiftUI

/// The Guide page's content: idle (route card, microphone, Where am I, search) or walking (compass,
/// control deck, microphone, route status). Reads `AppModel`; owns only the Stop gate.
struct GuideCard: View {
    /// App-wide owner of navigation, describer, beacon, audio route and location.
    @Environment(AppModel.self) private var model
    /// Distance figure in the compass, scaled with Dynamic Type (clamped at the call site).
    @ScaledMetric(relativeTo: .largeTitle) private var hero = 56
    /// Two-step gate for the destructive Stop route action; reset after its short confirmation
    /// window or whenever the route stops through another path.
    @State private var stopConfirmation = StopRouteConfirmation()
    /// Reduce Motion: the plain Simulate walk link presses without a scale.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The root scroll view's proxy, handed on to `DestinationField` so that focusing the search
    /// box scrolls it above the keyboard. nil in previews.
    var scroller: ScrollViewProxy? = nil
    /// waymark: the Sidewalk memory sheet (`WaymarkSheet`), opened from the chip or the ahead card.
    @State private var showWaymark = false

    /// Idle or walking layout (see the file header), plus the Stop-gate resets.
    var body: some View {
        VStack(alignment: .leading, spacing: CKSpacing.lg) {
            if walking {
                compassCard
                controlDeck
                // waymark: nearest report ahead, under Stop so the deck never moves (judge demo task 1);
                // not during the indoor leg, where street reports do not apply (review 3).
                if model.waymarkEnabled && !model.indoor.isActive { WaymarkAheadCard { showWaymark = true } }
            } else {
                routeCard
                statusChips
            }
            // One microphone outside the branches, so it keeps its identity (and VoiceOver focus)
            // when a spoken "route" / "stop" or the arrival flips `walking` (review C).
            // waymark: idle 0.30 → 0.18 with a capped disc (judge demo task 4, `WaymarkMicLayout`) so
            // the whole Where am I tile sits above the floating tab dock on a Pro Max at the default
            // text size and the rings still show; walking is unchanged (0.26, no cap). Both idle
            // numbers grow with Dynamic Type up to 0.30 (review fix), inside `VoiceTile`.
            // waymark: was `VoiceTile(heightFraction: walking ? 0.26 : 0.30)`.
            VoiceTile(walking: walking)
            if walking {
                describerLines
                routeStatusCard
                errorLine
            } else {
                whereAmIButton
                describerLines
                whereToCard
            }
        }
        .onChange(of: model.nav.isNavigating) { _, navigating in
            if !navigating { stopConfirmation.reset() }
        }
        .onChange(of: model.indoor.isActive) { _, active in
            if !active { stopConfirmation.reset() }
        }
        .sheet(isPresented: $showWaymark) { WaymarkSheet() }   // waymark:
    }

    // MARK: - Idle

    /// The demo route before it starts: its drawn shape, where it goes, how long; Start route;
    /// Directions from here; Simulate walk; Repeat after arrival; Cancel route start; the status.
    private var routeCard: some View {
        CKCard {
            HStack(alignment: .center, spacing: CKSpacing.lg) {
                RouteSketch(points: shownRoute?.waypoints.map(\.coordinate) ?? [])
                    .frame(width: 88, height: 88)
                    .background(CKColor.surfaceRaised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.nav.arrived ? "ARRIVED" : "YOUR ROUTE")
                        .font(CKFont.pill).kerning(0.8)
                        .foregroundStyle(CKColor.textSecondary)
                    Text(routeTitle)
                        .font(CKFont.cardTitle)
                        .foregroundStyle(CKColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(routeFacts)
                        .font(CKFont.secondary)
                        .foregroundStyle(CKColor.textSecondary)
                }
                Spacer(minLength: 0)
            }
            if model.nav.arrived {
                // The arrival line and trip summary are the longest of the walk: show and keep Repeat.
                // ⚠ test contract: after a mid-route Stop `arrived` is false, so no Repeat
                // (testGuideStartsAndStopsDemoRoute asserts it is gone).
                Text(model.nav.instruction)
                    .font(CKFont.body)
                    .foregroundStyle(CKColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                CKBigButton(title: "Repeat", subtitle: "Say the arrival again", systemImage: "speaker.wave.2.fill",
                            role: .secondary, hint: "Says the arrival line again") { model.repeatInstruction() }
            }
            if model.routeStartWaiting {
                // Waiting for depth after a camera transition (`DepthReadiness`): cancel without
                // the "Route stopped." of Stop. Start route / Directions are disabled meanwhile.
                CKBigButton(title: "Cancel route start", systemImage: "xmark",
                            role: .destructive,
                            hint: "Stops waiting for obstacle detection and does not start guidance") {
                    model.cancelRouteStart()
                }
            }
            // ⚠ test contract: "Start route" is the first thing every UI test waits for.
            CKBigButton(title: "Start route", subtitle: "Guided walk, step by step",
                        systemImage: "point.topleft.down.to.point.bottomright.curvepath.fill",
                        hint: AppModel.demoRouteDestination.isEmpty ? "Starts the demo route"
                            : "Starts the demo route to \(AppModel.demoRouteDestination)") { model.startDemoRoute() }
                .disabled(model.routeStartWaiting)
            // ⚠ test contract: "Directions from here" (its label is its text).
            CKBigButton(title: "Directions from here",
                        subtitle: "Apple Maps walk to the route's end",
                        systemImage: "arrow.triangle.turn.up.right.diamond.fill",
                        role: .secondary,
                        hint: "Builds a walking route with Apple Maps from where you are to \(AppModel.demoRouteDestination)",
                        value: model.isBuildingRoute ? "finding a route" : nil) { model.navigateToCIFFromHere() }
                .disabled(model.isBuildingRoute || model.routeStartWaiting)
            Button {
                model.startSimulatedWalk()
            } label: {
                Label("Simulate walk", systemImage: "play.circle")
                    .font(CKFont.body.weight(.semibold))
                    .foregroundStyle(CKColor.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: CKMetrics.touchTarget)
                    .contentShape(Rectangle())   // the whole row is the target (review B)
            }
            .buttonStyle(CKPressStyle(reduceMotion: reduceMotion))
            .disabled(model.routeStartWaiting || model.isBuildingRoute)
            .accessibilityLabel("Simulate walk")
            .accessibilityHint("Demo: plays the route step by step without moving")
            // Why a route has not started yet (waiting for depth, or timed out); not an error.
            if let status = model.routeStartStatus {
                Text(status)
                    .font(CKFont.secondary)
                    .foregroundStyle(CKColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(status)
            }
        }
    }

    /// Quiet facts for the idle page: GPS, sidewalk memory and, in the dark, the light. One row when it
    /// fits, else stacked (waymark review 5: the chip never truncates on a narrow phone or large text).
    private var statusChips: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: CKSpacing.sm) { chips; Spacer(minLength: 0) }
            VStack(alignment: .leading, spacing: CKSpacing.xs) { chips }
        }
    }

    /// The idle chips themselves.
    @ViewBuilder private var chips: some View {
        CKChip(text: gpsWord, systemImage: "location.fill", dot: gpsDot, spoken: "GPS: \(gpsWord)")
        WaymarkGuideChip { showWaymark = true }   // waymark: off → Turn on; on → reports loaded
        if model.lightState == .dark {
            CKChip(text: "Dark", systemImage: "moon.fill", spoken: "Low light; obstacle detection still works")
        }
    }

    /// "Where am I": one wide secondary button with the lens symbol. ⚠ test contract: "Where am I";
    /// "Describing…" while it works (testWhereAmIWithoutKeyReportsGracefully waits for it to return).
    private var whereAmIButton: some View {
        CKBigButton(title: model.describer.isDescribing ? "Describing…" : "Where am I",
                    subtitle: model.describer.isDescribing ? nil : "Describe what's ahead",
                    systemImage: "viewfinder", role: .secondary,
                    hint: "Takes a photo and reads out hazards and landmarks ahead",
                    value: model.describer.isDescribing ? "in progress" : nil) { model.describeScene() }
            .disabled(model.describer.isDescribing)
    }

    /// The scene description and the describer's error, as plain texts (test contract above).
    @ViewBuilder private var describerLines: some View {
        if !model.describer.lastDescription.isEmpty {
            Text(model.describer.lastDescription)
                .font(CKFont.body)
                .foregroundStyle(CKColor.textPrimary)
                .accessibilityLabel("Scene: \(model.describer.lastDescription)")
        }
        if let err = model.describer.lastError {
            CKErrorText(text: err)
        }
    }

    /// "Where to?": the destination field (+ live suggestions and Go, in `DestinationField`) and the
    /// route / location error line right under it.
    private var whereToCard: some View {
        CKCard(title: "Where to?", systemImage: "magnifyingglass") {
            DestinationField(scroller: scroller)
            errorLine
        }
    }

    // MARK: - Walking

    /// The compass card: heading word and progress, the compass ring with the distance in its
    /// centre, the instruction, the indoor step line and the status chips.
    private var compassCard: some View {
        CKCard {
            HStack {
                Text(headerWord.uppercased())
                    .font(CKFont.pill).kerning(0.8)
                    .foregroundStyle(CKColor.textSecondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                if let progress = progressWord {
                    Text(progress)
                        .font(CKFont.pill)
                        .foregroundStyle(CKColor.textSecondary)
                        .monospacedDigit()
                }
            }
            ZStack {
                CompassRing(bearingError: model.indoor.isActive ? nil : model.nav.bearingError,
                            symbol: model.indoor.isActive ? "door.left.hand.open" : nil)
                    .frame(width: 210, height: 210)
                    .accessibilityHidden(true)
                if let d = model.nav.distanceToNext, model.nav.isNavigating {
                    VStack(spacing: 0) {
                        Text("\(d)")
                            .font(CKFont.hero(min(hero, 72)))
                            .foregroundStyle(CKColor.textPrimary)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        Text("meters")
                            .font(CKFont.secondary.weight(.semibold))
                            .foregroundStyle(CKColor.textSecondary)
                    }
                    .frame(width: 120)
                    // One element with an explicit sentence.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(d) meters to the next point")
                }
            }
            .frame(maxWidth: .infinity)
            // ⚠ test contract: plain Text whose accessibility label is the instruction itself.
            Text(model.indoor.isActive ? model.indoor.currentSay : model.nav.instruction)
                .font(CKFont.instruction)
                .foregroundStyle(CKColor.textPrimary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits([.isHeader, .updatesFrequently])
            if model.indoor.isActive {
                Text(model.indoor.guideLine)
                    .font(CKFont.button)
                    .foregroundStyle(CKColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: CKSpacing.sm) {
                    if let err = model.nav.bearingError, model.nav.isNavigating {
                        CKStatusPill(text: bearingWord(err), tone: abs(err) <= 25 ? .trusted : .warning,
                                     systemImage: abs(err) <= 25 ? "arrow.up" : (err > 0 ? "arrow.turn.up.right" : "arrow.turn.up.left"),
                                     spoken: "Heading: \(bearingWord(err))", updatesFrequently: true)
                    }
                    CKChip(text: gpsWord, systemImage: "location.fill", dot: gpsDot, spoken: "GPS: \(gpsWord)")
                    // waymark: off → the chip offers it (on, the ahead card under Stop says it all).
                    if !model.waymarkEnabled { WaymarkGuideChip { showWaymark = true } }
                    if model.nav.gpsWeak {
                        CKStatusPill(text: "GPS weak", tone: .warning, systemImage: "exclamationmark.triangle")
                    }
                    if model.lightState == .dark {
                        CKStatusPill(text: "Dark", tone: .warning, systemImage: "moon.fill",
                                     spoken: "Low light; obstacle detection still works")
                    }
                }
            }
        }
    }

    /// The control deck: Repeat, Next and (outdoors) Recenter as round actions, then Stop route
    /// full width — all on the first screen. ⚠ test contract labels unchanged.
    @ViewBuilder private var controlDeck: some View {
        HStack(alignment: .top, spacing: CKSpacing.sm) {
            CKCircleAction(title: "Repeat", systemImage: "speaker.wave.2.fill", prominent: true,
                           hint: "Says the current instruction again") { model.repeatInstruction() }
            // `nextWaypoint()`, not `nav.next()`: one code path with the watch Next, the crown and Siri.
            CKCircleAction(title: "Next", systemImage: "forward.end.fill",
                           hint: "Skips to the next instruction") { model.nextWaypoint() }
            if model.nav.isNavigating {
                CKCircleAction(title: "Recenter", systemImage: "scope",
                               hint: "Sets straight ahead as the beacon's forward direction") { model.recenter() }
            }
        }
        stopRouteButton
        if stopConfirmation.isArmed {
            Text("Tap Stop route again within 3 seconds to end guidance.")
                .font(CKFont.secondary)
                .foregroundStyle(CKColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Stop route is armed. Tap Stop route again within 3 seconds to end guidance.")
        }
    }

    /// "Route status" while walking: beacon and headphone chips, Simulate walk / Stop simulation;
    /// indoors only the step simulation.
    private var routeStatusCard: some View {
        CKCard(title: "Route status", systemImage: "waveform.path.ecg") {
            if model.nav.isNavigating {
                // Beacon: warning without headphones (it cannot play), trusted while it plays.
                HStack(spacing: CKSpacing.sm) {
                    CKStatusPill(text: beaconWord, tone: !model.audioRoute.headphonesConnected ? .warning
                                 : (model.beacon.isRunning && model.beaconEnabled ? .trusted : .neutral),
                                 systemImage: "dot.radiowaves.left.and.right",
                                 spoken: "Beacon: \(beaconWord)", updatesFrequently: true)
                    CKStatusPill(text: headWord,
                                 tone: model.audioRoute.headphonesConnected ? .neutral : .warning,
                                 systemImage: "airpodspro",
                                 spoken: headSpoken)
                }
                if model.isSimulatingWalk {
                    CKBigButton(title: "Stop simulation", systemImage: "pause.fill", role: .secondary,
                                hint: "Pauses the walk simulation") { model.stopSimulatedWalk() }
                } else {
                    // ⚠ test contract (CaneKitIslandTour taps it when present).
                    CKBigButton(title: "Simulate walk", systemImage: "play.fill", role: .secondary,
                                hint: "Simulates walking along the active route indoors") { model.startSimulatedWalk() }
                }
            } else {
                if model.indoor.isSimulating {
                    CKBigButton(title: "Stop simulation", systemImage: "pause.fill", role: .secondary,
                                hint: "Pauses the indoor step simulation") { model.stopSimulatedWalk() }
                } else {
                    CKBigButton(title: "Simulate walk", systemImage: "play.fill", role: .secondary,
                                hint: "Simulates walking the indoor steps without moving") { model.startSimulatedWalk() }
                }
            }
        }
    }

    /// The route / location error line.
    @ViewBuilder private var errorLine: some View {
        // ⚠ test contract: the error text stays a plain `Text` whose label is its content
        // ("Type a destination first"); the glyph is hidden. Only after something failed.
        if let err = model.routeError ?? model.location.lastError ?? model.liveActivity.lastError {
            CKErrorText(text: err)
                .padding(.horizontal, CKSpacing.xs)
        }
    }

    /// Stop route is deliberately a two-tap confirmation (Step 51a): the first tap arms (spoken and
    /// visible), a second inside `StopRouteConfirmation.window` ends guidance. Full width under the
    /// deck, so it is always on the first screen. VoiceOver label exactly "Stop route".
    private var stopRouteButton: some View {
        CKBigButton(title: "Stop route", subtitle: stopConfirmation.isArmed ? "Tap again to stop" : "Tap twice to end",
                    systemImage: "stop.fill", role: .destructive,
                    hint: stopConfirmation.isArmed
                        ? "Confirms ending guidance when tapped again within 3 seconds"
                        : "Arms route stop; tap again within 3 seconds to end guidance",
                    value: stopConfirmation.isArmed ? "confirmation needed" : nil) {
            stopRoutePressed()
        }
        .task(id: stopConfirmation.isArmed) {
            guard stopConfirmation.isArmed else { return }
            try? await Task.sleep(for: .seconds(StopRouteConfirmation.window))
            guard !Task.isCancelled else { return }
            stopConfirmation.reset()
        }
    }

    /// Handles one press of the two-step Stop route gate.
    private func stopRoutePressed() {
        switch stopConfirmation.press(at: ProcessInfo.processInfo.systemUptime) {
        case .armed:
            model.logger.event("route", ["action": "stop_armed"])
            model.speech.say(AppModel.stopRouteConfirmationLine, .nav, ttl: 4)
        case .confirmed:
            stopConfirmation.reset()
            model.stopRoute()
        }
    }

    // MARK: - Words

    /// True while a route or the indoor leg guides.
    private var walking: Bool { model.nav.isNavigating || model.indoor.isActive }

    /// The route the card describes: after arrival the route just walked (a typed or Directions
    /// route too, review A), otherwise the demo route that Start route will run.
    private var shownRoute: Route? {
        model.nav.arrived ? (model.nav.route ?? AppModel.demoRoute) : AppModel.demoRoute
    }

    /// "To The Ave and NE 50th" (the demo route's destination); after arrival the walked route's name.
    private var routeTitle: String {
        if model.nav.arrived, let name = model.nav.route?.name, !name.isEmpty { return name }
        return AppModel.demoRouteDestination.isEmpty ? "Demo route" : "To \(AppModel.demoRouteDestination)"
    }

    /// "731 m · 9 stops" for `shownRoute` (polyline length, display only).
    private var routeFacts: String {
        let w = shownRoute?.waypoints ?? []
        let length = model.nav.arrived
            ? zip(w, w.dropFirst()).map { GeoMath.distanceMeters($0.coordinate, $1.coordinate) }.reduce(0, +)
            : AppModel.demoRouteLengthM
        let m = Int(length.rounded())
        return m > 0 ? "\(m) m · \(w.count) stops" : "\(w.count) stops"
    }

    /// The compass card's heading word.
    private var headerWord: String {
        model.indoor.isActive ? "Indoors" : "Next step"
    }

    /// "Stop 3 of 9" while a route runs.
    private var progressWord: String? {
        guard model.nav.isNavigating, let count = model.nav.route?.waypoints.count, count > 0 else { return nil }
        return "Stop \(min(model.nav.waypointIndex + 1, count)) of \(count)"
    }

    /// Beacon pill word: "Beacon off" → "Beacon paused" (no headphones) → error / "Beacon idle" →
    /// "Beacon N%".
    private var beaconWord: String {
        guard model.beaconEnabled else { return "Beacon off" }
        guard model.audioRoute.headphonesConnected else { return "Beacon paused" }
        guard model.beacon.isRunning else { return model.beacon.lastError ?? "Beacon idle" }
        return "Beacon \(Int(model.beacon.renderedVolume * 100))%"
    }

    /// No headphones → say so; AirPods motion flowing → head tracked; else compass only.
    private var headWord: String {
        guard model.audioRoute.headphonesConnected else { return "No AirPods" }
        return model.head.isConnected ? "Head tracked" : "Compass only"
    }

    /// VoiceOver sentence for the headphone pill.
    private var headSpoken: String {
        guard model.audioRoute.headphonesConnected else { return "No headphones connected; beacon paused" }
        return model.head.isConnected ? "\(model.audioRoute.outputName), head tracking on"
                                      : "\(model.audioRoute.outputName), no head tracking"
    }

    /// "On course" within ±25° (design.md §5), else "Veer right N°" / "Veer left N°".
    private func bearingWord(_ err: Double) -> String {
        if abs(err) <= 25 { return "On course" }
        return err > 0 ? "Veer right \(Int(abs(err)))°" : "Veer left \(Int(abs(err)))°"
    }

    /// GPS chip word: "Denied" / "Searching" / "Off" without a fix, "No accuracy", else "±N m".
    private var gpsWord: String {
        guard let f = model.location.fix else {
            return model.location.denied ? "Denied" : (model.location.isRunning ? "Searching" : "Off")
        }
        return f.accuracy < 0 ? "No accuracy" : "±\(Int(f.accuracy)) m"
    }

    /// GPS chip dot: blue at ≤ 15 m, amber above, none without a valid fix (words always say it).
    private var gpsDot: Color? {
        guard let f = model.location.fix, f.accuracy >= 0 else { return nil }
        return f.accuracy <= 15 ? CKColor.trusted : CKColor.warning
    }
}

// MARK: - Pictures (decoration; the words carry the meaning)

/// The route's shape: waypoints fitted into the frame (north up, aspect kept), a line with a start
/// dot and a finish ring. Empty when there are fewer than two points.
private struct RouteSketch: View {
    /// Waypoint coordinates in order.
    let points: [Coordinate]

    /// The sketch, drawn by the nonisolated `draw` (the same pattern as `ContourRings`).
    var body: some View {
        let points = points
        let ink = CKColor.textPrimary
        Canvas { context, size in
            RouteSketch.draw(in: &context, size: size, points: points, ink: ink)
        }
    }

    /// Fits the points into `size` (equirectangular, longitude scaled by cos(latitude)) and strokes
    /// the line, a start dot and a finish ring in `ink`.
    nonisolated static func draw(in context: inout GraphicsContext, size: CGSize,
                                 points: [Coordinate], ink: Color) {
        guard points.count > 1 else { return }
        let lat0 = points.map(\.latitude).reduce(0, +) / Double(points.count)
        let k = cos(lat0 * .pi / 180)
        let xs = points.map { $0.longitude * k }
        let ys = points.map { $0.latitude }
        let minX = xs.min() ?? 0, maxX = xs.max() ?? 0, minY = ys.min() ?? 0, maxY = ys.max() ?? 0
        let span = max(maxX - minX, maxY - minY, 1e-9)
        let side = Double(min(size.width, size.height)) - 32
        let cx = Double(size.width) / 2, cy = Double(size.height) / 2
        let pts = (0..<points.count).map { i in
            CGPoint(x: cx + (xs[i] - (minX + maxX) / 2) / span * side,
                    y: cy - (ys[i] - (minY + maxY) / 2) / span * side)
        }
        var path = Path()
        path.addLines(pts)
        context.stroke(path, with: .color(ink),
                       style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        let s = pts[0], e = pts[pts.count - 1]
        context.fill(Path(ellipseIn: CGRect(x: s.x - 5, y: s.y - 5, width: 10, height: 10)), with: .color(ink))
        context.stroke(Path(ellipseIn: CGRect(x: e.x - 6, y: e.y - 6, width: 12, height: 12)),
                       with: .color(ink), lineWidth: 3)
    }
}

/// The compass: a ring with 12 ticks and an arrow that turns toward the next stop (bearing error,
/// + = to the right). Without a bearing the arrow points up, dimmed; indoors a symbol replaces it.
private struct CompassRing: View {
    /// Degrees to turn (nil = unknown).
    let bearingError: Double?
    /// A symbol in place of the arrow (indoors).
    var symbol: String? = nil
    /// Reduce Motion: no turning animation.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The drawn angle, unwrapped so the arrow always turns the short way (+179° → −179° is 2°).
    @State private var shown: Double = 0

    /// Ring, 12 ticks (quarters longer), then the arrow (turned by the bearing error) or the symbol.
    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(CKColor.border, lineWidth: 10)
            ForEach(0..<12, id: \.self) { i in
                Capsule()
                    .fill(CKColor.textSecondary.opacity(i % 3 == 0 ? 0.9 : 0.4))
                    .frame(width: i % 3 == 0 ? 3 : 2, height: i % 3 == 0 ? 12 : 7)
                    .offset(y: -86)
                    .rotationEffect(.degrees(Double(i) * 30))
            }
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(CKColor.textPrimary)
            } else {
                Image(systemName: "location.north.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(CKColor.textPrimary.opacity(bearingError == nil ? 0.3 : 1))
                    .offset(y: -70)
                    .rotationEffect(.degrees(shown))
                    .onAppear { shown = bearingError ?? 0 }
                    .onChange(of: bearingError ?? 0) { _, target in
                        let step = (target - shown).truncatingRemainder(dividingBy: 360)
                        let short = step > 180 ? step - 360 : (step < -180 ? step + 360 : step)
                        if reduceMotion { shown += short } else {
                            withAnimation(.easeOut(duration: 0.4)) { shown += short }
                        }
                    }
            }
        }
    }
}
