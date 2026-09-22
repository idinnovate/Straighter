#!/usr/bin/env bash
set -u
cd "$HOME/ironfox-docker" || exit 1
LOG="$HOME/build-docker.log"
STATUS="$HOME/build-docker.status"
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
D="sudo docker exec ironfox-builder bash -c"
run_stage image      sudo docker build -t ironfox-builder -f Dockerfile .
run_stage container  bash -c "sudo docker rm -f ironfox-builder >/dev/null 2>&1; sudo docker run -d -it --name ironfox-builder -v $HOME/ironfox-docker:/app ironfox-builder"
run_stage git_trust  $D "git config --global --add safe.directory \"*\""
run_stage get_sources $D "cd /app && ./scripts/get_sources.sh"
run_stage prebuild   $D "cd /app && ./scripts/prebuild.sh"
run_stage build_arm64 $D "cd /app && printf \"y\\n\" | ./scripts/build.sh arm64"
echo "DONE" > "$STATUS"
