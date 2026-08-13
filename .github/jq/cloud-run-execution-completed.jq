# Reads whether a Cloud Run Job execution finished successfully, from the
# document `gcloud run jobs executions describe --format=json` returns.
#
# The v2 API reports outcome as a CONDITION, not a state string:
#
#   { "conditions": [ { "type": "Completed", "status": "True",
#                       "message": "Execution completed successfully in 1m45s." } ] }
#
# Asking for `.state` on that returns null, and a null compared against any
# expected value fails. That is not hypothetical: it failed a deploy whose
# reconciliation had in fact completed successfully, which is the same false
# failure the docs-launcher audience selector produced before it was tested.
#
# Prints one of:
#   True     the execution completed successfully
#   False    the execution finished and did not succeed
#   <empty>  no Completed condition, so the outcome is unknown
#
# An unknown outcome is deliberately distinct from a failure. Both stop a
# deploy, and only one of them is a true statement about what was observed.
#
# Only the Completed condition answers this. Started, ContainerReady and
# ResourcesAvailable are all True on an execution whose tasks then failed, so
# reading "some condition is True" would pass a failed run.
((.conditions // .status.conditions // [])
 | map(select(.type == "Completed"))
 | first
 | .status)
// empty
