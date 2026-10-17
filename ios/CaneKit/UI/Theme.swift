//
//  Theme.swift
//  CaneKit
//
//  Design tokens and the three reusable components. The prose twin is docs/design.md;
//  when the two disagree, fix this file.
//
//  Implements docs/design.md §1 (typography → CKFont), §2 (colour tokens → CKColor),
//  §3 (spacing, radius, touch targets → CKSpacing / CKRadius / CKMetrics), §4 (owned
//  animations: big-button press; tab switch lives in TabBar.swift), §7 ("Do not" list)
//  and §8 (implementation notes for the twin).
//
//  Rules baked in here so views can't get them wrong:
//    · every colour has light / dark / increased-contrast variants (UIKit trait providers)
//    · text on any coloured fill is always `CKColor.ink`
//    · numbers that change use tabular digits
//    · big buttons are ≥ 72 pt tall, carry a word and a symbol, and take a VoiceOver hint
//    · Reduce Motion is honoured by the animations we own (button press, tab switch)
//
//  Accessibility contract:
//    · `CKBigButton` exposes `accessibilityLabel(title)`. XCUITests query `app.buttons[title]`,
//      so every `title` string passed in from GuideCard is a ⚠ test contract (AGENTS.md rule 9).
//    · `CKBigButtonStyle` is also applied to plain `Button`s (Go, haptic / wrist test buttons);
//      those set their own labels at the call site.
//    · `CKStatusPill` is one VoiceOver element whose label is `spoken ?? text`.
//    · `CKCard` is a `.contain` container: titled cards are rotor stops, children stay reachable.
//
//  Swift 6, default MainActor isolation (project.yml). The colour helper is `nonisolated`
//  because UIKit may resolve dynamic colours off the main thread.
//
//  Owners / callers: every file in ios/CaneKit/UI (the watch has its own `WatchTheme.swift`).
//  Tests: none unit-level (tokens are values); `CaneKitUITests` query the labels `CKBigButton`
//  sets, and `make tour` (`CaneKitVisualTour`) is the visual check. Contrast ratios quoted below
//  come from docs/design.md §2 and must be re-checked there when a hex value changes.
//

import SwiftUI
import UIKit

// MARK: - Colour

/// Semantic colours. See docs/design.md §2 for the hex table and contrast ratios.
///
/// Every token is a dynamic `Color` that re-resolves for light / dark and Increase Contrast, so
/// no view in the app constructs a `Color` literal (design.md §8). Nothing here is colour-only
/// meaning: every lane fill is paired with a level word and a number in `LaneTile`.
enum CKColor {

    // Surfaces: warm neutrals tinted toward cane ivory, never pure grey.
    /// Screen ground behind every card (`ContentView`). Ivory in light, near-black in dark.
    static let background    = dynamic(0xF4F1EA, 0x0E0D0B, hcLight: 0xFFFFFF, hcDark: 0x000000)
    /// `CKCard` fill. Flat: elevation is a fill change plus a hairline, never a shadow (§7).
    static let surface       = dynamic(0xFFFFFF, 0x1A1816, hcLight: 0xFFFFFF, hcDark: 0x0A0A0A)
    /// Secondary-button fill and the no-data tile fill (via `laneNoData` / `neutral`).
    static let surfaceRaised = dynamic(0xEAE6DD, 0x26231F, hcLight: 0xE3DED3, hcDark: 0x141210)
    /// Hairlines on cards and secondary buttons; flips to pure black / white under Increase Contrast.
    static let border        = dynamic(0xC9C3B6, 0x3A362F, hcLight: 0x000000, hcDark: 0xFFFFFF)

    // Text.
    /// Body text on `background` / `surface` (≥ 14:1).
    static let textPrimary   = dynamic(0x17140F, 0xF4F1EA, hcLight: 0x000000, hcDark: 0xFFFFFF)
    /// Hints, card titles, secondary rows (≥ 6.5:1). Never used for text a hazard depends on.
    static let textSecondary = dynamic(0x5C574D, 0xB5AFA3, hcLight: 0x3A362F, hcDark: 0xD9D4C9)

    /// The brand accent (UI v2, 2026-10-17; was "cane white on ink"): deep blue `#1E40AF` in light
    /// mode (white text 8.7:1, AAA), sky blue `#84ADF8` in dark mode (dark text 8.6:1). Blue is the
    /// one hue every colour-vision type sees as itself. Primary buttons, the selected tab, the voice
    /// disc and the button badges. It never carries hazard meaning; hazard is only the lane ladder.
    static let accent   = dynamic(0x1E40AF, 0x84ADF8, hcLight: 0x1E3A8A, hcDark: 0xA8C5FF)
    /// Text / symbols on an `accent` fill (primary `CKBigButton`, selected tab).
    static let onAccent = dynamic(0xFFFFFF, 0x0E0D0B, hcLight: 0xFFFFFF, hcDark: 0x000000)
    /// Text on every coloured fill (lane tiles, pills, banners). One rule, no exceptions.
    static let ink      = dynamic(0x17140F, 0x17140F, hcLight: 0x000000, hcDark: 0x000000)

