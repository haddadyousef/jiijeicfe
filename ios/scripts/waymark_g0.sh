#!/usr/bin/env bash
# Waymark G0 runner (plan v1.1 §7.2). Akash runs this on the Mac, one stage at a time; the Mac
# Claude session reads the logs it writes (git-ignored, waymark/logs/mac/). Nothing here pushes.
#
#   ios/scripts/waymark_g0.sh check      toolchain + repo state (fast)
#   ios/scripts/waymark_g0.sh baseline   make test on main (before our rename), the "is it us?" gate
#   ios/scripts/waymark_g0.sh rename     switch to waymark/g0-rename; make test, make gen, make sim
#   ios/scripts/waymark_g0.sh uitest     on main: make sim17 if needed; make uitest at UIUC, then at Seattle
#   ios/scripts/waymark_g0.sh device     on main: build, install, launch on the phone (needs ios/local.mk)
#
# Every step: `cmd > log 2>&1; echo "exit=$?" >> log`, judged by that exit code, never by `tail`
# (plan 7.2, design doc §0.4). The summary at the end prints only the exit codes and log paths.
# Safe to re-run a stage. Uses WATCH=0 (phone-only) for gen per plan D-09.
set -u
ROOT="$(git rev-parse --show-toplevel)" || { echo "run inside the Waymark repo"; exit 1; }
LOGS="$ROOT/waymark/logs/mac"
mkdir -p "$LOGS"
cd "$ROOT/ios"
SUMMARY=()

run() {  # run <log-name> <command...>
  local name="$1"; shift
  local log="$LOGS/$name.log"
  echo "== $name: $*"
  { echo "# $(date '+%Y-%m-%d %H:%M:%S %Z') on $(git rev-parse --short HEAD) ($(git branch --show-current))"
    echo "# \$ $*"; } > "$log"
  "$@" >> "$log" 2>&1
  local rc=$?
  echo "exit=$rc" >> "$log"
  SUMMARY+=("$name exit=$rc  ($log)")
  return $rc
}

finish() {
  echo; echo "---- summary ----"
  for line in "${SUMMARY[@]}"; do echo "$line"; done
  echo "Tell the Mac chat: \"g0 $STAGE done\" (it reads the logs itself)."
}

STAGE="${1:-}"
case "$STAGE" in
  check)
    run g0-check bash -c '
      xcodebuild -version; echo; xcode-select -p; echo
      command -v xcodegen && xcodegen --version || echo "xcodegen MISSING: brew install xcodegen"
      echo; sw_vers; echo; df -h ~ | tail -n 1; echo
      git remote -v; git branch --show-current; git status --short; git log --oneline -5
      echo; xcrun simctl list runtimes | grep -i ios || echo "no iOS simulator runtime"
      echo; test -f local.mk && grep -E "^(TEAM|DEVICE|BUNDLE_PREFIX)" local.mk | sed -E "s/(TEAM *= *).*/\1<set>/" || echo "ios/local.mk missing (only needed for the device stage)"'
    ;;
  baseline)
    git checkout -q main || exit 1
    run g0-baseline-test make test
    ;;
  rename)
    git checkout -q waymark/g0-rename || exit 1
    git pull -q --ff-only || true
    run g0-rename-test make test || { finish; exit 1; }
    run g0-rename-gen env WATCH=0 scripts/gen.sh || { finish; exit 1; }
    run g0-rename-sim make sim
    ;;
  uitest)
    git checkout -q main && git pull -q --ff-only origin main || exit 1
    # Simulator: SIM from the environment, else iPhone 17 Pro Max (the base repo's target), else
    # the first available iPhone Pro simulator. Xcode 27.1 refused to create a 17 Pro Max on the
    # iOS 27.1 runtime ("Incompatible device", 14:28), so the fallback matters.
    SIMNAME="${SIM:-}"
    if [ -z "$SIMNAME" ]; then
      if xcrun simctl list devices available | grep -q "iPhone 17 Pro Max ("; then SIMNAME="iPhone 17 Pro Max"
      elif run g0-sim17 make sim17; then SIMNAME="iPhone 17 Pro Max"
      else SIMNAME="$(xcrun simctl list devices available | sed -n -E 's/^ +(iPhone [0-9]+ Pro( Max)?) \(.*/\1/p' | head -n 1)"
      fi
    fi
    [ -n "$SIMNAME" ] || { echo "no iPhone Pro simulator available"; finish; exit 1; }
    echo "== simulator: $SIMNAME"
    run g0-uitest-uiuc make uitest SIM="$SIMNAME" SIM_LAT=40.1140 SIM_LON=-88.2249
    xcrun simctl shutdown all >/dev/null 2>&1 || true
    run g0-uitest-seattle make uitest SIM="$SIMNAME"
    ;;
  device)
    git checkout -q main && git pull -q --ff-only origin main || exit 1
    test -f local.mk || { cp local.mk.example local.mk; echo "Created ios/local.mk — fill in TEAM and DEVICE (make devices), then re-run: $0 device"; exit 1; }
    run g0-devices make devices
    run g0-device-gen env WATCH=0 scripts/gen.sh || { finish; exit 1; }
    run g0-device-run make build install launch
    ;;
  *)
    sed -n '2,12p' "$0"; exit 2 ;;
esac
finish
