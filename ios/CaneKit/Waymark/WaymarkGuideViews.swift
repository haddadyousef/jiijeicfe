//
//  WaymarkGuideViews.swift
//  CaneKit
//
//  Waymark judge demo, task 1: sidewalk memory on the Guide page.
//    · `WaymarkGuideChip` — a small chip on the Guide ("Sidewalk memory off · Turn on" /
//      "Sidewalk memory on · 3,405 reports"). It opens `WaymarkSheet`, which holds the existing
//      Sidewalk memory card (`WaymarkCard`: the same switch, binding and spotter buttons). The
//      default stays OFF (`AppModel.waymarkEnabled`); the chip changes nothing by itself.
//    · `WaymarkAheadCard` — while walking with sidewalk memory on, one compact card under Stop
//      route: the nearest report ahead in the same order the spoken line uses
//      (`WaymarkSession.Step.nearest`), with its distance and belief ("Reported obstacle · 40 m ·
//      72 % likely"). Placed under the control deck so Repeat / Next / Recenter / Stop never move.
//    · `WaymarkSheet` — the Sidewalk memory card in a sheet with Done.
//  Every word comes from `WaymarkGlance` (CaneKitLogic, tested); the views only read `AppModel`.
//  Nothing here speaks through the speech queue. Owner / caller: `GuideCard`.
//

import SwiftUI
import CaneKitLogic

/// The Guide's sidewalk memory chip: off → a way to turn it on; on → how many reports are loaded.
struct WaymarkGuideChip: View {
    /// Reads `waymarkEnabled` and `waymark.state`.
    @Environment(AppModel.self) private var model
    /// Opens `WaymarkSheet`.
    let open: () -> Void

    /// A tappable `CKChip`; a blue dot only while on and loaded (the words always say it). The
    /// capsule is 32 pt; the hit area is padded to 44 pt (review 5).
    var body: some View {
        let words = WaymarkGlance.chip(enabled: model.waymarkEnabled, loadedLabels: loaded, failed: failed)
        Button(action: open) {
            CKChip(text: words, systemImage: "signpost.right.and.left.fill",
                   dot: model.waymarkEnabled && loaded != nil ? CKColor.trusted : nil)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(words.replacingOccurrences(of: " · ", with: ". "))
        .accessibilityHint(model.waymarkEnabled ? "Opens Sidewalk memory: reports, map and spotter buttons"
                                                : "Opens Sidewalk memory, where you can turn it on")
    }

    /// Label count once the bundle has loaded.
    private var loaded: Int? {
        if case .loaded(let n) = model.waymark.state { return n }
        return nil
    }

    /// The bundle failed to load (review 6: never "loading" forever).
    private var failed: Bool {
        if case .failed = model.waymark.state { return true }
        return false
    }
}

/// While walking with sidewalk memory on: the nearest report ahead, or why there is none.
struct WaymarkAheadCard: View {
    /// Reads `waymark.nearest` and `waymark.state`.
    @Environment(AppModel.self) private var model
    /// Opens `WaymarkSheet`.
    let open: () -> Void

    /// One button: badge, heading, the line; a chevron says it opens more. Re-rendered every 2 s so
    /// a report from a fix older than `NavigationHealth.maxFixAge` turns into "Waiting for a fresh
    /// GPS fix" even when fixes stop arriving (review 2).
    var body: some View {
        // The timeline only re-renders; the clock is read at render time. `timeline.date` is the
        // scheduled entry, earlier than a fix that just arrived, and `isFresh` rejects a fix from the
        // "future" — the card said "Waiting for a fresh GPS fix" while walking (tour, 20:30).
        TimelineView(.periodic(from: .now, by: 2)) { _ in
            card(now: Date())
        }
    }

    /// The card at `now`.
    private func card(now: Date) -> some View {
        let shown = fresh(now: now) ? model.waymark.nearest : nil
        let title = title(shown, now: now)
        let facts = shown.map { WaymarkGlance.aheadFacts(alongM: $0.alongM, p: $0.p) }.flatMap { $0.isEmpty ? nil : $0 }
        let spoken = shown.map { WaymarkGlance.aheadSpoken(type: $0.type, alongM: $0.alongM, p: $0.p) } ?? title + "."
        return Button(action: open) {
            HStack(alignment: .center, spacing: CKSpacing.md) {
                // Task 2: a report shows its map pin (band colour + shape, type glyph), so the card
                // and the map of reports read the same; otherwise the feature's badge.
                if let shown {
                    WaymarkPinMark(band: WaymarkConfidenceBand(p: shown.p), type: shown.type, size: 32)
                        .padding(-4)
                        .accessibilityHidden(true)
                } else {
                    CKIconBadge(systemImage: "signpost.right.and.left.fill", tinted: true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("SIDEWALK MEMORY")
                        .font(CKFont.pill).kerning(0.6)
                        .foregroundStyle(CKColor.textSecondary)
                    Text(title)
                        .font(CKFont.body.weight(.semibold))
                        .foregroundStyle(CKColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let facts {
                        Text(facts)
                            .font(CKFont.secondary.weight(.semibold))
                            .foregroundStyle(CKColor.textSecondary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(CKColor.textSecondary)
            }
            .padding(.horizontal, CKSpacing.lg)
            .padding(.vertical, CKSpacing.md)
            .frame(maxWidth: .infinity, minHeight: CKMetrics.touchTarget, alignment: .leading)
            .background(CKColor.surface, in: RoundedRectangle(cornerRadius: CKRadius.button, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: CKRadius.button, style: .continuous)
                        .strokeBorder(CKColor.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sidewalk memory. \(spoken)")
        .accessibilityHint("Opens Sidewalk memory: reports, map and spotter buttons")
        .accessibilityAddTraits([.isButton, .updatesFrequently])
    }

    /// The fix behind `nearest` is fresh (`NavigationHealth.isFresh`, the base app's tested rule).
    private func fresh(now: Date) -> Bool {
        guard let t = model.waymark.nearestFixTimestamp else { return false }
        return NavigationHealth.isFresh(timestamp: t, now: now.timeIntervalSinceReferenceDate)
    }

    /// The first line: the report ("Reported obstacle") or why there is none.
    private func title(_ shown: WaymarkSession.Nearest?, now: Date) -> String {
        switch model.waymark.state {
        case .idle, .loading: return WaymarkGlance.loadingLine
        case .failed: return WaymarkGlance.failedLine
        case .loaded:
            if let shown { return WaymarkGlance.reported(shown.type) }
            return fresh(now: now) ? WaymarkGlance.noneAhead : WaymarkGlance.waitingForGPS
        }
    }
}

/// The Sidewalk memory card (`WaymarkCard`) in a sheet, opened from the Guide.
struct WaymarkSheet: View {
    /// Closes the sheet.
    @Environment(\.dismiss) private var dismiss

    /// The existing card on the page ground, with Done.
    var body: some View {
        NavigationStack {
            pageScroll { WaymarkCard() }
                .background(CKColor.background)
                .navigationTitle("Sidewalk memory")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }.fontWeight(.bold)
                    }
                }
        }
    }
}
