//
//  WaymarkCard.swift
//  CaneKit
//
//  Waymark A2 / E1: the "Sidewalk memory" card on the Details page. One place for the feature:
//    · the switch (moved here from the Hazards card; same label "Sidewalk memory", same binding);
//    · a status line: off / loading / N reports loaded / the last line spoken / a load failure;
//    · while on and loaded, the spotter's two buttons, "Confirm" and "Not there" (design doc §9.3):
//      they apply to the nearest report within 15 m, ahead or just passed, and are held for 10 s
//      with an Undo in a toast that names the report and its distance, so a mis-tap can be taken
//      back; a line says why a tap did nothing ("No sidewalk report within 15 m.");
//    · how many checks were saved and the last one ("Confirmed: obstacle, 3 m");
//    · judge demo: "Map of reports" opens `WaymarkMapView` (pins coloured and shaped by confidence);
//    · judge demo task 3: once an outcome is committed, a "learning" row under the spotter buttons —
//      the label's pin (band of p after) + "Reported obstacle" + "Not there · 50 % → 43 % · spotter"
//      (`WaymarkGlance.learningLine`; VoiceOver hears `learningSpoken`) — and, once a belief is
//      saved, a caption naming the file it is kept in ("Saved on this phone:
//      Documents/waymark/beliefs.json"). A "Couldn't check" pass never replaces a decisive row
//      (`WaymarkLearning.kept`); the row's pin dot is the map's "checked" (a stored belief).
//  Everything is words; the buttons are `CKBigButton` tiles. CaneKitWaymarkTour queries the switch,
//  "Map of reports", "Not there", the toast text and the learning row (identifier "waymark-learning").
//  Owner / caller: `SensePage` in ContentView.swift (after "What's ahead"). Reads
//  `model.waymarkEnabled` and `model.waymark` (`WaymarkEngine`).
//

import SwiftUI
import UIKit
import CaneKitLogic

/// The Sidewalk memory card. Reads and binds `AppModel`; owns no state.
struct WaymarkCard: View {
    /// Source of the switch binding and every line shown here.
    @Environment(AppModel.self) private var model
    /// Judge demo task 2: the map of reports (`WaymarkMapView`) in a sheet.
    @State private var showMap = false

