# Scheduler Module
# The one timer in this stack: it starts a bounded slice of the shard discovery
# sweep on a cadence, plus the caller identity it does that as and the single
# permission that identity holds.
#
# A separate module rather than an addition to modules/queue, which is the Cloud
# Tasks queue carrying lazy documentation build requests. The two look adjacent
# because both are "work that happens later", and they are not the same thing: a
# queue is filled by a request that has already happened and holds one item per
# shard version, while this fires on a clock with nobody asking. Folding a
# discovery timer into a module whose only variables describe documentation build
# concurrency would mislabel both.
#
# It is also not part of modules/services even though it triggers a Job defined
# there, because the Job and the decision to run it on a timer are separable: the
# Job is executable by hand with `gcloud run jobs execute discover-shards`
# whether or not any schedule exists, and keeping the schedule out means deleting
# it does not touch the thing it runs.
module "scheduler" {
  source = "./modules/scheduler"

  project_id = var.project_id
  region     = var.region

  # Read from the services module rather than restated. A schedule pointed at a
  # job name that does not exist fails with a 404 in the scheduler's own logs and
  # nowhere anybody watching the registry would see it.
  discovery_job_name     = module.services.discover_shards_job
  discovery_job_location = module.services.region

  depends_on = [module.project_services]
}
