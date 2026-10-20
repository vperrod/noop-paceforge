# Shared by the profile-today stages. Sourced, never run.
# OUT: everything uploaded as artifacts. W: scratch that is not uploaded.
export OUT="${RUNNER_TEMP:-/tmp}/profile-today-out"
export W="${RUNNER_TEMP:-/tmp}/profile-today-work"
mkdir -p "$OUT" "$W"
STATE="$W/state.env"
[ -f "$STATE" ] && . "$STATE"

save_state() { echo "export $1=\"$2\"" >> "$STATE"; export "$1=$2"; }

# run_limited SECONDS cmd... : kills cmd after SECONDS (macOS has no timeout(1)).
run_limited() { local s="$1"; shift; perl -e 'alarm shift; exec @ARGV' "$s" "$@"; }

# The arguments every launch shares: the demo seed (800 days of daily history, 7 days of 1 Hz heart rate), the synthetic
# PaceForge documents grown to the live list lengths (321 activities), dark look.
common_args() {
  echo --demo-seed --demo-seed-days 800 --demo-seed-raw-hr-days 7 -theme.appearance dark \
       -PaceForgeFixture -PaceForgeFixtureFile "$FIX"
}

container() { xcrun simctl get_app_container "$UDID" "$BID" data; }
