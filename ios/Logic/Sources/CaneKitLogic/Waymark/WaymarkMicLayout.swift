//
//  WaymarkMicLayout.swift
//  CaneKitLogic
//
//  Judge demo task 4: the Guide microphone's display geometry (`VoiceTile`). The idle ring square
//  was 0.30 of the visible page, which left the "Where am I / Describe what's ahead" tile cut in
//  half by the floating tab dock on a Pro Max (tour shot 01-idle-top). It is now 0.18; at that size
//  the 116 pt disc would cover all but a ~6 pt band of the contour rings (the rings are how a
//  sighted spotter sees "listening"), so the idle disc is capped at 0.62 of the square. The whole
//  full-width ring square stays the button, still the largest target on the page. The walking
//  layout is unchanged (0.26, no cap).
//
//  Review fix: both idle numbers are for the default text size. At larger Dynamic Type sizes the
//  idle square and the cap grow by the same ratio as the `@ScaledMetric` disc (`square`), up to the
//  UI v3 idle square (0.30), so a low-vision walker at an accessibility size gets the full-size
//  microphone again (the default-size layout cannot keep the tile above the dock there anyway).
//
//  Pure, Foundation-only, display-only. Caller: `VoiceTile` (`square`, `discDiameter`; `GuideCard`
//  passes `walking`). Tests: `WaymarkMicLayoutTests.swift`.
//

import Foundation

/// Microphone ring square and disc sizes for the Guide page. Namespace only.
public enum WaymarkMicLayout {
    /// Idle Guide: share of the visible page the ring square takes (was 0.30 in UI v3).
    public static let idleHeightFraction: Double = 0.18
    /// Walking Guide: share of the visible page the ring square takes (unchanged from UI v3).
    public static let walkingHeightFraction: Double = 0.26
    /// Idle Guide: largest disc diameter as a share of the ring square's side.
    public static let idleDiscShare: Double = 0.62

    /// The disc diameter to draw.
    /// - Parameters:
    ///   - preferred: the Dynamic Type–scaled diameter (`VoiceTile.disc`, 116 pt at the default size).
    ///   - side: the ring square's measured side in points; 0 or less before the first layout pass.
    ///   - maxShare: the cap as a share of `side`, or nil for no cap (walking).
    /// - Returns: `min(preferred, side × maxShare)` when capped and measured, else `preferred`.
    ///   Pinned by `aCappedDiscLeavesRoomForTheRings`, `withoutACapTheDiscKeepsItsPreferredSize`,
    ///   `anUnmeasuredSquareKeepsThePreferredDisc`.
    public static func discDiameter(preferred: Double, side: Double, maxShare: Double?) -> Double {
        guard let maxShare, side > 0 else { return preferred }
        return min(preferred, side * maxShare)
    }

    // MARK: Dynamic Type (review fix, finding 1)

    /// The disc diameter at the default text size (`VoiceTile.disc`'s `@ScaledMetric` base).
    public static let defaultDiscDiameter: Double = 116
    /// The idle square never grows past the UI v3 idle share, whatever the text size.
    public static let idleHeightFractionCeiling: Double = 0.30

    /// How far Dynamic Type has grown the disc: `preferredDisc / defaultDiscDiameter`, never below 1
    /// (smaller text sizes keep the default layout) and 1 for a non-finite or non-positive input.
    /// Pinned by `theTextScaleIsThePreferredDiscOverTheDefaultAndNeverBelowOne`.
    public static func textScale(preferredDisc: Double) -> Double {
        guard preferredDisc.isFinite, preferredDisc > 0 else { return 1 }
        return max(1, preferredDisc / defaultDiscDiameter)
    }

    /// The ring square for one Guide state.
    public struct Square: Equatable, Sendable {
        /// Share of the visible page the ring square takes.
        public let heightFraction: Double
        /// Largest disc diameter as a share of the square's side; nil = no cap.
        public let discShare: Double?
    }

    /// The ring square and disc cap for the Guide.
    /// - Parameters:
    ///   - walking: true while a route runs.
    ///   - textScale: `textScale(preferredDisc:)`.
    /// - Returns: walking — `walkingHeightFraction`, no cap, at every text size (unchanged from UI v3).
    ///   Idle — `idleHeightFraction` and `idleDiscShare` at the default size, both multiplied by
    ///   `textScale` at larger sizes, capped at `idleHeightFractionCeiling` and a share of 1, so the
    ///   idle disc grows with Dynamic Type as it did before task 4 (about 200 pt at AX sizes) and
    ///   stays inside its square. Pinned by `theDefaultTextSizeKeepsTheTask4IdleSquareAndTheWalkingSquareNeverChanges`,
    ///   `anAccessibilityTextSizeIsNotClampedToTheDefaultSizeCap`, `theIdleDiscNeverShrinksAsTheTextSizeGrows`.
    public static func square(walking: Bool, textScale: Double) -> Square {
        if walking { return Square(heightFraction: walkingHeightFraction, discShare: nil) }
        let s = textScale.isFinite ? max(1, textScale) : 1
        return Square(heightFraction: min(idleHeightFractionCeiling, idleHeightFraction * s),
                      discShare: min(1, idleDiscShare * s))
    }
}
