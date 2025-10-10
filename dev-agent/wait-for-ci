#!/usr/bin/env bash
set -e

SHA=$(git rev-parse HEAD)
echo "Waiting for all workflows to complete for SHA: $SHA"

# Track all run IDs we're monitoring (includes dependencies)
declare -A monitored_runs
declare -A checked_for_deps

# Get initial runs for the commit
get_initial_runs() {
  gh run list --commit "$SHA" --json databaseId,status,conclusion,name --limit 100 | \
    jq -r '.[] | @json'
}

# Find dependent workflows triggered by a specific run
find_dependent_runs() {
  local trigger_run_id=$1

  # Skip if we already checked this run for dependencies
  [[ -n "${checked_for_deps[$trigger_run_id]}" ]] && return
  checked_for_deps[$trigger_run_id]=1

  # Get workflow_run events that might be triggered by this run
  # Look for runs that started after our run and have workflow_run event
  local api_output
  api_output=$(gh api "/repos/:owner/:repo/actions/runs" \
    --paginate \
    -f event=workflow_run \
    --jq ".workflow_runs[] | select(.id > $trigger_run_id) | select(.id <= ($trigger_run_id + 10000)) | {databaseId: .id, status: .status, conclusion: .conclusion, name: .name, event: .event, workflow_run_id: .triggering_actor.workflow_run_id}" 2>/dev/null || true)

  # Only process if we got valid output with databaseId (not an error response)
  if [[ -n "$api_output" ]] && echo "$api_output" | jq -e 'select(.databaseId)' >/dev/null 2>&1; then
    echo "$api_output" | jq -s '.[]' 2>/dev/null || true
  fi
}

# Main monitoring loop
wait_for_runs() {
  # Initialize with runs from the commit
  while IFS= read -r run; do
    run_id=$(echo "$run" | jq -r '.databaseId')
    monitored_runs[$run_id]="$run"
  done < <(get_initial_runs)
  
  while true; do
    # Refresh status of all monitored runs
    local temp_monitored_runs
    declare -A temp_monitored_runs
    
    for run_id in "${!monitored_runs[@]}"; do
      current_status=$(gh run view "$run_id" --json status,conclusion,name,databaseId 2>/dev/null | jq -c '.')
      temp_monitored_runs[$run_id]="$current_status"
      
      # If a run just completed, look for dependent workflows
      status=$(echo "$current_status" | jq -r '.status')
      if [[ "$status" == "completed" ]]; then
        while IFS= read -r dep_run; do
          dep_id=$(echo "$dep_run" | jq -r '.databaseId')
          if [[ -z "${monitored_runs[$dep_id]}" ]]; then
            echo "  📎 Found dependent workflow: $(echo "$dep_run" | jq -r '.name')"
            temp_monitored_runs[$dep_id]="$dep_run"
          fi
        done < <(find_dependent_runs "$run_id")
      fi
    done
    
    monitored_runs=()
    for key in "${!temp_monitored_runs[@]}"; do
      monitored_runs[$key]="${temp_monitored_runs[$key]}"
    done
    
    # Count progress
    total=${#monitored_runs[@]}
    completed=0
    failed=0
    
    echo -e "\n📊 Monitoring $total workflow run(s):"
    for run_id in "${!monitored_runs[@]}"; do
      run="${monitored_runs[$run_id]}"
      name=$(echo "$run" | jq -r '.name')
      status=$(echo "$run" | jq -r '.status')
      conclusion=$(echo "$run" | jq -r '.conclusion // "in_progress"')
      
      if [[ "$status" == "completed" ]]; then
        ((completed++))
        if [[ "$conclusion" == "failure" || "$conclusion" == "cancelled" ]]; then
          ((failed++))
          echo "  ❌ $name: $conclusion"
        else
          echo "  ✅ $name: $conclusion"
        fi
      else
        echo "  ⏳ $name: $status"
      fi
    done
    
    echo "Progress: $completed/$total completed"
    
    # Check if we're done
    if [[ "$completed" -eq "$total" ]]; then
      if [[ "$failed" -gt 0 ]]; then
        echo -e "\n❌ $failed workflow(s) failed"
        exit 1
      else
        echo -e "\n✅ All workflows (including dependents) completed successfully"
        exit 0
      fi
    fi
    
    sleep 10
  done
}

if [ "$(get_initial_runs | wc -l)" -eq 0 ]; then
  echo "No workflow runs found for this SHA"
  exit 0
fi

wait_for_runs