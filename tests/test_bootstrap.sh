#!/bin/bash
# shellcheck disable=SC2016,SC2319,SC2015  # intentional: single-quoted stub bodies; $? of && chains
# Stub-based tests for the bootstrap script embedded in cloud-init.yaml.
# Usage: tests/test_bootstrap.sh   (needs python3 with pyyaml; set PY to override)
# Not a substitute for a real boot: no cloud-init ordering, no systemd, no real network.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
PY=${PY:-python3}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
"$PY" "$HERE/extract.py" "$HERE/../cloud-init.yaml" "$T/script.sh" || exit 1
mkdir "$T/bin"; FAILS=0
FPR=060A61C51B558A7F742B77AAC52FEB6B621E9F35

stub() { printf '#!/bin/bash\n%s\n' "$2" > "$T/bin/$1"; chmod +x "$T/bin/$1"; }
setup() { # fresh stubs; behavior switched by env vars in the stub bodies
  rm -f "$T/calls" "$T/marker" "$T/bin/"*; : > "$T/calls"
  stub curl 'echo "curl $*" >> '"$T/calls"'
[ "${STUB_NET:-up}" = up ] || exit 7
out=""; while [ $# -gt 0 ]; do [ "$1" = -o ] && out=$2; shift; done
[ -n "$out" ] && case "$out" in *docker-ce.repo*) printf "[docker-ce-stable]\ngpgcheck=${STUB_GPGCHECK:-1}\ngpgkey=https://x/gpg\n[docker-ce-test]\ngpgcheck=${STUB_OTHER_GPGCHECK:-1}\ngpgkey=https://x/gpg\n" > "$out";; *) echo key > "$out";; esac; exit 0'
  stub gpg 'echo "fpr:::::::::${STUB_FPR:-'"$FPR"'}:"'
  stub rpm 'echo "rpm $*" >> '"$T/calls"'; [ "$1" = --import ] && exit 0; exit 1'
  stub dnf 'echo "dnf $*" >> '"$T/calls"'; exit 0'
  stub sleep 'exit 0'
  stub systemctl 'echo "systemctl $*" >> '"$T/calls"'
[ "$1" = is-enabled ] && [ "${STUB_ENABLED:-yes}" != yes ] && exit 1; exit 0'
  stub usermod 'echo "usermod $*" >> '"$T/calls"
  stub docker 'echo "docker $*" >> '"$T/calls"'; [ "${STUB_DOCKER:-ok}" = ok ]'
}
run() { # run with stubbed PATH; WAIT_SECS=0 so unreachable net fails fast
  PATH="$T/bin:$PATH" REPO_FILE="$T/docker-ce.repo" MARKER="$T/marker" WAIT_SECS=0 \
    bash "$T/script.sh" > "$T/out" 2>&1; echo $?
}
check() { # check <name> <cond-exit>
  if [ "$2" -eq 0 ]; then echo "PASS $1"; else echo "FAIL $1"; FAILS=$((FAILS+1)); sed 's/^/    /' "$T/out"; fi
}

setup; rc=$(run); [ "$rc" = 0 ] && [ -f "$T/marker" ]; check "success: exit 0 and marker written" $?
# marker must come after both verification checks: stubs log calls, marker is touched last in script
grep -n 'docker --version\|is-enabled\|touch "\$MARKER"' "$T/script.sh" | awk -F: 'NR==1{a=$1} NR==2{b=$1} NR==3{c=$1} END{exit !(a<b && b<c)}'
check "marker is touched after docker --version and is-enabled (script order)" $?
grep -q 'docker-ce-stable.skip_if_unavailable=False' "$T/calls"; check "docker repo not skippable in dnf call" $?
grep -q 'skip_if_unavailable=True' "$T/calls"; check "other repos skippable in dnf call" $?

export STUB_NET=down; setup; rc=$(run); [ "$rc" != 0 ] && [ ! -f "$T/marker" ]; check "unreachable repo: non-zero, no marker" $?
! grep -q '^dnf .*install' "$T/calls"; check "unreachable repo: no install attempted" $?
unset STUB_NET

export STUB_DOCKER=bad; setup; rc=$(run); [ "$rc" != 0 ] && [ ! -f "$T/marker" ]; check "docker --version fails: non-zero, no marker" $?
unset STUB_DOCKER
export STUB_ENABLED=no; setup; rc=$(run); [ "$rc" != 0 ] && [ ! -f "$T/marker" ]; check "is-enabled fails: non-zero, no marker" $?
unset STUB_ENABLED
export STUB_FPR=DEADBEEF; setup; rc=$(run); [ "$rc" != 0 ] && [ ! -f "$T/marker" ] && ! grep -q '^dnf .*install' "$T/calls"; check "wrong GPG fingerprint: fails before install" $?
unset STUB_FPR
export STUB_GPGCHECK=0; setup; rc=$(run); [ "$rc" != 0 ] && [ ! -f "$T/marker" ] && ! grep -q '^dnf .*install' "$T/calls"; check "gpgcheck=0: fails before install" $?
unset STUB_GPGCHECK
# gpgcheck=1 in another section must not satisfy the check for [docker-ce-stable]
export STUB_GPGCHECK=0 STUB_OTHER_GPGCHECK=1; setup; rc=$(run); [ "$rc" != 0 ] && ! grep -q '^dnf .*install' "$T/calls"; check "gpgcheck=0 in stable, =1 elsewhere: fails before install" $?
unset STUB_GPGCHECK STUB_OTHER_GPGCHECK
setup; rc=$(run); grep -q '^rpm --import' "$T/calls"; check "verified key imported before install" $?

# stale marker from an earlier run must not survive a failed run
export STUB_DOCKER=bad; setup; touch "$T/marker"; rc=$(run); [ "$rc" != 0 ] && [ ! -f "$T/marker" ]; check "stale marker removed on failed run" $?
unset STUB_DOCKER

[ "$FAILS" -eq 0 ] && echo "ALL PASS" || { echo "$FAILS FAILED"; exit 1; }
