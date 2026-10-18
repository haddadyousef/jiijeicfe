//
//  WaymarkProfileName.swift
//  CaneKitLogic
//
//  Judge demo task 4: the name the Profile header shows. The app ships no person's name or photo;
//  until the walker types a name, the stored value is the first-run default ("Not set",
//  `CKMedicalProfile.standardDefault.name`) and the header says "Waymark walker" instead. The stored
//  value is never rewritten here — "Not set" is also EmergencyContactSeed's sentinel.
//
//  Pure, Foundation-only. The default name is passed in (it is defined on the app's
//  `CKMedicalProfile`, which this package cannot see), so there is one copy of the sentinel.
//  Caller: `ProfilePage.medicalIDCard` (header name and the line under it).
//  Tests: `WaymarkProfileNameTests.swift`.
//

import Foundation

/// Display rule for the Profile header name. Namespace only.
public enum WaymarkProfileName {
    /// The neutral name shown while no name is set.
    public static let placeholder = "Waymark walker"

    /// True when `name`, trimmed of whitespace and newlines, is empty or exactly `defaultName`.
    /// - Parameters:
    ///   - name: the stored profile name.
    ///   - defaultName: the first-run default (`CKMedicalProfile.standardDefault.name`, "Not set").
    /// - Returns: whether the header should show `placeholder`. Case-sensitive: only the shipped
    ///   sentinel counts. Pinned by `aBlankOrPaddedDefaultNameIsUnset`, `onlyTheExactDefaultCountsAsUnset`.
    public static func isUnset(_ name: String, defaultName: String) -> Bool {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty || n == defaultName
    }

    /// The header name: `placeholder` while unset, else the stored name trimmed.
    /// - Parameters: as `isUnset(_:defaultName:)`.
    /// - Returns: the text to show. Pinned by `theFirstRunDefaultShowsAsTheNeutralWalker`,
    ///   `aTypedNameShowsAsTypedTrimmed`.
    public static func display(_ name: String, defaultName: String) -> String {
        isUnset(name, defaultName: defaultName) ? placeholder : name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// What "Announce Medical ID" says in place of the name while it is unset.
    public static let spokenUnset = "Name not set"

    /// The name "Announce Medical ID" speaks (review fix): `spokenUnset` while unset — never the raw
    /// "Not set" sentinel, which a responder would hear as a name, and never `placeholder`, which is
    /// not the walker's name — else the stored name trimmed.
    /// - Parameters: as `isUnset(_:defaultName:)`.
    /// - Returns: the name part of the spoken summary. Pinned by `theSpokenNameSaysNameNotSetWhileUnset`.
    public static func spoken(_ name: String, defaultName: String) -> String {
        isUnset(name, defaultName: defaultName) ? spokenUnset : name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