    // Lane ladder: identical in light and dark (the fill *is* the signal).
    // Thresholds live in CaneKitLogic.TileLevel: clear ≥ 2.0 m, far ≥ 1.2, near ≥ 0.7, urgent < 0.7.
    //
    // Waymark UI rework (2026-10-17): colour-blind-safe ladder, blue → yellow → amber → rose. The old
    // green / yellow / orange / red ladder put CLEAR and NEAR 0.071 apart (OKLab) for deuteranopes and
    // NEAR and STOP 0.059 apart for tritanopes. This set keeps every pair ≥ 0.116 apart for normal,
    // protan, deutan and tritan vision (Machado 2009 simulation, gamut-clamped, design.md §2) and every fill
    // ≥ 7:1 against `ink`. Blue for CLEAR also stops "green = go" being the only reading of safe.
    // The tile still carries a word and a number, and NEAR / STOP add a glyph and STOP a border,
    // so no state depends on colour alone (LaneTile).
    /// Tile ≥ 2.0 m (level word CLEAR). Sky blue, 8.1:1 against `ink`. Also the `trusted` pill tone.
    static let laneClear  = dynamic(0x84ADF8, 0x84ADF8, hcLight: 0x84ADF8, hcDark: 0x84ADF8)
    /// Tile 1.2–2.0 m (level word FAR). Lemon, 16.4:1 against `ink`.
    static let laneFar    = dynamic(0xFCF855, 0xFCF855, hcLight: 0xFCF855, hcDark: 0xFCF855)
    /// Tile 0.7–1.2 m (level word NEAR). Amber, 10.6:1 against `ink`. Also the `warning` tone.
    static let laneNear   = dynamic(0xF8BA48, 0xF8BA48, hcLight: 0xF8BA48, hcDark: 0xF8BA48)
    /// Tile < 0.7 m (level word STOP). Rose, 7.1:1 against `ink`. Also `danger` (Stop route).
    /// Never used as text colour: rose on a white card is 2.6:1 — errors use `CKErrorText`.
    static let laneUrgent = dynamic(0xFD748F, 0xFD748F, hcLight: 0xFD748F, hcDark: 0xFD748F)
    /// Tile with no depth data ("—" / NO DATA); text on it is `textSecondary`, not `ink`.
    static let laneNoData = surfaceRaised

    // Status.
    /// Pill tone for a healthy state (TRUSTED, Engine OK, Reachable, GPS within 15 m).
    static let trusted = laneClear
    /// Pill tone for a degraded-but-working state (SWEEPING, GPS weak, Speaking, No AirPods). The
    /// same amber as NEAR (one "caution" colour instead of two that colour-blind eyes merge).
    static let warning = laneNear
    /// Destructive button fill (Stop route) and failure pills (Engine down).
    static let danger  = laneUrgent
    /// Idle / informational pill tone; text on it is `textPrimary` (the only non-ink pill).
    static let neutral = surfaceRaised

    /// Builds a `Color` that re-resolves for light/dark and Increase Contrast automatically.
    ///
    /// - Parameters: 0xRRGGBB for light, dark, high-contrast light and high-contrast dark.
    /// - Note: `nonisolated` because UIKit may call the trait provider off the main thread; the
    ///   closure touches only its value-type captures.
    nonisolated private static func dynamic(_ light: UInt32, _ dark: UInt32,
                                            hcLight: UInt32, hcDark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hc = traits.accessibilityContrast == .high
            let isDark = traits.userInterfaceStyle == .dark
            let hex = isDark ? (hc ? hcDark : dark) : (hc ? hcLight : light)
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255,
                           alpha: 1)
        })
    }
}

// MARK: - Type

