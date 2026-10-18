//
//  WaymarkMicLayoutTests.swift
//  CaneKitLogicTests
//
//  Judge demo task 4: pins `WaymarkMicLayout`, the Guide microphone's display geometry. The idle
//  ring square shrank (0.30 → 0.18 of the page) so the Where am I tile clears the tab dock on a
//  Pro Max; the idle disc is capped to a share of that square so the contour rings stay visible
//  around it. No cap (the walking layout) keeps the preferred diameter exactly.
//  Source pinned: `ios/Logic/Sources/CaneKitLogic/Waymark/WaymarkMicLayout.swift`.
//

import Foundation
import Testing
@testable import CaneKitLogic

@Test func theIdleFractionIsBelowTheOldOneAndTheWalkingOneIsUnchanged() {
    #expect(WaymarkMicLayout.idleHeightFraction == 0.18)
    #expect(WaymarkMicLayout.walkingHeightFraction == 0.26)
    #expect(WaymarkMicLayout.idleDiscShare == 0.62)
}

@Test func withoutACapTheDiscKeepsItsPreferredSize() {
    #expect(WaymarkMicLayout.discDiameter(preferred: 116, side: 140, maxShare: nil) == 116)
    #expect(WaymarkMicLayout.discDiameter(preferred: 116, side: 0, maxShare: nil) == 116)
}

@Test func aCappedDiscLeavesRoomForTheRings() {
    // A Pro Max idle square of ~140 pt: 0.62 × 140 = 86.8 pt, so ~26 pt of rings each side.
    let d = WaymarkMicLayout.discDiameter(preferred: 116, side: 140, maxShare: 0.62)
    #expect(abs(d - 86.8) < 0.001)
    // A square big enough for the preferred disc does not grow it.
    #expect(WaymarkMicLayout.discDiameter(preferred: 116, side: 300, maxShare: 0.62) == 116)
}

@Test func anUnmeasuredSquareKeepsThePreferredDisc() {
    // Before the first layout pass the side is 0; the disc must not collapse to nothing.
    #expect(WaymarkMicLayout.discDiameter(preferred: 116, side: 0, maxShare: 0.62) == 116)
    #expect(WaymarkMicLayout.discDiameter(preferred: 116, side: -5, maxShare: 0.62) == 116)
}

// Review fix (judge demo task 4, finding 1): the idle cap must grow with Dynamic Type, or a
// low-vision walker at an accessibility text size gets a smaller microphone than before task 4.

@Test func theTextScaleIsThePreferredDiscOverTheDefaultAndNeverBelowOne() {
    #expect(WaymarkMicLayout.defaultDiscDiameter == 116)
    #expect(WaymarkMicLayout.textScale(preferredDisc: 116) == 1)
    #expect(abs(WaymarkMicLayout.textScale(preferredDisc: 200) - 200.0 / 116.0) < 1e-9)
    // Smaller text sizes keep the default layout; a bad measurement is treated as the default.
    #expect(WaymarkMicLayout.textScale(preferredDisc: 90) == 1)
    #expect(WaymarkMicLayout.textScale(preferredDisc: 0) == 1)
    #expect(WaymarkMicLayout.textScale(preferredDisc: .nan) == 1)
    #expect(WaymarkMicLayout.textScale(preferredDisc: .infinity) == 1)
}

@Test func theDefaultTextSizeKeepsTheTask4IdleSquareAndTheWalkingSquareNeverChanges() {
    let idle = WaymarkMicLayout.square(walking: false, textScale: 1)
    #expect(idle.heightFraction == WaymarkMicLayout.idleHeightFraction)
    #expect(idle.discShare == WaymarkMicLayout.idleDiscShare)
    // Below the default size the idle square does not shrink further.
    #expect(WaymarkMicLayout.square(walking: false, textScale: 0.8) == idle)
    for s in [0.8, 1.0, 1.4, 200.0 / 116.0, 3.0] {
        let walking = WaymarkMicLayout.square(walking: true, textScale: s)
        #expect(walking.heightFraction == WaymarkMicLayout.walkingHeightFraction)
        #expect(walking.discShare == nil)
    }
}

@Test func anAccessibilityTextSizeIsNotClampedToTheDefaultSizeCap() {
    // ~200 pt preferred disc at an AX size (116 pt at the default). Before task 4 the idle disc drew
    // at the full 200 pt; it must again, not at the ~87 pt default-size cap.
    let preferred = 200.0
    let s = WaymarkMicLayout.textScale(preferredDisc: preferred)
    let idle = WaymarkMicLayout.square(walking: false, textScale: s)
    // The square grows back to at most the UI v3 idle share (0.30), never beyond it.
    #expect(idle.heightFraction == WaymarkMicLayout.idleHeightFractionCeiling)
    #expect(WaymarkMicLayout.idleHeightFractionCeiling == 0.30)
    #expect(idle.discShare == 1)
    for pageHeight in [700.0, 760.0, 870.0] {          // visible Guide heights, small phone … Pro Max
        let side = pageHeight * idle.heightFraction
        let d = WaymarkMicLayout.discDiameter(preferred: preferred, side: side, maxShare: idle.discShare)
        #expect(d == preferred, "page \(pageHeight)")
        #expect(d <= side, "the disc stays inside its square")
    }
}

@Test func theIdleDiscNeverShrinksAsTheTextSizeGrows() {
    let pageHeight = 870.0
    var last = 0.0
    for preferred in stride(from: 116.0, through: 260.0, by: 4) {
        let idle = WaymarkMicLayout.square(walking: false,
                                           textScale: WaymarkMicLayout.textScale(preferredDisc: preferred))
        let d = WaymarkMicLayout.discDiameter(preferred: preferred, side: pageHeight * idle.heightFraction,
                                              maxShare: idle.discShare)
        #expect(d >= last, "preferred \(preferred)")
        last = d
    }
}
