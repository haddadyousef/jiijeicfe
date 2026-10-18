//
//  WaymarkStoreFolder.swift
//  CaneKitLogic
//
//  Waymark judge demo, task 3: which `Documents/` sub-folder holds `beliefs.json` and
//  `evidence.jsonl`. Always `waymark` — except under UI tests (`CANEKIT_UITEST=1`), where
//  `WAYMARK_STORE_SUBDIR` names a throwaway folder so a tour never touches the real beliefs. The
//  name must be 1…64 ASCII letters, digits, "-" or "_" (no "/", no dots, so it cannot leave
//  Documents); anything else is ignored and the standard folder is used. Under UI tests, folders
//  left by earlier runs ("wm-ui-…", formerly "waymark-uitest-…") are listed for removal
//  (`staleTestFolders`); the real `waymark` folder never is.
//  Portability (plan 1.4): Foundation only. Pure. Tests: `WaymarkLearningShownTests.swift`.
//

import Foundation

/// The Waymark store folder name.
public enum WaymarkStoreFolder {
    /// The shipped folder: `Documents/waymark/`.
    public static let standard = "waymark"
    /// Longest accepted test folder name.
    public static let maxLength = 64

    /// `raw` when it is a safe folder name (1…`maxLength` of A–Z a–z 0–9 - _), else nil.
    public static func sanitized(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty, raw.unicodeScalars.count <= maxLength else { return nil }
        let ok = raw.unicodeScalars.allSatisfy { s in
            switch s.value {
            case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x2D, 0x5F: true    // 0-9 A-Z a-z - _
            default: false
            }
        }
        return ok ? raw : nil
    }

    /// Prefix of the UI tours' folders ("wm-ui-" + 8 hex characters, short enough for a caption).
    public static let testPrefix = "wm-ui-"
    /// The prefix used before the review (long UUID names); still cleaned up.
    static let legacyTestPrefix = "waymark-uitest-"

    /// Of the `Documents/` entries `names`, the UI-test folders left by earlier runs, to delete at
    /// launch (review L6: they piled up). Only under UI tests; never `active`, never `standard`,
    /// only safe names with a test prefix.
    public static func staleTestFolders(_ names: [String], active: String, uiTest: Bool) -> [String] {
        guard uiTest else { return [] }
        return names.filter { n in
            n != active && n != standard && sanitized(n) != nil
                && (n.hasPrefix(testPrefix) || n.hasPrefix(legacyTestPrefix))
        }
    }

    /// The folder to use.
    /// - Parameters:
    ///   - subdir: `WAYMARK_STORE_SUBDIR`, if set.
    ///   - uiTest: `CANEKIT_UITEST == "1"`; without it `subdir` is ignored.
    public static func name(subdir: String?, uiTest: Bool) -> String {
        guard uiTest, let safe = sanitized(subdir) else { return standard }
        return safe
    }
}