/// Text styles. System faces only: SF Pro for prose, SF Rounded for glanceable numbers and
/// button labels, SF Mono reserved for developer-only views (`mono`, unused since the debug
/// footer was removed in Step 11). Everything scales with Dynamic Type.
///
/// Implements the scale table in docs/design.md §1. `secondary` (15 pt) is the smallest size a
/// user ever reads; `mono` (13 pt) is allowed only inside `accessibilityHidden` developer views.
enum CKFont {
    /// Distance on Guide. Pass a value from `@ScaledMetric(relativeTo: .largeTitle) var hero = 64`.
    static func hero(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy, design: .rounded).monospacedDigit()
    }
    /// Metres inside a depth tile (28 pt base). Readable from a metre away.
    static let tile        = Font.system(.title, design: .rounded).weight(.bold).monospacedDigit()
    /// Current instruction (`GuideCard`) and the Sense status line. No line cap is applied at the
    /// call sites (`lineLimit(nil)` + vertical `fixedSize`): the text wraps and is never truncated
    /// or shrunk — the spotter reads it over the walker's shoulder.
    static let instruction = Font.system(.title2, design: .default).weight(.semibold)
    /// Big button labels (UI v2: bold).
    static let button      = Font.system(.title3, design: .rounded).weight(.bold)
    /// Settings rows and section headers' titles.
    static let label       = Font.headline
    /// Card titles (UI v2: one size up from `label`, rounded, so each card reads as a heading).
    static let cardTitle   = Font.system(.title3, design: .rounded).weight(.bold)
    /// Toggle labels, scene description text, route names.
    static let body        = Font.body
    /// Status pills: uppercase, 1–2 words, tracking added in the view.
    static let pill        = Font.system(.subheadline, design: .rounded).weight(.bold)
    /// Hints and secondary lines. The smallest user-facing size.
    static let secondary   = Font.subheadline
    /// Developer-only views; the view must be `accessibilityHidden(true)`. Currently unused (the
    /// debug footer it was made for is gone).
    static let mono        = Font.system(.footnote, design: .monospaced).monospacedDigit()
}

// MARK: - Spacing, radius, metrics

/// 4 pt base. Named for intent so layouts read as decisions, not numbers.
///
/// docs/design.md §3. Values are layout only; none of them carry meaning.
enum CKSpacing {
    /// 4 pt: icon-to-text inside a pill.
    static let xs: CGFloat = 4      // icon-to-text inside a pill
    /// 8 pt: between pills; tile gap.
    static let sm: CGFloat = 8      // between pills; tile gap
    /// 12 pt: rows inside a card.
    static let md: CGFloat = 12     // rows inside a card
    /// 16 pt: card padding; between big buttons.
    static let lg: CGFloat = 16     // card padding; between big buttons
    /// 24 pt: between sections (cards on the root scroll view).
    static let xl: CGFloat = 24     // between sections
    /// 32 pt: above the button stack on Guide (design.md §3). Not referenced by any view today.
    static let xxl: CGFloat = 32    // above the button stack on Guide
    /// 20 pt: screen-edge padding.
    static let gutter: CGFloat = 20 // screen edge
}

/// Corner radii (docs/design.md §3). All shapes use `.continuous` corners.
enum CKRadius {
    /// Depth tiles.
    static let tile: CGFloat = 14
    /// Big buttons (UI v2: 22, softer; still a slab, not a pill).
    static let button: CGFloat = 22
    /// Cards (UI v2: 26).
    static let card: CGFloat = 26
    /// Status pills (effectively a capsule). Not referenced: `CKStatusPill` draws a `Capsule()`.
    static let pill: CGFloat = 999
}

/// Touch-target and stroke metrics (docs/design.md §3 "Touch targets", §8 "Border width").
enum CKMetrics {
    /// Minimum height of anything tappable on the phone that is not a `CKBigButton` (Go, the
    /// destination field, its clear button and suggestion rows, the haptic / wrist test buttons,
    /// the share button, each tab). Big buttons use `bigButton`.
    static let touchTarget: CGFloat = 60
    /// `CKBigButton` minimum height (UI v2: 76 pt, full or half width).
    static let bigButton: CGFloat = 76
    /// Minimum height of a `CKBigButton` in `tile` layout (badge over word over subtitle); the
    /// pair's `HStack` stretches both tiles to the taller one. Step 47; UI v2 124 pt.
    static let tile: CGFloat = 124
    /// Hairline normally; a real border under Increase Contrast.
    static func border(for contrast: ColorSchemeContrast) -> CGFloat {
        contrast == .increased ? 3 : 1
    }
}

// MARK: - CKBigButton

