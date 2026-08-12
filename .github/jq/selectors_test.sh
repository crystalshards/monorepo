#!/usr/bin/env bash
#
# Tests the jq programs the deploy uses to decide whether docs-launcher will
# accept the build tokens Cloud Tasks mints for it.
#
# These exist because that check has been wrong in both directions. It first
# read an annotation path Cloud Run does not use, reported that the service
# accepted no audiences, and failed a release while the audience was applied
# and working. Rewriting it to search the whole document fixed the false
# failure by introducing a false pass: a revision template can carry its own
# copy of the annotation describing what a future revision would declare, so a
# service rejecting every token would have looked fine.
#
# The workflow reads these same files, so this cannot drift away from what the
# deploy actually runs. A test holding its own copy of the program would prove
# nothing.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
configured="${here}/docs-launcher-configured-audience.jq"
accepted="${here}/docs-launcher-accepted-audiences.jq"

failures=0

check() {
  local program="$1" name="$2" want="$3" doc="$4" got

  got="$(jq -r --from-file "$program" <<< "$doc")"

  if [ "$got" != "$want" ]; then
    printf 'FAIL  %s\n      want: [%s]\n      got:  [%s]\n' "$name" "$want" "$got" >&2
    failures=$((failures + 1))
  else
    printf 'ok    %s\n' "$name"
  fi
}

# --- what the service is configured to verify --------------------------------

check "$configured" "v1: reads the serving template" \
  "https://launcher.internal" \
  '{"spec":{"template":{"spec":{"containers":[{"env":[
     {"name":"OTHER","value":"x"},
     {"name":"DOCS_LAUNCHER_AUDIENCE","value":"https://launcher.internal"}]}]}}}}'

check "$configured" "v2: reads the template containers" \
  "https://launcher.internal" \
  '{"template":{"containers":[{"env":[
     {"name":"DOCS_LAUNCHER_AUDIENCE","value":"https://launcher.internal"}]}]}}'

# An empty array is truthy in jq, so a `//` between the two shapes would let an
# empty v1 list hide a populated v2 one.
check "$configured" "empty v1 list does not suppress v2" \
  "https://launcher.internal" \
  '{"spec":{"template":{"spec":{"containers":[]}}},
    "template":{"containers":[{"env":[
     {"name":"DOCS_LAUNCHER_AUDIENCE","value":"https://launcher.internal"}]}]}}'

# The false pass this must never allow: the current template has nothing and an
# old revision still carries the variable.
check "$configured" "a stale revision cannot vouch for the template" \
  "" \
  '{"spec":{"template":{"spec":{"containers":[{"env":[]}]}}},
    "status":{"revisions":[{"spec":{"containers":[{"env":[
     {"name":"DOCS_LAUNCHER_AUDIENCE","value":"https://stale.internal"}]}]}}]}}'

check "$configured" "an empty value is not a value" \
  "" \
  '{"spec":{"template":{"spec":{"containers":[{"env":[
     {"name":"DOCS_LAUNCHER_AUDIENCE","value":""}]}]}}}}'

# A secret reference has no literal to compare against, so it must not read as
# configured.
check "$configured" "a secret reference is not a literal audience" \
  "" \
  '{"spec":{"template":{"spec":{"containers":[{"env":[
     {"name":"DOCS_LAUNCHER_AUDIENCE","valueFrom":{"secretKeyRef":{"name":"a"}}}]}]}}}}'

check "$configured" "agreeing containers read as one value" \
  "https://launcher.internal" \
  '{"spec":{"template":{"spec":{"containers":[
     {"env":[{"name":"DOCS_LAUNCHER_AUDIENCE","value":"https://launcher.internal"}]},
     {"env":[{"name":"DOCS_LAUNCHER_AUDIENCE","value":"https://launcher.internal"}]}]}}}}'

check "$configured" "disagreeing containers are refused, not resolved" \
  "CONFLICT: https://a.internal, https://b.internal" \
  '{"spec":{"template":{"spec":{"containers":[
     {"env":[{"name":"DOCS_LAUNCHER_AUDIENCE","value":"https://a.internal"}]},
     {"env":[{"name":"DOCS_LAUNCHER_AUDIENCE","value":"https://b.internal"}]}]}}}}'

# --- what the service actually accepts ---------------------------------------

# The exact shape the live service returns: service-level annotation, holding a
# JSON-encoded array as a string. Getting this path wrong is what failed a good
# release.
check "$accepted" "v1: service-level annotation, JSON encoded" \
  "https://launcher.internal" \
  '{"metadata":{"annotations":{
     "run.googleapis.com/custom-audiences":"[\"https://launcher.internal\"]"}}}'

check "$accepted" "v2: plain array at the top level" \
  "https://launcher.internal" \
  '{"customAudiences":["https://launcher.internal"]}'

check "$accepted" "both shapes are collected" \
  "https://a.internal https://b.internal" \
  '{"metadata":{"annotations":{"run.googleapis.com/custom-audiences":"[\"https://a.internal\"]"}},
    "customAudiences":["https://b.internal"]}'

# The false pass: a template-level copy describes a future revision, not what
# this service accepts today.
check "$accepted" "a template copy does not count as accepted" \
  "" \
  '{"spec":{"template":{"metadata":{"annotations":{
     "run.googleapis.com/custom-audiences":"[\"https://ghost.internal\"]"}}}}}'

check "$accepted" "a service with none reports none" \
  "" \
  '{"metadata":{"annotations":{}}}'

# An annotation that is present but not JSON is reported as itself, not folded
# into the empty result. Both stop the release; only one of them tells the
# truth about what was observed.
check "$accepted" "an unparseable annotation says so" \
  "UNPARSEABLE: not json" \
  '{"metadata":{"annotations":{"run.googleapis.com/custom-audiences":"not json"}}}'

if [ "$failures" -ne 0 ]; then
  printf '\n%d selector test(s) failed.\n' "$failures" >&2
  exit 1
fi

printf '\nAll deploy selector tests passed.\n'
