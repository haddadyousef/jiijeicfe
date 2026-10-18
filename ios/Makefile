# CaneKit — CLI build / install / launch. Run from ios/.
#
#   make gen                 regenerate CaneKit.xcodeproj (scripts/gen.sh)
#   make test                pure-logic unit tests (Logic/, no device needed)
#   make build               device build with automatic signing
#   make install             install the built .app on the phone
#   make launch              launch it
#   make run                 gen + build + install + launch
#   make sim                 build for the iOS simulator (UI / nav logic only; no LiDAR, no haptics)
#   make uitest / tour       XCUITests / screenshot tour on the iPhone 17 Pro Max simulator
#   make e2e                 GPS-replay end-to-end scenarios through the real app (SCENARIO=clean …)
#   make devices             list connected devices (find DEVICE)
#   make sim17               create the iPhone 17 Pro Max (iOS 27) simulator once
#   make sim-grant           boot SIM and pre-grant location + motion (a prerequisite of the sim tests)
#   make uitest-streetview   "Where am I" XCUITest over Street View frames (needs the local JPEGs)
#   make island              Dynamic Island screenshots (CaneKitIslandTour) → build/shots
#   make audit               cue load of one walk from its trip log (LOG=path, or pulled off the phone)
#   make clean               delete build/, CaneKit.xcodeproj and Logic/.build (next build needs `make gen`)
#
# Owner: everyone; this is the only supported CLI entry point (AGENTS.md "Commands"). Commit gate
# (AGENTS.md hard rule 10): `make test` + `make sim` every commit; UI changes add `make uitest` +
# `make tour`; `make e2e` per "How we engineer" §4. Automated targets are silent: e2e launches with
# CANEKIT_MUTE=1 and XCUITests with CANEKIT_UITEST=1 (the app mutes itself).
# ⚠ Check each target's own exit status; never judge a run through `| tail` (Step 27 false green).
# ⚠ Do not run two simulator targets (uitest / tour / e2e) at once on the same SIM: a contended
# simulator starves the GPS replay and fails for reasons unrelated to the code (e2e.py fix_cadence).
#
# TEAM, DEVICE and BUNDLE_PREFIX come from local.mk (git-ignored; template: local.mk.example):
#   TEAM          = ABCDE12345                # the OU= value of the Apple Development certificate (below)
#   DEVICE        = 00008150-000A1B2C3D4E5F   # make devices
#   BUNDLE_PREFIX = com.yourname              # Waymark: unique per teammate → bundle id <prefix>.waymark
# `make gen` also copies TEAM and BUNDLE_PREFIX into Config/Local.xcconfig so Xcode itself signs the
# same way (scripts/gen.sh, Config/Waymark.xcconfig).
# TEAM: add the Apple ID in Xcode (Settings > Accounts), `make gen`, open CaneKit.xcodeproj once,
# CaneKit target > Signing & Capabilities > pick the Personal Team (creates the certificate). Then
# read the Team ID in Xcode > Settings > Accounts > team details, or run
#   security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject
# and take OU=. Not the 10 characters in parentheses of "Apple Development: Name (…)".

# Optional per-machine overrides (TEAM, DEVICE, and optionally SIM, SCHEME, CONFIG, SHOTS); the leading
# `-` makes a missing file silent, so `make test` / `make sim` work on a fresh clone.
-include local.mk
# A comment after the value in local.mk ("DEVICE = 0000…   # make devices") leaves trailing spaces
# in the variable, and xcodebuild then cannot find the phone. Strip them.
TEAM   := $(strip $(TEAM))
DEVICE := $(strip $(DEVICE))
BUNDLE_PREFIX := $(strip $(BUNDLE_PREFIX))
# Same placeholder as Config/Waymark.xcconfig, so the simulator targets work on a fresh clone.
ifeq ($(BUNDLE_PREFIX),)
BUNDLE_PREFIX := com.example.waymark-dev
endif

# No-ops once the := lines above have run (they define both, possibly empty); kept as documentation
# of the two variables. `make TEAM=… DEVICE=…` on the command line still overrides everything.
TEAM   ?=
DEVICE ?=
SCHEME ?= CaneKit
CONFIG ?= Debug
# Derived data lives in ios/build (git-ignored); e2e.py hard-codes the simulator product path under it.
DERIVED = build
# The DEVICE build product installed by `make install` (the simulator product is ...-iphonesimulator).
APP     = $(DERIVED)/Build/Products/$(CONFIG)-iphoneos/CaneKit.app
# The phone app's bundle id (Waymark: <BUNDLE_PREFIX>.waymark). Exported so scripts/e2e.py and
# scripts/cue_audit.py launch / pull the same app (they read WAYMARK_BUNDLE).
BUNDLE  = $(BUNDLE_PREFIX).waymark
export WAYMARK_BUNDLE := $(BUNDLE)
XCB     = xcodebuild -project CaneKit.xcodeproj -scheme $(SCHEME) -configuration $(CONFIG) -derivedDataPath $(DERIVED) \
          BUNDLE_ID_PREFIX=$(BUNDLE_PREFIX)