/// The action button of the app: every Guide button except Go and the destination field's own
/// controls, plus "Speech test" and the self-test buttons. Full width by default, a word plus an SF
/// Symbol, and a VoiceOver hint that says what happens (docs/design.md §6 has the copy).
///
/// UI v2 (2026-10-17, owner: "change the button format, simpler and better overall"): one format
/// everywhere — the symbol sits in a round badge, the title is bold, an optional one-line subtitle
/// says what the button does, and every row ends in a chevron so it reads as tappable. Tiles (two
/// across) put the badge top-left and the words under it, left-aligned, like a Shortcuts tile.
/// Fills: primary = `accent` (deep blue / sky blue), secondary = `surface` card with a border,
/// destructive = `danger` (rose) with `ink` text.
///
/// Accessibility: label = `title` (⚠ test contract: XCUITests find it as `app.buttons[title]`),
/// hint = `hint`, value = `value`; the SF Symbol and the subtitle are not part of the label.
/// The visible text never truncates: it wraps, and at accessibility sizes the row restacks.
struct CKBigButton: View {
    /// Fill / foreground pairing: `primary` = accent, `secondary` = surface with a border,
    /// `destructive` = `danger` fill with ink text (Stop route).
    enum Role { case primary, secondary, destructive }

    /// `row` = badge, words and chevron across the button; `tile` = badge over the words, for a
    /// pair (or a 2 × 2 grid) placed side by side. A pair is always `tile`, and the pair's `HStack`
    /// gets `.fixedSize(horizontal: false, vertical: true)` so both tiles take the taller height.
    enum Layout { case row, tile }

    /// Visible word and VoiceOver label. ⚠ test contract for every title used by the XCUITests.
    let title: String
    /// Optional one-line subtitle under the title: what the button does or where it goes.
    var subtitle: String? = nil
    /// SF Symbol in the badge; hidden from VoiceOver (a companion, never the only cue).
    let systemImage: String
    /// Visual role; see `Role`.
    var role: Role = .primary
    /// Label arrangement; see `Layout`. Default `row` (every full-width button).
    var layout: Layout = .row
    /// VoiceOver hint: what the button does, in one sentence. Optional only for previews.
    var hint: String? = nil
    /// Optional VoiceOver value ("Describing…") while the action is in flight.
    var value: String? = nil
    /// Tap handler. Runs on the main actor.
    let action: () -> Void

    /// A `Button` with the row or tile label, styled by `CKBigButtonStyle`.
    var body: some View {
        Button(action: action) {
            if layout == .tile { tileLabel } else { rowLabel }
        }
        .buttonStyle(CKBigButtonStyle(role: role))
        // ⚠ test contract: the label is exactly `title`; do not decorate it.
        .accessibilityLabel(title)
        .accessibilityHint(hint ?? "")
        .accessibilityValue(value ?? "")
    }

    /// Words colour of the subtitle per role (slightly quieter than the title).
    private var subtitleStyle: Color {
        switch role {
        case .primary: CKColor.onAccent.opacity(0.85)
        case .secondary: CKColor.textSecondary
        case .destructive: CKColor.ink.opacity(0.8)
        }
    }

    /// `tile`: badge top-left, then the title and subtitle, left-aligned, filling the width and any
    /// height the pair's `HStack` gives it (≥ `CKMetrics.tile`).
    private var tileLabel: some View {
        VStack(alignment: .leading, spacing: CKSpacing.sm) {
            CKButtonBadge(systemImage: systemImage, role: role, size: 46)
            Spacer(minLength: 0)
            Text(title)
                .font(CKFont.button)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(CKFont.secondary)
                    .foregroundStyle(subtitleStyle)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(CKSpacing.lg)
        .frame(maxWidth: .infinity, minHeight: CKMetrics.tile, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(RoundedRectangle(cornerRadius: CKRadius.button, style: .continuous))
    }

    /// `row`: badge, words, chevron. At accessibility text sizes the row won't fit, so the words
    /// stack under the badge.
    private var rowLabel: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: CKSpacing.md) {
                CKButtonBadge(systemImage: systemImage, role: role, size: 40)
                // Flexible width so a long subtitle wraps instead of making `ViewThatFits`
                // reject the row (Step 47: "Simulate walk" stacked alone).
                VStack(alignment: .leading, spacing: 2) {
                    text
                    if let subtitle {
                        Text(subtitle)
                            .font(CKFont.secondary)
                            .foregroundStyle(subtitleStyle)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.bold))
                    .opacity(0.55)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: CKSpacing.xs) {
                CKButtonBadge(systemImage: systemImage, role: role, size: 40)
                text
                if let subtitle {
                    Text(subtitle)
                        .font(CKFont.secondary)
                        .foregroundStyle(subtitleStyle)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, CKSpacing.lg)
        .padding(.vertical, CKSpacing.md)
        .frame(maxWidth: .infinity, minHeight: CKMetrics.bigButton, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: CKRadius.button, style: .continuous))
    }

