//
//  VoiceTile.swift
//  CaneKit
//
//  The voice shell's face (Step 58): one giant round microphone in the middle of the Guide page,
//  inside ~40 thin, hand-drawn-looking contour rings. Tap anywhere on the rings to talk.
//
//  Why this exists: the first cane-mounted walk (2026-09-13) showed a blind walker cannot find a
//  108 pt "Talk to Waymark" tile among eleven buttons. Owner decision 2026-09-13: the launch
//  screen is a giant microphone dead-centre (reference image: a circle of concentric wavy contour
//  rings around a clear centre). The whole ring area — at least 60 % of the page height — is one
//  button, so a thumb that lands anywhere near the middle of the phone talks. The rings say what
//  the app is doing to a sighted spotter: they ripple outward while the microphone listens, breathe
//  while the app speaks, and are still when idle. Reduce Motion keeps them still.
//
//  Key invariants:
//    · One accessibility element: the button, label exactly "Talk to Waymark" / "Listening…" /
//      "Starting…" / "Thinking…" (the same state logic the old Talk tile had); the rings are hidden.
//    · Action is `AppModel.toggleVoiceInput()` — press to talk, press again to send / cancel.
//    · The rings are pure drawing from a seeded per-ring noise: the same shape every launch, no
//      random state, no timers when still (`TimelineView` paused).
//    · Theme colours only (`CKColor`): ink rings on the page, accent disc, danger disc while listening.
//
//  Owner / caller: `GuideCard` (UI v3: under the route card idle, under the control deck walking).
//  Tests: no unit test (drawing); the UI tests reach the buttons below it through `scrollTo`
//  (`CaneKitUITests`, `CaneKitVisualTour`, `CaneKitIslandTour`); `make tour` pictures show it.
//

import CaneKitLogic
import SwiftUI

/// The giant microphone: contour rings + disc as one button, and a status line under it.
struct VoiceTile: View {
    /// Voice input state, the assistant's last answer, and the speech queue's `isSpeaking`.
    @Environment(AppModel.self) private var model
    /// Reduce Motion: the rings never move.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Microphone disc diameter, scaled with Dynamic Type so the glyph keeps its margin.
    @ScaledMetric(relativeTo: .largeTitle) private var disc: CGFloat = 116

    /// Shown under the rings when there is no answer yet: the three words to start with.
    static let hintLine = "Tap to talk. Try “route”, “where am I” or “help”."

    /// waymark: the Guide state (judge demo task 4 + review fix). It picks the ring square through
    /// `WaymarkMicLayout.square(walking:textScale:)`: walking 0.26 of the visible page, no disc cap
    /// (under the compass and the control deck, unchanged from UI v3); idle 0.18 with the disc capped
    /// at 0.62 of the square at the default text size (was 0.30, which left the Where am I tile cut
    /// in half by the tab dock on a Pro Max), both growing with Dynamic Type up to 0.30 so the idle
    /// disc still reaches its full scaled size at accessibility sizes.
    /// History: this was `heightFraction: CGFloat = 0.46`; UI v2 (2026-10-17) passed 0.40 idle and
    /// 0.30 while walking, so the tiles under it (Where am I / Start route; Repeat / Stop route) sit
    /// above the tab bar — the 04-navigating tour shot at 0.46 had the whole walking grid below the
    /// fold under a long instruction. Still the largest target on the page.
    var walking = false

    /// waymark: the ring square for this state and text size (`WaymarkMicLayout`).
    private var square: WaymarkMicLayout.Square {
        WaymarkMicLayout.square(walking: walking,
                                textScale: WaymarkMicLayout.textScale(preferredDisc: Double(disc)))
    }

    /// waymark: the disc diameter drawn in a square of `side` points (`WaymarkMicLayout.discDiameter`).
    /// `side` comes from the same layout pass as the square itself, so the disc never draws at the
    /// uncapped size for a frame (review fix: no "pop" at launch or on Stop / arrival).
    private func discSize(side: CGFloat) -> CGFloat {
        CGFloat(WaymarkMicLayout.discDiameter(preferred: Double(disc), side: Double(side),
                                              maxShare: square.discShare))
    }

