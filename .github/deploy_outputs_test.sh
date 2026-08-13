#!/usr/bin/env bash
#
# Checks that the deploy's terraform plumbing is connected end to end, before a
# deploy discovers it is not.
#
# This exists because a release job read a Job name the root stack never
# exported. `terraform validate` passed, because the module declared the output
# and the configuration was valid. CI passed, because nothing in CI reads
# deploy.yml. The apply passed too. The deploy then died reading its own
# outputs, after building six images and migrating four production databases:
#
#   Error: Output "docs_build_core_job" not found
#
# Three names have to agree for a value to travel from terraform to a release
# step, and nothing was checking that they do:
#
#   1. `emit_raw <name>` in the infra job reads a ROOT terraform output
#   2. the infra job's `outputs:` map republishes that step output
#   3. a later job reads it back as `needs.infra.outputs.<name>`
#
# Each link is asserted here. Adding a module output is not enough, and neither
# is adding a root output nobody republishes.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "${here}/.." && pwd)"
workflow="${repo}/.github/workflows/deploy.yml"
terraform_root="${repo}/terraform"

failures=0

fail() {
  printf 'FAIL  %s\n' "$1" >&2
  failures=$((failures + 1))
}

# Every terraform output the workflow reads. `emit_json NAME [ALIAS]` and
# `emit_raw NAME [ALIAS]` both take the terraform output name first.
emitted_tf_names="$(
  grep -Eo '^[[:space:]]*emit_(json|raw)[[:space:]]+[a-z0-9_]+' "$workflow" |
    awk '{ print $2 }' | sort -u
)"

# Only the ROOT module. terraform/modules/**/outputs.tf declares outputs that
# `terraform output` cannot see, which is exactly the confusion being guarded.
declared_tf_outputs="$(
  grep -Eho '^output "[a-z0-9_]+"' "${terraform_root}"/*.tf |
    sed -e 's/^output "//' -e 's/"$//' | sort -u
)"

# The step output name each emit publishes: the alias when given, else the
# terraform name.
emitted_step_outputs="$(
  grep -Eo '^[[:space:]]*emit_(json|raw)[[:space:]]+[a-z0-9_]+([[:space:]]+[a-z0-9_]+)?' "$workflow" |
    awk '{ print ($3 == "" ? $2 : $3) }' | sort -u
)"

# The infra job's outputs map, as pairs of "<job output> <step output>".
infra_outputs_map="$(
  awk '
    /^  infra:/            { in_job = 1 }
    in_job && /^  [a-z]/ && !/^  infra:/ { in_job = 0 }
    in_job && /^    outputs:/ { in_outputs = 1; next }
    in_outputs && /^    [a-z]/ { in_outputs = 0 }
    in_outputs && match($0, /^      [a-z0-9_]+:/) {
      job_output = substr($0, 7, RLENGTH - 7)
      if (match($0, /steps\.outputs\.outputs\.[a-z0-9_]+/)) {
        # "steps.outputs.outputs." is 22 characters.
        step_output = substr($0, RSTART + 22, RLENGTH - 22)
        print job_output, step_output
      } else {
        print job_output, "-"
      }
    }
  ' "$workflow" | sort -u
)"

# Every name a later job reads back off the infra job.
consumed_job_outputs="$(
  grep -Eo 'needs\.infra\.outputs\.[a-z0-9_]+' "$workflow" |
    sed 's/^needs\.infra\.outputs\.//' | sort -u
)"

printf 'Emitted terraform outputs:  %s\n' "$(echo "$emitted_tf_names" | tr '\n' ' ')"
printf 'Consumed infra job outputs: %s\n\n' "$(echo "$consumed_job_outputs" | tr '\n' ' ')"

# 1. Every emitted name is a real root output.
while read -r name; do
  [ -n "$name" ] || continue
  if ! grep -qx "$name" <<< "$declared_tf_outputs"; then
    fail "the deploy reads terraform output '${name}', which the root stack does not declare"
  else
    printf 'ok    root stack declares %s\n' "$name"
  fi
done <<< "$emitted_tf_names"

# 2. Every infra job output is fed by a step output something actually emits.
while read -r job_output step_output; do
  [ -n "$job_output" ] || continue
  if [ "$step_output" = "-" ]; then
    printf 'ok    infra output %s is not fed by the outputs step\n' "$job_output"
    continue
  fi
  if ! grep -qx "$step_output" <<< "$emitted_step_outputs"; then
    fail "infra job output '${job_output}' reads step output '${step_output}', which no emit_json/emit_raw publishes"
  else
    printf 'ok    infra output %s <- %s\n' "$job_output" "$step_output"
  fi
done <<< "$infra_outputs_map"

# 3. Every needs.infra.outputs.X a later job reads is declared by the infra job.
declared_job_outputs="$(awk '{ print $1 }' <<< "$infra_outputs_map" | sort -u)"
while read -r name; do
  [ -n "$name" ] || continue
  if ! grep -qx "$name" <<< "$declared_job_outputs"; then
    fail "a job reads 'needs.infra.outputs.${name}', which the infra job does not declare"
  else
    printf 'ok    consumer reads declared infra output %s\n' "$name"
  fi
done <<< "$consumed_job_outputs"

if [ "$failures" -ne 0 ]; then
  printf '\n%d deploy output wiring check(s) failed.\n' "$failures" >&2
  exit 1
fi

printf '\nAll deploy output wiring checks passed.\n'
