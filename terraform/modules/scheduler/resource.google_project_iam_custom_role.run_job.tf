# A role containing exactly one permission: run.jobs.run.
#
# A custom role rather than a predefined one because no predefined role is that
# small, and the difference is checkable rather than rhetorical:
#
#   roles/run.invoker                    run.instances.invoke, run.jobs.run,
#                                        run.routes.invoke
#   roles/run.jobsExecutor               run.executions.cancel, run.jobs.run
#   roles/run.jobsExecutorWithOverrides  run.executions.cancel, run.jobs.run,
#                                        run.jobs.runWithOverrides
#
# The two extra permissions in run.invoker have no meaning on a Job resource, so
# binding it here would be harmless in practice. It would also be a role whose
# contents no longer describe what the principal may do, and the next person to
# ask "what can the scheduler do" would have to know that argument to answer.
# run.jobsExecutor is closer but still carries run.executions.cancel, which is
# the ability to kill a sweep in progress. A schedule starts things. It has no
# business stopping one.
#
# runWithOverrides is deliberately absent, which is the difference between this
# and the role docs-launcher holds on docs-build. The launcher must pass per build
# signed URLs, so it needs overrides. A schedule passes nothing: an override is
# how a caller changes what the container runs, and this caller must only be able
# to run it as terraform defined it. The one override an operator does use,
# DISCOVERY_FRESH, is a deliberate human action from the command line, not
# something the timer can do.
#
# Creating this costs the deploy identity roles/iam.roleAdmin. That is the price
# of the binding below being exactly one permission, and it is recorded in
# .github/SETUP.md alongside the other roles.
resource "google_project_iam_custom_role" "run_job" {
  project = var.project_id
  role_id = "runDiscoveryJob"
  title   = "Run the shard discovery Job"

  description = "Start executions of one Cloud Run Job. Exactly run.jobs.run: no overrides, no cancel, no read. Bound per Job, never at project scope"

  permissions = ["run.jobs.run"]
}