    /// The visible word; wraps vertically instead of truncating (design.md §1, §7).
    private var text: some View {
        Text(title)
            .font(CKFont.button)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The round symbol badge inside a `CKBigButton`: a translucent disc of the foreground colour
/// behind the symbol, so the symbol reads as an icon on every fill. Hidden from VoiceOver.
struct CKButtonBadge: View {
    /// SF Symbol.
    let systemImage: String
    /// The button's role (picks the disc tint).
    let role: CKBigButton.Role
    /// Disc diameter in points.
    var size: CGFloat = 40

    /// Disc + symbol; the symbol inherits the button's foreground colour.
    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.45, weight: .bold))
            .frame(width: size, height: size)
            .background(Circle().fill(disc))
            .accessibilityHidden(true)
    }

    /// Disc fill: a soft wash of the foreground on primary / destructive, an accent wash on secondary.
    private var disc: Color {
        switch role {
        case .primary: CKColor.onAccent.opacity(0.18)
        case .secondary: CKColor.accent.opacity(0.12)
        case .destructive: CKColor.ink.opacity(0.12)
        }
    }
}

/// Fill + border per role and press feedback that respects Reduce Motion.
///
/// Implements docs/design.md §4 "Big button press": scale 0.97 on a 120 ms spring, or opacity
/// 0.85 only under Reduce Motion; the light impact haptic fires on the press-down edge either way
/// (`sensoryFeedback(_:trigger:condition:)` passes `(oldValue, newValue)`: `$0 == false && $1`).
/// Disabled buttons drop to 40 % opacity; VoiceOver announces "dimmed" from `.disabled`.
/// Also applied directly to plain `Button`s / `ShareLink`: Go, the haptic and wrist test buttons,
/// "Share hazard map".
struct CKBigButtonStyle: ButtonStyle {
    /// Picks fill, foreground and border; shared with `CKBigButton.Role`.
    let role: CKBigButton.Role
    /// Reduce Motion swaps the scale spring for a plain opacity change.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Increase Contrast thickens the secondary border (via `CKMetrics.border(for:)`).
    @Environment(\.colorSchemeContrast) private var contrast
    /// Drives the 40 % disabled opacity.
    @Environment(\.isEnabled) private var isEnabled

    /// Applies fill, border, disabled / pressed feedback and the press haptic to the label.
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: CKRadius.button, style: .continuous)
        configuration.label
            .foregroundStyle(foreground)
            .background(fill, in: shape)
            .overlay(shape.strokeBorder(CKColor.border, lineWidth: role == .secondary
                                        ? CKMetrics.border(for: contrast) + 0.5 : 0))
            .opacity(isEnabled ? 1 : 0.4)
            .opacity(configuration.isPressed && reduceMotion ? 0.85 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .spring(duration: 0.12), value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { $0 == false && $1 }
    }

    /// Background colour per role.
    private var fill: Color {
        switch role {
        case .primary: CKColor.accent
        case .secondary: CKColor.surface
        case .destructive: CKColor.danger
        }
    }

    /// Text / symbol colour per role; `ink` on the coloured destructive fill (one rule, §2).
    private var foreground: Color {
        switch role {
        case .primary: CKColor.onAccent
        case .secondary: CKColor.textPrimary
        case .destructive: CKColor.ink
        }
    }
}

// MARK: - CKStatusPill

/// One or two uppercase words on a solid fill: TRUSTED, SWEEPING, HOT, 82%. Ink text always.
///
/// Accessibility: one element (children ignored) labelled `spoken ?? text`, so a terse visible
/// word can carry a full spoken sentence. Always has a word: never colour-only (design.md §7).
/// Adds `.updatesFrequently` when asked, so VoiceOver re-reads a live pill on focus (§5 rule).
struct CKStatusPill: View {
    /// Fill colour family: `trusted` / `warning` / `danger` use `ink` text; `neutral` uses
    /// `textPrimary` on the raised surface; `accent` is ink-on-ivory / ivory-on-ink (the brand
    /// pairing) for a mark that is not a state — today only the "Campus" badge on a destination
    /// suggestion (design.md §2, §6.3). Accent never carries hazard meaning.
    enum Tone { case trusted, warning, danger, neutral, accent }

    /// Visible word(s); uppercased when drawn. Also the VoiceOver label when `spoken` is nil.
    let text: String
    /// Fill colour family; see `Tone`.
    var tone: Tone = .neutral
    /// Optional leading SF Symbol (a companion; the element's label comes from the text).
    var systemImage: String? = nil
    /// VoiceOver **label** (not value) when the visible text is too terse ("82%" → "Battery 82
    /// percent"); nil reads `text` as written (not uppercased).
    var spoken: String? = nil
    /// Set for pills that change on their own (TRUSTED/SWEEPING) so VoiceOver re-reads them.
    var updatesFrequently: Bool = false

