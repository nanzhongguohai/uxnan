#!/usr/bin/env bash
#
# deploy-bridge.sh — build the uxnan-bridge from `main`, deploy it into the
# global npm prefix, stamp a build marker, and restart the daemon.
#
# Every step ends with an invariant check, so at any point you can tell
# "which build is actually running" — and never again have to guess.
#
# Usage:
#   scripts/deploy-bridge.sh                 # build -> test -> backup -> deploy -> mark -> restart
#   scripts/deploy-bridge.sh --no-restart    # stop before the restart (deploy is live but stale)
#   scripts/deploy-bridge.sh --skip-test     # skip the test gate (emergency only)
#   scripts/deploy-bridge.sh --skip-build    # redeploy the already-built dist (no rebuild)
#   scripts/deploy-bridge.sh --rollback      # restore the newest backup and restart
#
# Layout it manages (all measured, not assumed):
#   source of truth : /data/github/uxnan                     (monorepo, git repo)
#   build output    : <repo>/bridge/dist , <repo>/shared/dist (dist/ is gitignored)
#   install dir     : /opt/node-v24.14.0-linux-x64/lib/node_modules/uxnan-bridge
#   bin symlink     : /opt/node-v24.14.0-linux-x64/bin/uxnan-bridge -> ../lib/node_modules/uxnan-bridge/dist/src/cli.js
#   daemon          : root user-unit uxnan-bridge.service -> /usr/local/sbin/uxnan-bridge-start.sh
#                     -> exec node .../uxnan-bridge/dist/src/cli.js start
#
# Why shared is deployed too: uxnan-bridge imports @uxnan/shared at RUNTIME, and
# the installed copy is a real directory, not a workspace symlink. Building only
# bridge and copying only bridge/dist leaves shared stale whenever shared moves.

set -euo pipefail

REPO="/data/github/uxnan"
NPM_PREFIX="/opt/node-v24.14.0-linux-x64"
NODE="$NPM_PREFIX/bin/node"
NPM="$NPM_PREFIX/bin/npm"
INSTALL_DIR="$NPM_PREFIX/lib/node_modules/uxnan-bridge"
SERVICE="uxnan-bridge"
STAMP="$(date +%Y%m%d-%H%M%S)"
TS="$STAMP"

NO_RESTART=0
SKIP_TEST=0
SKIP_BUILD=0
ROLLBACK=0

for arg in "$@"; do
  case "$arg" in
    --no-restart) NO_RESTART=1 ;;
    --skip-test)  SKIP_TEST=1 ;;
    --skip-build) SKIP_BUILD=1 ;;
    --rollback)   ROLLBACK=1 ;;
    -h|--help)    sed -n '3,24p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
note() { printf '\033[1m    %s\033[0m\n' "$*"; }
fail() { printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

# Root's user-session bus lives here; the daemon is a user unit under uid 0.
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/0}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/0/bus}"

[ -x "$NODE" ] || fail "node not found at $NODE"
[ -d "$INSTALL_DIR" ] || fail "install dir missing: $INSTALL_DIR"
[ -d "$REPO/.git" ] || fail "not a git checkout: $REPO"

GIT_SHA="$(git -C "$REPO" rev-parse --short=8 HEAD)"
GIT_BRANCH="$(git -C "$REPO" rev-parse --abbrev-ref HEAD)"
GIT_DIRTY="$(git -C "$REPO" status --porcelain | wc -l | tr -d ' ')"

# --------------------------------------------------------------------------
# 6. Restart + health check.
# --------------------------------------------------------------------------
health_check() {
  local want_version="$1" i state out live_version lan

  step "step 6/6  restart + health check"

  if [ "$NO_RESTART" -eq 1 ]; then
    note "skipping restart (--no-restart)"
    return 0
  fi

  systemctl --user daemon-reload || true
  systemctl --user restart "$SERVICE"
  note "systemctl --user restart $SERVICE sent"

  state="inactive"
  for i in $(seq 1 30); do
    state="$(systemctl --user is-active "$SERVICE" 2>/dev/null || true)"
    [ "$state" = "active" ] && break
    sleep 1
  done
  [ "$state" = "active" ] || fail "service not active after restart (state=${state:-unknown})"
  note "service active after ${i}s"

  # `uxnan-bridge status` prints JSON and exits. Its own `version` field is the
  # one thing that tells you which build is live.
  out="$("$NODE" "$INSTALL_DIR/dist/src/cli.js" status 2>/dev/null)" \
    || fail "uxnan-bridge status failed to run"

  live_version="$(printf '%s' "$out" | "$NODE" -e '
    let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
      try{console.log(JSON.parse(s).version||"")}catch(e){console.log("")}});')"
  [ -n "$live_version" ] || fail "could not read version from status output"

  [ "$live_version" = "$want_version" ] \
    || fail "version mismatch: running=$live_version  expected=$want_version"
  note "running version = $live_version"

  lan="$(printf '%s' "$out" | "$NODE" -e '
    let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
      try{console.log(String(JSON.parse(s).lanEnabled))}catch(e){console.log("unknown")}});')"
  [ "$lan" = "true" ] || note "lanEnabled=$lan (expected true) — daemon may still be booting transport"

  printf '\n\033[1;32mDeployed %s (branch %s, %s files dirty)\033[0m\n' \
    "$live_version" "$GIT_BRANCH" "$GIT_DIRTY"
  printf '%s\n' "$out" | sed 's/^/    /'
}