.PHONY: gen test build install launch run sim devices clean check-env uitest tour tour-waymark island sim17 sim-grant e2e e2e-waymark uitest-streetview audit

# Regenerate the Xcode project from project.yml (see scripts/gen.sh for WATCH=0 / PATCH_WATCH_EMBED).
gen:
	scripts/gen.sh

# CaneKitLogic Swift Testing suite; no simulator, no xcodebuild (safe beside a running app build).
test:
	scripts/test.sh

# Guard for the device targets: fail fast with a pointer to local.mk rather than an xcodebuild error.
check-env:
	@test -n "$(TEAM)"   || { echo "TEAM is empty — put TEAM=<10-char team id> in ios/local.mk"; exit 1; }
	@test -n "$(DEVICE)" || { echo "DEVICE is empty — run 'make devices' and put DEVICE=<id> in ios/local.mk"; exit 1; }
	@test "$(BUNDLE_PREFIX)" != "com.example.waymark-dev" || { echo "BUNDLE_PREFIX is unset — put BUNDLE_PREFIX=com.<yourname> in ios/local.mk"; exit 1; }

# Signed device build. -allowProvisioningUpdates / -allowProvisioningDeviceRegistration let a free
# personal team create profiles and register the phone; the team id comes only from local.mk, so
# project.yml never carries one.
build: check-env
	$(XCB) -destination "platform=iOS,id=$(DEVICE)" \
	  -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
	  DEVELOPMENT_TEAM=$(TEAM) CODE_SIGN_STYLE=Automatic build

# Install the last `make build` product on DEVICE (does not build first).
install: check-env
	xcrun devicectl device install app --device $(DEVICE) $(APP)

# Launch the installed app on DEVICE (the phone must be unlocked).
launch: check-env
	xcrun devicectl device process launch --device $(DEVICE) $(BUNDLE)

# The phone loop: regenerate, build, install, launch. ⚠ It regenerates the project every time
# (gen) — harmless for an unchanged project.yml, but it discards any hand edit to the pbxproj.
run: gen build install launch

# Unsigned simulator build for any simulator (generic destination). The compile gate for app code;
# no LiDAR, haptics or watch in the simulator. Prerequisite of `make e2e`.
sim:
	$(XCB) -destination "generic/platform=iOS Simulator" CODE_SIGNING_ALLOWED=NO build

# XCUITest run in the simulator (SIM = a booted or bootable simulator name/UDID).
# The demo phone is an iPhone 17 Pro Max on iOS 27; Xcode 27 does not create that device by
# default — `make sim17` creates it once.
SIM ?= iPhone 17 Pro Max
# Waymark (D-35, supersedes D-07): where the simulator's GPS is parked for sim-grant / uitest / tour /
# island. Default = the start of the Seattle demo route (The Ave and NE 42nd, waypoint 1 of
# Resources/route_ave_seattle.json, pinned by WaymarkRouteTests). `make uitest SIM_LAT=40.1140
# SIM_LON=-88.2249` reproduces the original UIUC location (Townsend Hall) for a like-for-like
# baseline. e2e.py parks the GPS itself at the start of the route it replays.
SIM_LAT ?= 47.658324
SIM_LON ?= -122.313219
# Pre-answer the permission prompts so no system alert races the first tap (fresh simulator / CI).
# ⚠ On a simulator that has never had the app installed the grant may not stick (G0, 15:30); the
# UI tests also answer the prompt themselves (`allowLocationPrompts()` in CaneKitUITests.swift).
sim-grant:
	@xcrun simctl boot "$(SIM)" 2>/dev/null || true
	@xcrun simctl bootstatus "$(SIM)" -b
	@xcrun simctl privacy "$(SIM)" grant location $(BUNDLE)
	@xcrun simctl privacy "$(SIM)" grant location-always $(BUNDLE) 2>/dev/null || true
	@xcrun simctl privacy "$(SIM)" grant motion $(BUNDLE)
	@xcrun simctl location "$(SIM)" set $(SIM_LAT),$(SIM_LON)

# Every XCUITest in CaneKitUITests (the Street View test skips itself without CANEKIT_FRAME_DIR).
# ⚠ Set a simulator location first (sim-grant does it: SIM_LAT / SIM_LON above) or the route
# tests fail for want of a GPS fix (AGENTS.md "Commands").
uitest: sim-grant
	$(XCB) -destination "platform=iOS Simulator,name=$(SIM)" CODE_SIGNING_ALLOWED=NO -only-testing:CaneKitUITests test

