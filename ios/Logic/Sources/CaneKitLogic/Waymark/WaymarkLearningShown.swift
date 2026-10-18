//
//  WaymarkLearningShown.swift
//  CaneKitLogic
//
//  Waymark judge demo, task 3: how a recorded outcome is shown and logged in the app.
//    · `WaymarkLearning.tripLogFields` — `p_before` / `p_after` rounded to 3 dp for the
//      `waymark_evidence` TRIP-LOG record only. Never for the `evidence.jsonl` line: schema
//      `waymark.evidence.v1` has `additionalProperties: false`. Non-finite numbers are left out
//      (JSONSerialization throws on NaN).
//    · `WaymarkSession.isChecked` — a stored belief exists, i.e. field evidence moved it on this
//      phone (unverifiable never stores one); restored across launches from `beliefs.json`.
//    · The map pin's words: its VoiceOver label (", checked on this phone"), its detail line (this
//      launch's learning, else "Checked on this phone before") and its icon by outcome, and the
//      card's storage caption (only once something is saved).
//    · `WaymarkLearning.kept` — an unverifiable pass never replaces a decisive learning (review).
//  Portability (plan 1.4): Foundation only. Pure. Tests: `WaymarkLearningShownTests.swift`.
//

import Foundation

extension WaymarkLearning {
    /// p to 3 decimals, half away from zero.
    public static func round3(_ p: Double) -> Double { (p * 1000).rounded() / 1000 }

    /// `["p_before": …, "p_after": …]` for the `waymark_evidence` trip-log record; a non-finite
    /// value is omitted.
    public var tripLogFields: [String: Double] {
        var out: [String: Double] = [:]
        if pBefore.isFinite { out["p_before"] = Self.round3(pBefore) }
        if pAfter.isFinite { out["p_after"] = Self.round3(pAfter) }
        return out
    }
}

extension WaymarkSession {
    /// True when field evidence (a confirmed or contradicted outcome) has been stored for this
    /// label on this phone, this launch or restored from an earlier one.
    public func isChecked(_ id: String) -> Bool { beliefs[id] != nil }
}

extension WaymarkGlance {
    /// The map details' line for a pin checked in an earlier launch.
    public static let checkedBefore = "Checked on this phone before"

    /// A map pin's VoiceOver label: "Reported obstacle, 43 percent likely, uncertain", plus
    /// ", checked on this phone" when `checked`.
    public static func pinSpoken(type: WaymarkLabelType, p: Double, checked: Bool) -> String {
        "\(reported(type)), \(confidenceSpoken(p))" + (checked ? ", checked on this phone" : "")
    }

    /// The tapped pin's learning line: this launch's `learningLine`, else `checkedBefore` when
    /// checked, else nil (nothing learned on this phone).
    public static func pinLearningDetail(learning: WaymarkLearning?, checked: Bool) -> String? {
        if let learning { return learningLine(learning) }
        return checked ? checkedBefore : nil
    }

    /// "Saved on this phone: Documents/waymark/beliefs.json" for the store folder in use, once
    /// `savedLabels` (stored beliefs, this launch or restored) is above zero; nil before anything
    /// was saved (review L4: the caption said "Saved" before any check).
    public static func storedCaption(folder: String, savedLabels: Int) -> String? {
        savedLabels > 0 ? "Saved on this phone: Documents/\(folder)/beliefs.json" : nil
    }

    /// VoiceOver for `pinLearningDetail`: this launch's `learningSpoken`, else "Checked on this phone
    /// before." when checked, else nil. Used by the map details and the Guide's ahead card (review L2).
    public static func learningDetailSpoken(learning: WaymarkLearning?, checked: Bool) -> String? {
        if let learning { return learningSpoken(learning) }
        return checked ? checkedBefore + "." : nil
    }

    /// SF Symbol beside a learning line, by outcome (review L5: a check seal beside "Not there"
    /// read as confirmation): confirmed → checkmark seal, not there → xmark seal, couldn't check →
    /// question mark, nil (checked in an earlier launch) → clock.
    public static func learningSymbol(_ learning: WaymarkLearning?) -> String {
        switch learning?.outcome {
        case .confirmed: "checkmark.seal.fill"
        case .contradicted: "xmark.seal.fill"
        case .unverifiable: "questionmark.circle"
        case nil: "clock.arrow.circlepath"
        }
    }
}

extension WaymarkLearning {
    /// Which learning to keep when `new` arrives over `previous` (per label, or the card's last):
    /// `new`, unless it is unverifiable and `previous` was decisive — a "Couldn't check" pass changes
    /// no belief, so it must not hide the change that did happen (review L3).
    public static func kept(_ new: WaymarkLearning, over previous: WaymarkLearning?) -> WaymarkLearning {
        if !new.changed, let previous, previous.changed { return previous }
        return new
    }
}