    /// Rings + disc as one button, then the status line.
    var body: some View {
        VStack(spacing: CKSpacing.md) {
            Button { model.toggleVoiceInput() } label: {
                // waymark: GeometryReader so the idle disc cap uses this pass's square side (the
                // shorter edge). It fills exactly the frame below, as the greedy rings canvas did.
                GeometryReader { geo in
                    let discSize = discSize(side: min(geo.size.width, geo.size.height))
                    ZStack {
                        ContourRings(motion: reduceMotion ? .still : motion, ink: CKColor.textPrimary)
                        Circle()
                            .fill(isBusy ? CKColor.danger : CKColor.accent)
                            .frame(width: discSize, height: discSize)   // waymark: was `disc`
                            .overlay {
                                Image(systemName: glyph)
                                    .font(.system(size: discSize * 0.38, weight: .bold))
                                    .foregroundStyle(isBusy ? CKColor.ink : CKColor.onAccent)
                            }
                            .accessibilityHidden(true)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }
                .frame(maxWidth: .infinity)
                // UI audit 2026-09-13: 0.6 → 0.46 of the visible page so the compact row (Where am I /
                // Start route) sits above the tab bar on a 17 Pro Max instead of cut in half, and
                // stays reachable on smaller iPhones. Still the largest target on the page.
                // waymark: the share is `square.heightFraction` (was `heightFraction`).
                .containerRelativeFrame(.vertical) { height, _ in height * CGFloat(square.heightFraction) }
                // The whole ring square is the target, not just the stroked pixels.
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityHint(model.voiceInput.isStarting ? "Tap to cancel microphone setup"
                               : "Tap to speak a command, ask a question, or set a post")
            .accessibilityValue(model.voiceInput.isListening ? "listening"
                                : (model.voiceInput.isStarting ? "starting" : ""))

            Text(statusLine)
                .font(CKFont.body)
                .foregroundStyle(CKColor.textPrimary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(answer.map { "Assistant: \($0)" } ?? statusLine)
        }
    }

    /// The button's label: the same four states the old Talk tile used.
    private var title: String {
        if model.voiceInput.isListening { return "Listening…" }
        if model.voiceInput.isStarting { return "Starting…" }
        if model.conversation.isProcessing { return "Thinking…" }
        return "Talk to Waymark"
    }

    /// Listening or starting: the disc turns danger red (today's convention for "tap to stop").
    private var isBusy: Bool { model.voiceInput.isListening || model.voiceInput.isStarting }

    /// SF Symbol inside the disc.
    private var glyph: String {
        model.voiceInput.isListening ? "waveform" : (model.voiceInput.isStarting ? "hourglass" : "mic.fill")
    }

    /// Ripple while listening, breathe while the app speaks, still otherwise.
    private var motion: ContourRings.Motion {
        if model.voiceInput.isListening { return .ripple }
        if model.speech.isSpeaking { return .breathe }
        return .still
    }

    /// The assistant's last answer, if any (non-empty).
    private var answer: String? {
        guard let r = model.conversation.lastResponse, !r.isEmpty else { return nil }
        return r
    }

    /// The last answer, or the three-word hint before the first one.
    private var statusLine: String { answer ?? Self.hintLine }
}

/// ~40 concentric, slightly wobbly rings around a clear centre, drawn in a `Canvas`.
///
/// Each ring's wobble is three sine harmonics whose frequencies, phases and amplitudes come from a
/// per-ring seed, so the drawing looks hand-made but is identical every frame and every launch.
/// Hidden from VoiceOver (the button carries the meaning).
struct ContourRings: View {
    /// What the rings are doing.
    enum Motion: Sendable { case still, ripple, breathe }

    /// Current motion; `.still` pauses the timeline entirely.
    let motion: Motion
    /// Stroke colour (a theme token, resolved by the canvas for light / dark / high contrast).
    let ink: Color

    /// Number of rings.
    nonisolated static let ringCount = 40

    /// A 30 fps timeline while moving, paused when still.
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: motion == .still)) { context in
            let t = motion == .still ? 0 : context.date.timeIntervalSinceReferenceDate
            let motion = motion
            let ink = ink
            Canvas { ctx, size in
                ContourRings.draw(in: &ctx, size: size, t: t, motion: motion, ink: ink)
            }
        }
        .accessibilityHidden(true)
    }

    /// Strokes every ring for time `t` (seconds; 0 when still).
    /// - Parameters:
    ///   - ctx: the canvas context.
    ///   - size: the canvas size; rings fit the inscribed circle.
    ///   - t: animation clock.
    ///   - motion: ripple travels a crest outward (~1 ring-width per 0.1 s); breathe scales all
    ///     rings ±2.5 % over 2 s, inner rings leading.
    ///   - ink: stroke colour; inner rings are darker, outer rings fade.
    nonisolated static func draw(in ctx: inout GraphicsContext, size: CGSize, t: Double,
                                 motion: Motion, ink: Color) {
        let side = Double(min(size.width, size.height))
        let cx = Double(size.width) / 2, cy = Double(size.height) / 2
        let inner = side * 0.19, outer = side * 0.49
        let steps = 144
        for i in 0..<ringCount {
            let f = Double(i) / Double(ringCount - 1)          // 0 innermost … 1 outermost
            // Ring math shared with the island's brand mark (Step 64: ios/Shared/Brand/ContourRingGeometry.swift).
            let params = ContourRingParameters(index: i)
            // Wobble grows outward, like contour lines loosening away from a summit.
            let a = side * (0.0025 + 0.009 * f)
            var base = inner + (outer - inner) * f
            var gain = 1.0
            var drift = 0.0
            switch motion {
            case .still:
                break
            case .ripple:
                let phase = t * 5 - f * 9                        // crest moves outward as t grows
                let crest = max(0, sin(phase))
                gain = 1 + 1.6 * crest
                base += side * 0.006 * crest
                drift = t * 0.35
            case .breathe:
                base *= 1 + 0.025 * sin(t * .pi - f * 1.2)
            }
            let path = ContourRingGeometry.ring(params, center: CGPoint(x: cx, y: cy), base: base,
                                                amplitude: a, gain: gain, drift: drift, steps: steps)
            ctx.stroke(path, with: .color(ink.opacity(0.75 - 0.5 * f)), lineWidth: 1)
        }
    }
}

// `SeededNoise` moved to ios/Shared/Brand/ContourRingGeometry.swift in Step 64 (shared with the widget).