# "Where am I" on a real street scene: Street View frames stand in for the camera (FrameReplay).
STREETVIEW ?= scripts/streetview
# TEST_RUNNER_* must be in xcodebuild's *environment* (it strips the prefix and hands the rest to
# the test runner); written after the command it is only a build setting and never arrives.
uitest-streetview: sim-grant
	TEST_RUNNER_CANEKIT_FRAME_DIR=$(abspath $(STREETVIEW)) \
	  $(XCB) -destination "platform=iOS Simulator,name=$(SIM)" CODE_SIGNING_ALLOWED=NO \
	  -only-testing:CaneKitUITests/CaneKitUITests/testWhereAmIDescribesAStreetViewFrame test

# Screenshot tour of every screen state (CaneKitVisualTour); PNGs land in SHOTS.
SHOTS ?= $(DERIVED)/shots
tour: sim-grant
	mkdir -p $(SHOTS)
	TEST_RUNNER_CANEKIT_SHOTS=$(abspath $(SHOTS)) \
	  $(XCB) -destination "platform=iOS Simulator,name=$(SIM)" CODE_SIGNING_ALLOWED=NO \
	  -only-testing:CaneKitUITests/CaneKitVisualTour test

# Waymark judge demo: sidewalk memory screenshots (CaneKitWaymarkTour) on the default Ave route —
# Guide chip off / on, the sheet, the ahead card while walking. PNGs land in WM_SHOTS.
WM_SHOTS ?= $(DERIVED)/shots-waymark
tour-waymark: sim-grant
	mkdir -p $(WM_SHOTS)
	TEST_RUNNER_CANEKIT_SHOTS=$(abspath $(WM_SHOTS)) \
	  $(XCB) -destination "platform=iOS Simulator,name=$(SIM)" CODE_SIGNING_ALLOWED=NO \
	  -only-testing:CaneKitUITests/CaneKitWaymarkTour test

# Dynamic Island pictures (CaneKitIslandTour, Step 47): route start → background → compact island,
# long-press → expanded, a few seconds of simulated walk, then Stop and the island after it. PNGs
# land in SHOTS as NN-island-*.png. Same prerequisites as `make tour` (location set, sim-grant).
island: sim-grant
	mkdir -p $(SHOTS)
	TEST_RUNNER_CANEKIT_SHOTS=$(abspath $(SHOTS)) \
	  $(XCB) -destination "platform=iOS Simulator,name=$(SIM)" CODE_SIGNING_ALLOWED=NO \
	  -only-testing:CaneKitUITests/CaneKitIslandTour test

# End-to-end GPS replay through the real app (scripts/e2e.py): clean, missed_fence, gps_jitter,
# wrong_turn (SCENARIO=all). SCENARIO=streetview reruns clean with Street View frames as the
# camera (needs the local-only JPEGs). Asserts on the app's JSONL trip log; report + logs in
# build/e2e/. ~20 min for all. Always muted (CANEKIT_MUTE).
SCENARIO ?= all
e2e: sim sim-grant
	python3 scripts/e2e.py --sim "$(SIM)" --scenario $(SCENARIO)

# Waymark X-e2e (D-35 item 3): the Ave route with W's SYNTHETIC test priors, sidewalk memory on.
e2e-waymark: sim sim-grant
	python3 scripts/e2e.py --sim "$(SIM)" --scenario waymark_ave

# Cue load of one walk (scripts/cue_audit.py, Step 35): mounted or handheld, head band wall vs
# overhang, cues and spoken lines per minute, replays. LOG=path, or no LOG to pull the newest trip
# log off the phone in local.mk. Read-only; no simulator.
audit:
	python3 scripts/cue_audit.py --selftest
	python3 scripts/cue_audit.py $(if $(LOG),"$(LOG)",--pull)

# Create the demo-phone simulator once (Xcode 27 does not ship this device by default). Running it
# again creates a second device with the same name; `-destination name=` then picks one of them.
# Waymark (plan M1): the runtime is the newest iOS runtime Xcode has installed (Xcode 27.1 may ship
# iOS 27.1 rather than 27.0). Override with SIM_RUNTIME=com.apple.CoreSimulator.SimRuntime.iOS-27-0.
SIM_RUNTIME ?= $(shell xcrun simctl list runtimes 2>/dev/null | grep -o 'com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9-]*' | tail -n 1)
sim17:
	@test -n "$(SIM_RUNTIME)" || { echo "No iOS simulator runtime installed — Xcode → Settings → Components → iOS"; exit 1; }
	xcrun simctl create "iPhone 17 Pro Max" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max $(SIM_RUNTIME)

# List paired / connected devices; copy the phone's identifier into DEVICE in local.mk.
devices:
	xcrun devicectl list devices

# Delete every generated artefact. ⚠ Also deletes CaneKit.xcodeproj, so the next xcodebuild target
# needs `make gen` first (the generated project is git-ignored; AGENTS.md hard rule 5).
clean:
	rm -rf $(DERIVED) CaneKit.xcodeproj Logic/.build