    /// Optional bold icon + uppercased, tracked, tabular text that never wraps (it scales down to
    /// 80 % instead), on a `Capsule` fill at least 32 pt tall.
    var body: some View {
        HStack(spacing: CKSpacing.xs) {
            if let systemImage {
                Image(systemName: systemImage).font(.subheadline.weight(.bold))
            }
            Text(text.uppercased())
                .font(CKFont.pill)
                .kerning(0.9)
                .monospacedDigit()
                .lineLimit(1)                       // a pill never hyphenates ("SPEAK-ING")
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, CKSpacing.md)
        .frame(minHeight: 32)
        .background(fill, in: Capsule())
        // One element: the icon and the uppercased text are replaced by the spoken label.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken ?? text)
        .accessibilityAddTraits(updatesFrequently ? .updatesFrequently : [])
    }

    /// Capsule fill per tone.
    private var fill: Color {
        switch tone {
        case .trusted: CKColor.trusted
        case .warning: CKColor.warning
        case .danger: CKColor.danger
        case .neutral: CKColor.neutral
        case .accent: CKColor.accent
        }
    }

    /// Text / symbol colour: `ink` on every coloured fill (§2, one rule), `textPrimary` on the
    /// raised neutral surface, `onAccent` on the accent fill.
    private var foreground: Color {
        switch tone {
        case .neutral: CKColor.textPrimary
        case .accent: CKColor.onAccent
        default: CKColor.ink
        }
    }
}

// MARK: - CKCard

/// A flat surface with a hairline. Groups its children as one VoiceOver container whose label
/// is the title, so the rotor can jump card to card.
///
/// docs/design.md §3 (radius 20, `lg` padding, no shadow) and §8 ("`CKCard(title:)` groups
/// children as one VoiceOver container"). The title is drawn as a `.isHeader` so the headings
/// rotor stops on "Guide", "Arrived" / "This trip" (Guide page); "Obstacles", "Hazards" (Sense);
/// "Cues", "Haptics", "Watch", "Mount", "This phone" (Settings). An untitled card (the Sense
/// page's status card) gets an empty label here and sets its own label afterwards.
struct CKCard<Content: View>: View {
    /// Optional card heading; also the container's VoiceOver label.
    var title: String? = nil
    /// Optional SF Symbol drawn in a small badge before the title (UI audit 2026-09-13). Hidden
    /// from VoiceOver: the title carries the meaning.
    var systemImage: String? = nil
    /// Optional one-sentence plain-language caption under the title: what the card is for.
    var caption: String? = nil
    /// The card's rows.
    @ViewBuilder let content: () -> Content
    /// Increase Contrast thickens the card border to 3 pt.
    @Environment(\.colorSchemeContrast) private var contrast

