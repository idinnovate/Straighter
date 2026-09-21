#!/usr/bin/env bash
set -u
cd "$HOME/Straighter" || exit 1
export IRONFOX_YQ=/usr/local/bin/yq-go
LOG="$HOME/build.log"
STATUS="$HOME/build.status"
: > "$STATUS"
run_stage() {
  local name="$1"; shift
  echo "=== [$(date -u +%FT%TZ)] START $name ===" | tee -a "$LOG"
  echo "RUNNING $name" > "$STATUS"
  "$@" < /dev/null >> "$LOG" 2>&1
  local rc=$?
  echo "=== [$(date -u +%FT%TZ)] END $name (exit $rc) ===" | tee -a "$LOG"
  if [ "$rc" -ne 0 ]; then echo "FAILED $name (exit $rc)" > "$STATUS"; exit "$rc"; fi
}
run_stage build_arm64 bash -c "printf y\n | ./scripts/build.sh arm64"
echo "DONE" > "$STATUS"
