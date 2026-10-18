//
//  StoredBool.swift
//  CaneKitLogic
//
//  waymark: (judge demo task 3 review M1) how a stored Bool setting is read back from
//  `UserDefaults.object(forKey:)`. A value written by the app is a Bool; a launch argument
//  (`-waymarkEnabled NO`, which the UI tests use to force a feature off for one launch) reaches the
//  argument domain as the String "NO" / "YES", which `as? Bool` read as "never written", so the
//  mask silently did nothing. This accepts both. Anything else is "unset" (the caller's default).
//  Caller: `Settings.bool` (AppModel.swift). Portability (plan 1.4): Foundation only. Pure.
//  Tests: `WaymarkReviewFixTests.swift`.
//

import Foundation

/// Reads a stored Bool setting.
public enum StoredBool {
    /// `value` as a Bool: a Bool itself, or the strings yes / true / 1 and no / false / 0 (any case);
    /// nil for nil or anything else.
    public static func parse(_ value: Any?) -> Bool? {
        if let s = value as? String {
            switch s.lowercased() {
            case "yes", "true", "1": return true
            case "no", "false", "0": return false
            default: return nil
            }
        }
        return value as? Bool
    }
}
