//
//  WaymarkProfileNameTests.swift
//  CaneKitLogicTests
//
//  Judge demo task 4: pins `WaymarkProfileName`, the rule for the name the Profile header shows. A
//  stored name that is blank or still the first-run default ("Not set", `CKMedicalProfile.standardDefault.name`,
//  which EmergencyContactSeed's tests also rely on) shows as "Waymark walker"; anything the walker
//  typed shows as typed (trimmed). No person's name or photo ships in the app.
//  Source pinned: `ios/Logic/Sources/CaneKitLogic/Waymark/WaymarkProfileName.swift`.
//

import Foundation
import Testing
@testable import CaneKitLogic

/// The app passes `CKMedicalProfile.standardDefault.name`; the test pins the shipped value.
private let defaultName = "Not set"

@Test func theFirstRunDefaultShowsAsTheNeutralWalker() {
    #expect(WaymarkProfileName.isUnset("Not set", defaultName: defaultName))
    #expect(WaymarkProfileName.display("Not set", defaultName: defaultName) == "Waymark walker")
    #expect(WaymarkProfileName.placeholder == "Waymark walker")
}

@Test func aBlankOrPaddedDefaultNameIsUnset() {
    for name in ["", "   ", "\n", "  Not set  ", "\tNot set\n"] {
        #expect(WaymarkProfileName.isUnset(name, defaultName: defaultName), "\(name.debugDescription)")
        #expect(WaymarkProfileName.display(name, defaultName: defaultName) == "Waymark walker")
    }
}

@Test func aTypedNameShowsAsTypedTrimmed() {
    #expect(!WaymarkProfileName.isUnset("Sam Rivera", defaultName: defaultName))
    #expect(WaymarkProfileName.display("Sam Rivera", defaultName: defaultName) == "Sam Rivera")
    #expect(WaymarkProfileName.display("  Sam  ", defaultName: defaultName) == "Sam")
}

@Test func onlyTheExactDefaultCountsAsUnset() {
    // Case matters: the sentinel is the exact shipped string, not any "not set" a walker might type.
    #expect(!WaymarkProfileName.isUnset("not set", defaultName: defaultName))
    #expect(!WaymarkProfileName.isUnset("Not settled", defaultName: defaultName))
    #expect(WaymarkProfileName.display("not set", defaultName: defaultName) == "not set")
}

// Review fix (judge demo task 4, finding 6): "Announce Medical ID" must not speak the raw sentinel
// as if it were a name, and must not tell a responder the neutral header name either.

@Test func theSpokenNameSaysNameNotSetWhileUnset() {
    for name in ["Not set", "", "  ", "  Not set\n"] {
        #expect(WaymarkProfileName.spoken(name, defaultName: defaultName) == "Name not set",
                "\(name.debugDescription)")
        #expect(WaymarkProfileName.spoken(name, defaultName: defaultName) != WaymarkProfileName.placeholder)
    }
    #expect(WaymarkProfileName.spoken("  Sam Rivera ", defaultName: defaultName) == "Sam Rivera")
    #expect(WaymarkProfileName.spoken("not set", defaultName: defaultName) == "not set")
}