    /// Header (badge + title with the header trait, then the caption) then the rows, `lg` padding,
    /// full width, `surface` fill in a continuous `card`-radius shape with a hairline (3 pt under
    /// Increase Contrast). No shadow.
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: CKRadius.card, style: .continuous)
        VStack(alignment: .leading, spacing: CKSpacing.md) {
            if let title {
                VStack(alignment: .leading, spacing: CKSpacing.xs) {
                    HStack(spacing: CKSpacing.md) {
                        if let systemImage { CKIconBadge(systemImage: systemImage, tinted: true) }
                        Text(title)
                            .font(CKFont.cardTitle)
                            .foregroundStyle(CKColor.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                    }
                    if let caption {
                        Text(caption)
                            .font(CKFont.secondary)
                            .foregroundStyle(CKColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.bottom, CKSpacing.xs)
            }
            content()
        }
        .padding(CKSpacing.lg + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CKColor.surface, in: shape)
        .overlay(shape.strokeBorder(CKColor.border.opacity(contrast == .increased ? 1 : 0.7),
                                    lineWidth: CKMetrics.border(for: contrast)))
        .accessibilityElement(children: .contain)
        // An empty label would override the children for VoiceOver; only label titled cards.
        .accessibilityLabel(title.map { Text($0) } ?? Text(""))
    }
}

// MARK: - Settings rows (UI audit 2026-09-13)

/// A small rounded-square badge holding an SF Symbol: the leading mark of a card title or a
/// settings row, the way iOS Settings marks its rows. Decoration only, hidden from VoiceOver.
struct CKIconBadge: View {
    /// SF Symbol drawn in the badge.
    let systemImage: String
    /// UI v2: card titles use an accent-tinted badge (accent symbol on a soft accent wash) so each
    /// card is easy to find by its symbol; settings rows keep the neutral one.
    var tinted: Bool = false

    /// 32 pt rounded square with a semibold symbol.
    var body: some View {
        Image(systemName: systemImage)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(tinted ? CKColor.accent : CKColor.textPrimary)
            .frame(width: 32, height: 32)
            .background(tinted ? CKColor.accent.opacity(0.12) : CKColor.surfaceRaised,
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// One settings switch: optional icon badge, a short title, and a plain-language subtitle under it.
///
/// Accessibility: the switch's VoiceOver label is exactly `title` (⚠ XCUITests query
/// `app.switches[title]`, so the subtitle must never leak into the label); the hint is `hint`, or the
/// subtitle when no separate hint is given. The row grows with Dynamic Type; nothing truncates.
struct CKToggleRow: View {
    /// Visible title and the switch's VoiceOver label (a test contract for some rows).
    let title: String
    /// One short sentence under the title saying what the switch does, in everyday words.
    var subtitle: String? = nil
    /// Optional leading SF Symbol badge.
    var systemImage: String? = nil
    /// The setting.
    @Binding var isOn: Bool
    /// VoiceOver hint; defaults to the subtitle.
    var hint: String? = nil

    /// A system `Toggle` whose label is the badge + title + subtitle.
    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(alignment: .center, spacing: CKSpacing.md) {
                if let systemImage { CKIconBadge(systemImage: systemImage) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(CKFont.body)
                        .foregroundStyle(CKColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle {
                        Text(subtitle)
                            .font(CKFont.secondary)
                            .foregroundStyle(CKColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .accessibilityLabel(title)
        .accessibilityHint(hint ?? subtitle ?? "")
    }
}

/// A hairline between rows inside a card. Hidden from VoiceOver.
struct CKRowDivider: View {
    /// 1 pt `border` line.
    var body: some View {
        Rectangle()
            .fill(CKColor.border.opacity(0.6))
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

/// A small uppercase group label above a run of cards on a page ("EVERYDAY", "TESTING TOOLS").
/// A VoiceOver heading, so the rotor can jump between groups.
struct CKSectionHeader: View {
    /// The group's name; drawn as written (UI v2; it was uppercased).
    let title: String

    /// UI v2: a real heading — `CKFont.cardTitle` size in `textPrimary`, not small caps.
    var body: some View {
        Text(title)
            .font(.system(.title2, design: .rounded).weight(.bold))
            .foregroundStyle(CKColor.textPrimary)
            .padding(.horizontal, CKSpacing.xs)
            .padding(.top, CKSpacing.sm)
            .padding(.bottom, -CKSpacing.sm)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Waymark UI rework (2026-10-17): progressive disclosure and error text

/// A collapsible group of cards on a page: one tappable header ("More settings", "Diagnostics")
/// and, when open, its cards below it. Used to keep each page to what a walk needs while every
/// control stays one tap away (owner request 2026-10-17: simpler, nothing removed).
///
/// Rules: never put a ⚠ test-contract control inside one (the XCUITests do not open sections), nor a
/// warning or a control the app may need the walker to reach while something is on (callers show
/// those cards directly instead — HazardsCard); the open / closed state is remembered per section
/// (`@AppStorage("ui.more.<storageKey>")`), so a teammate who opened Diagnostics once finds it open
/// next launch — except under `CANEKIT_UITEST=1`, where a throwaway store keeps every run closed
/// (deterministic tests); the header is ≥ 60 pt, a VoiceOver heading (rotor), carries a chevron
/// that turns (no motion under Reduce Motion), and speaks "<title>, collapsed / expanded".
struct CKMoreSection<Content: View>: View {
    /// Header text and the button's VoiceOver label.
    let title: String
    /// One plain sentence under the title: what is inside.
    var caption: String? = nil
    /// Header badge symbol.
    var systemImage: String = "ellipsis.circle"
    /// The section's cards, shown only while open.
    @ViewBuilder let content: () -> Content
    /// Open / closed, persisted per section.
    @AppStorage private var expanded: Bool
    /// Reduce Motion: open and close without the chevron turn and the fade.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Increase Contrast thickens the header border.
    @Environment(\.colorSchemeContrast) private var contrast

    /// - Parameters:
    ///   - title: header text and VoiceOver label.
    ///   - caption: optional sentence under the title.
    ///   - systemImage: header badge symbol.
    ///   - storageKey: stable id for the remembered state (`ui.more.<storageKey>`).
    ///   - content: the cards inside.
    init(title: String, caption: String? = nil, systemImage: String = "ellipsis.circle",
         storageKey: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.caption = caption
        self.systemImage = systemImage
        self.content = content
        _expanded = AppStorage(wrappedValue: false, "ui.more.\(storageKey)", store: Self.store)
    }

    /// `.standard`, or under `CANEKIT_UITEST=1` a suite emptied once per launch, so a section a
    /// person opened on that simulator cannot change what a UI test sees (review H1).
    private static var store: UserDefaults { CKMoreSectionStore.shared }

    /// Header button, then the content when open, spaced like the page's cards.
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: CKRadius.card, style: .continuous)
        VStack(alignment: .leading, spacing: CKSpacing.xl) {
            Button {
                if reduceMotion { expanded.toggle() } else {
                    withAnimation(.easeOut(duration: 0.2)) { expanded.toggle() }
                }
            } label: {
                HStack(spacing: CKSpacing.md) {
                    CKIconBadge(systemImage: systemImage, tinted: true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(CKFont.cardTitle)
                            .foregroundStyle(CKColor.textPrimary)
                        if let caption {
                            Text(caption)
                                .font(CKFont.secondary)
                                .foregroundStyle(CKColor.textSecondary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(CKColor.textSecondary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .padding(CKSpacing.lg)
                .frame(maxWidth: .infinity, minHeight: CKMetrics.touchTarget, alignment: .leading)
                .contentShape(shape)
            }
            .buttonStyle(.plain)
            .background(CKColor.surface, in: shape)
            .overlay(shape.strokeBorder(CKColor.border, lineWidth: CKMetrics.border(for: contrast)))
            .accessibilityLabel(title)
            .accessibilityValue(expanded ? "expanded" : "collapsed")
            .accessibilityHint(expanded ? "Hides this section" : "Shows \(caption.map { $0.lowercased() } ?? "more")")
            .accessibilityAddTraits(.isHeader)
            if expanded {
                content()
                    .transition(reduceMotion ? .identity : .opacity)
            }
        }
    }
}

/// The one `UserDefaults` store behind every `CKMoreSection` (a generic type cannot hold a static
/// stored property, so it lives here). `.standard` normally; under `CANEKIT_UITEST=1` the
/// "waymark.uitest.sections" suite, emptied the first time it is read in each launch.
enum CKMoreSectionStore {
    /// See the type doc. Main actor (UI only).
    static let shared: UserDefaults = {
        guard ProcessInfo.processInfo.environment["CANEKIT_UITEST"] == "1",
              let suite = UserDefaults(suiteName: "waymark.uitest.sections") else { return .standard }
        suite.removePersistentDomain(forName: "waymark.uitest.sections")
        return suite
    }()
}

/// An error, failure or attention line: a glyph (hidden from VoiceOver) and the message in
/// `textPrimary`. Replaces red / rose / amber text, which is 1.7–2.8:1 on a white card and
/// unreadable for many low-vision and colour-blind readers (design.md §10). The text stays a plain
/// `Text` whose label is its content, so tests that match an error string still find it.
struct CKErrorText: View {
    /// The message, shown and spoken as written.
    let text: String
    /// The glyph: a warning triangle by default; `exclamationmark.circle` for a reminder that is not
    /// a failure ("Not saved yet").
    var systemImage: String = "exclamationmark.triangle.fill"

    /// Glyph in `danger`, words in `textPrimary`, wrapping, never truncated.
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: CKSpacing.sm) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(CKColor.danger)
                .accessibilityHidden(true)
            Text(text)
                .font(CKFont.secondary)
                .foregroundStyle(CKColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Preview

/// Xcode canvas preview of every component in one stack (design review only; no test uses it).
#Preview("Components") {
    VStack(spacing: CKSpacing.lg) {
        HStack(spacing: CKSpacing.sm) {
            CKStatusPill(text: "Trusted", tone: .trusted, systemImage: "checkmark", updatesFrequently: true)
            CKStatusPill(text: "Sweeping", tone: .warning)
            CKStatusPill(text: "82%", spoken: "Battery 82 percent")
        }
        CKCard(title: "Next instruction") {
            Text("Turn left onto Goodwin Avenue").font(CKFont.instruction)
            Text("120 m").font(CKFont.hero(64)).foregroundStyle(CKColor.textPrimary)
        }
        CKBigButton(title: "Stop route", systemImage: "stop.fill", role: .destructive,
                    hint: "Ends guidance and shows the arrival summary") {}
        HStack(spacing: CKSpacing.lg) {
            CKBigButton(title: "Recenter", systemImage: "location.north.line", role: .secondary,
                        hint: "Sets straight ahead as the beacon's forward direction") {}
            CKBigButton(title: "Next", systemImage: "forward.fill", hint: "Skips to the next instruction") {}
        }
    }
    .padding(CKSpacing.gutter)
    .background(CKColor.background)
}