# --------------------------------------------------------------------------
# --rollback : restore the newest timestamped backup, then restart.
# --------------------------------------------------------------------------
if [ "$ROLLBACK" -eq 1 ]; then
  step "rollback: newest backup"
  newest_dist="$(ls -1d "$INSTALL_DIR"/dist.bak-* 2>/dev/null | sort | tail -1 || true)"
  newest_pkg="$(ls -1t "$INSTALL_DIR"/package.json.bak-* 2>/dev/null | sort | tail -1 || true)"
  [ -n "$newest_dist" ] || [ -n "$newest_pkg" ] || fail "no backup to roll back to"

  if [ -n "$newest_dist" ]; then
    rm -rf "$INSTALL_DIR/dist"
    cp -a "$newest_dist" "$INSTALL_DIR/dist"
    note "restored dist from $(basename "$newest_dist")"
  fi
  if [ -n "$newest_pkg" ]; then
    cp -a "$newest_pkg" "$INSTALL_DIR/package.json"
    note "restored package.json from $(basename "$newest_pkg")"
  fi
  health_check "$(grep -o '"version": *"[^"]*"' "$INSTALL_DIR/package.json" | head -1 | sed 's/.*"\(.*\)"/\1/')"
  exit 0
fi

# --------------------------------------------------------------------------
# 1. Build
# --------------------------------------------------------------------------
step "step 1/6  build (shared -> relay -> bridge)"
if [ "$SKIP_BUILD" -eq 1 ]; then
  note "skipping build (--skip-build)"
else
  (cd "$REPO" && "$NPM" run build)
fi
[ -f "$REPO/bridge/dist/src/cli.js" ] || fail "build produced no bridge/dist/src/cli.js"
note "built $(git -C "$REPO" rev-parse --short HEAD) into bridge/dist"

# --------------------------------------------------------------------------
# 2. Test gate
# --------------------------------------------------------------------------
if [ "$SKIP_TEST" -eq 1 ]; then
  step "step 2/6  test gate (skipped --skip-test)"
else
  step "step 2/6  test gate (uxnan-bridge)"
  (cd "$REPO" && "$NPM" run test -w uxnan-bridge)
  note "test gate passed"
fi

# --------------------------------------------------------------------------
# 3. Backup
# --------------------------------------------------------------------------
step "step 3/6  backup"
cp -a "$INSTALL_DIR/dist"          "$INSTALL_DIR/dist.bak-$TS"
cp -a "$INSTALL_DIR/package.json"  "$INSTALL_DIR/package.json.bak-$TS"
if [ -d "$INSTALL_DIR/node_modules/@uxnan/shared" ]; then
  cp -a "$INSTALL_DIR/node_modules/@uxnan/shared" "$INSTALL_DIR/node_modules/@uxnan/shared.bak-$TS"
fi
note "backed up -> *.bak-$TS"

# --------------------------------------------------------------------------
# 4. Deploy
# --------------------------------------------------------------------------
step "step 4/6  deploy (bridge/dist + shared/dist)"
rm -rf "$INSTALL_DIR/dist"
cp -a "$REPO/bridge/dist" "$INSTALL_DIR/dist"

SHARED_DST="$INSTALL_DIR/node_modules/@uxnan/shared/dist"
if [ -d "$SHARED_DST" ]; then
  rm -rf "$SHARED_DST"
  cp -a "$REPO/shared/dist" "$SHARED_DST"
  cp -a "$REPO/shared/package.json" "$INSTALL_DIR/node_modules/@uxnan/shared/package.json"
  [ -f "$REPO/shared/README.md" ] && \
    cp -a "$REPO/shared/README.md" "$INSTALL_DIR/node_modules/@uxnan/shared/README.md"
fi
note "copied bridge/dist and shared/dist into install dir"

# --------------------------------------------------------------------------
# 5. Build marker
# --------------------------------------------------------------------------
step "step 5/6  build marker"

# base version comes from the SOURCE package.json; only the `version` field of
# the installed package.json is rewritten. Re-reading it back is what makes
# this step auditable: the marker is derived from the build, not hand-typed.
BASE_VERSION="$("$NODE" -e "console.log(JSON.parse(require('fs').readFileSync('$REPO/bridge/package.json','utf8')).version)")"
[ -n "$BASE_VERSION" ] || fail "could not read source version from $REPO/bridge/package.json"
WANT_VERSION="${BASE_VERSION}-custom.${TS}.${GIT_SHA}"

"$NODE" -e '
  const fs = require("fs");
  const [p, v] = process.argv.slice(1);
  const obj = JSON.parse(fs.readFileSync(p, "utf8"));
  obj.version = v;
  fs.writeFileSync(p, JSON.stringify(obj, null, 2) + "\n");
' "$INSTALL_DIR/package.json" "$WANT_VERSION"

# read the authoritative value back out of the file we just wrote
MARKER_VERSION="$("$NODE" -e "console.log(JSON.parse(require('fs').readFileSync('$INSTALL_DIR/package.json','utf8')).version)")"
[ "$MARKER_VERSION" = "$WANT_VERSION" ] \
  || fail "build marker did not persist: file=$MARKER_VERSION expected=$WANT_VERSION"
note "install package.json version = $MARKER_VERSION"

# --------------------------------------------------------------------------
# 6. Restart + health check
# --------------------------------------------------------------------------
health_check "$MARKER_VERSION"

# --------------------------------------------------------------------------
# Final invariant: what is on disk == what was built.
# --------------------------------------------------------------------------
step "verify: disk == build"
diff -rq "$REPO/bridge/dist" "$INSTALL_DIR/dist" >/dev/null \
  || fail "bridge/dist drifts from build output"
if [ -d "$SHARED_DST" ]; then
  diff -rq "$REPO/shared/dist" "$SHARED_DST" >/dev/null \
    || fail "shared/dist drifts from build output"
fi
note "bridge/dist and shared/dist are byte-identical to the build output"
printf '\n\033[1;32mOK\033[0m  %s  deployed from %s/%s\n' "$MARKER_VERSION" "$GIT_BRANCH" "$GIT_SHA"