    /// Switch, status, spotter buttons + toast, evidence line.
    var body: some View {
        @Bindable var model = model
        CKCard(title: "Sidewalk memory", systemImage: "signpost.right.and.left.fill",
               caption: "Warns about obstacles and missing curb ramps other people reported, before you reach them.") {
            CKToggleRow(title: "Sidewalk memory",
                        subtitle: "Reports from Project Sidewalk, spoken ahead of you",
                        isOn: $model.waymarkEnabled,
                        hint: "Experimental. Speaks problems other people reported on the sidewalk ahead, such as obstacles or missing curb ramps. Never talks over obstacle warnings.")
            caption(status)
            if model.waymarkEnabled, case .loaded = model.waymark.state {
                // Judge demo task 2: every report along the route, coloured and shaped by confidence.
                CKBigButton(title: "Map of reports", subtitle: "Coloured and shaped by confidence",
                            systemImage: "map.fill", role: .secondary,
                            hint: "Opens a map of the sidewalk reports along the route. Tap a pin for its details.") {
                    showMap = true
                }
                CKRowDivider()
                Text("Walking with a helper? Tap when you pass a report:")
                    .font(CKFont.secondary)
                    .foregroundStyle(CKColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: CKSpacing.sm) {
                    CKBigButton(title: "Confirm", subtitle: "It's there", systemImage: "checkmark",
                                layout: .tile,
                                hint: "Marks the nearest sidewalk report within 15 meters as really there. You can undo for 10 seconds.") {
                        model.waymark.spotter(.confirmed)
                    }
                    CKBigButton(title: "Not there", subtitle: "It's gone", systemImage: "xmark",
                                role: .secondary, layout: .tile,
                                hint: "Marks the nearest sidewalk report within 15 meters as not there. You can undo for 10 seconds.") {
                        model.waymark.spotter(.contradicted)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                // `.id`: a replacing tap is a new view, so it is announced again (review M6).
                if let tap = model.waymark.pendingTap { toast(tap).id(tap.token) }
                if let message = model.waymark.spotterMessage {
                    CKErrorText(text: message, systemImage: "exclamationmark.circle")
                }
                if let learning = model.waymark.lastLearning { learningRow(learning) }   // task 3
                if model.waymark.evidenceCount > 0 || model.waymark.lastEvidence != nil {
                    caption("\(model.waymark.evidenceCount) \(model.waymark.evidenceCount == 1 ? "check" : "checks") saved this session"
                            + (model.waymark.lastEvidence.map { ". Last: \($0)." } ?? "."))
                }
                // Review: only once a belief is saved (none before the first decisive outcome).
                if let stored = WaymarkGlance.storedCaption(folder: model.waymark.storeFolderName,
                                                            savedLabels: model.waymark.savedLabelCount) {
                    caption(stored)
                }
            }
        }
        .sheet(isPresented: $showMap) { WaymarkMapView() }
    }

    /// The undo toast: what the tap applies to, and an Undo button. One VoiceOver element plus the
    /// button; announced when it appears.
    private func toast(_ tap: WaymarkEngine.SpotterTap) -> some View {
        let words = "\(tap.outcome == .confirmed ? "Confirmed" : "Not there"): \(tap.typeWord), \(Int(tap.distM.rounded())) m"
        return HStack(spacing: CKSpacing.md) {
            Image(systemName: tap.outcome == .confirmed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.title3.weight(.bold))
                .foregroundStyle(CKColor.accent)
                .accessibilityHidden(true)
            Text(words)
                .font(CKFont.body.weight(.semibold))
                .foregroundStyle(CKColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("\(words). Undo within 10 seconds.")
            Spacer(minLength: 0)
            // The frame is inside the label so the styled background and the hit area are 60 pt (review M6).
            Button { model.waymark.undoSpotter() } label: {
                Text("Undo")
                    .font(CKFont.body.weight(.bold))
                    .frame(minWidth: 76, minHeight: CKMetrics.touchTarget)
            }
                .buttonStyle(CKBigButtonStyle(role: .secondary))
                .accessibilityLabel("Undo")
                .accessibilityHint("Takes back the last tap")
        }
        .padding(CKSpacing.md)
        .background(CKColor.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: CKRadius.tile, style: .continuous))
        .onAppear { UIAccessibility.post(notification: .announcement, argument: words) }
    }

    /// Task 3: what the last committed outcome did — the label's pin in its new band, the report and
    /// "Not there · 50 % → 43 % · spotter". One VoiceOver element saying it in words.
    private func learningRow(_ l: WaymarkLearning) -> some View {
        HStack(alignment: .center, spacing: CKSpacing.md) {
            // Review: the same "checked" as the map pin (a stored belief), not "this outcome changed it".
            WaymarkPinMark(band: WaymarkConfidenceBand(p: l.pAfter), type: l.type, size: 34,
                           checked: model.waymark.isChecked(l.labelID))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(WaymarkGlance.reported(l.type))
                    .font(CKFont.body.weight(.bold))
                    .foregroundStyle(CKColor.textPrimary)
                Text(WaymarkGlance.learningLine(l))
                    .font(CKFont.body.weight(.semibold))
                    .foregroundStyle(CKColor.textPrimary)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(CKSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CKColor.surfaceRaised, in: RoundedRectangle(cornerRadius: CKRadius.tile, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CKRadius.tile, style: .continuous)
                    .strokeBorder(CKColor.border, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(WaymarkGlance.reported(l.type)). \(WaymarkGlance.learningSpoken(l))")
        .accessibilityIdentifier("waymark-learning")
    }

    /// The status line under the switch.
    private var status: String {
        guard model.waymarkEnabled else { return "Off." }
        switch model.waymark.state {
        case .idle, .loading: return "Loading sidewalk reports…"
        case .failed: return "Sidewalk reports could not be loaded. Waymark stays quiet."
        case .loaded(let n):
            if let line = model.waymark.lastLine { return "\(n) reports loaded. Last said: \(line)" }
            return "\(n) sidewalk reports loaded."
        }
    }

    /// A secondary-text line whose label is its content.
    private func caption(_ text: String) -> some View {
        Text(text).font(CKFont.secondary).foregroundStyle(CKColor.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
