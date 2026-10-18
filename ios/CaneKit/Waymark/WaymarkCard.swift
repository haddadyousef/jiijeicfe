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
//    · how many checks were saved and the last one ("Confirmed: obstacle, 3 m").
//  Everything is words; the buttons are `CKBigButton` tiles. No XCUITest queries this card yet.
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

    /// Switch, status, spotter buttons + toast, evidence line.
    var body: some View {
        @Bindable var model = model
        CKCard(title: "Sidewalk memory", systemImage: "map",
               caption: "Warns about obstacles and missing curb ramps other people reported, before you reach them.") {
            CKToggleRow(title: "Sidewalk memory",
                        subtitle: "Reports from Project Sidewalk, spoken ahead of you",
                        isOn: $model.waymarkEnabled,
                        hint: "Experimental. Speaks problems other people reported on the sidewalk ahead, such as obstacles or missing curb ramps. Never talks over obstacle warnings.")
            caption(status)
            if model.waymarkEnabled, case .loaded = model.waymark.state {
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
                if model.waymark.evidenceCount > 0 || model.waymark.lastEvidence != nil {
                    caption("\(model.waymark.evidenceCount) checks saved this session"
                            + (model.waymark.lastEvidence.map { ". Last: \($0)." } ?? "."))
                }
            }
        }
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
