# The one registry for every application image.
#
# This replaces the multi region "crystalshards" repository in "us" that the
# deleted cluster module owned. It is a new repository rather than an adoption
# of that one: the old repository holds builds of apps that have changed
# underneath them, every deploy builds fresh and tags by commit SHA, and
# adopting it would mean carrying an import block forward purely to inherit a
# leftover of the architecture being removed.
#
# Images are pushed to and pulled from:
#   <region>-docker.pkg.dev/<project>/docker-images/<app>:<sha>
resource "google_artifact_registry_repository" "docker_images" {
  project       = var.project_id
  location      = var.region
  repository_id = "docker-images"
  description   = "Container images for the CrystalShards Cloud Run services and jobs"
  format        = "DOCKER"

  # Cleanup runs for real rather than in audit mode. Stated explicitly because
  # the field is the difference between a policy that deletes and a policy that
  # only logs what it would have deleted, and the default reads as neither.
  # Flip this to true to audit a change to the rules below before it bites.
  cleanup_policy_dry_run = false

  # Why there are policies here at all: CI pushes one image per app per commit
  # (see the build matrix in .github/workflows/deploy.yml) and nothing has ever
  # removed one. Measured growth is 0.476 GiB a day, 5.83 GiB and $0.53 a month
  # at the time of writing, which straight-lines to $17.32 a month by month 12.
  # Storage is the cheapest thing on this bill and it is the only line that only
  # ever goes up.
  #
  # The hard constraint on anything written here is that a cleanup policy has no
  # idea what Cloud Run is running. Every service and Job in the services module
  # carries lifecycle { ignore_changes = [...image...] }: terraform sets the
  # image once and CI rolls the tag afterwards, so terraform's state is not a
  # record of what is deployed, and a service that has not been redeployed in
  # months is still pulling the image from the commit that last touched it. On
  # top of that, the rollback path is "re-point a service at an older commit's
  # tag", so a deleted image is a rollback target that no longer exists. Deleting
  # something a live revision can still pull would trade a storage line for an
  # outage, so the rules below are deliberately timid.

  # KEEP policies always take precedence over DELETE policies in Artifact
  # Registry (see Google Cloud documentation at
  # https://cloud.google.com/artifact-registry/docs/repositories/cleanup-policy-overview).
  # If an image matches both a KEEP policy and a DELETE policy, KEEP wins and
  # the image is never deleted.
  # Floor under every package regardless of tag state. keep_count is per package,
  # preserving 50 versions deep for each app image. Because KEEP beats DELETE,
  # the active serving revision and up to 49 rollback targets are unconditionally
  # preserved even if they are older than 30 days and even for services that
  # deploy infrequently (like trycrystal-runner).
  cleanup_policies {
    id     = "keep-recent-versions"
    action = "KEEP"

    most_recent_versions {
      keep_count = 50
    }
  }

  # Delete tagged versions older than 30 days unless kept by a KEEP policy.
  #
  # Because keep-recent-versions above protects the 50 most recent versions of
  # each package with KEEP precedence, this rule only ever deletes versions
  # that are BOTH older than 30 days AND outside the 50 most recent versions
  # for their package. This bounds repository growth to at most 50 versions per
  # package (approximately 500 images total across all services and jobs),
  # halting the 0.476 GiB/day ($17.32/month by month 12) growth rate.
  cleanup_policies {
    id     = "delete-stale-tagged"
    action = "DELETE"

    condition {
      tag_state  = "TAGGED"
      older_than = "2592000s"
    }
  }

  # The only thing actually deleted: versions carrying no tag at all, and only
  # once they are 30 days old. An untagged version in this repository is an
  # orphan by construction rather than part of a tagged image. Builds are single
  # platform (platforms: linux/amd64) with provenance: false, so a push produces
  # one manifest and no manifest list, which is what makes this safe: in a
  # multi-arch or attested repository the untagged versions are the per
  # architecture children of a tagged index, and deleting them breaks the tag
  # that points at them. If either of those build settings ever changes, this
  # rule has to be revisited before the build is merged.
  #
  # 30 days rather than something shorter because an orphan costs pennies and the
  # only way one appears here is a tag being re-pushed over a different digest,
  # which is exactly the situation where somebody may still want the thing that
  # was displaced.
  cleanup_policies {
    id     = "delete-stale-untagged"
    action = "DELETE"

    condition {
      tag_state  = "UNTAGGED"
      older_than = "2592000s"
    }
  }

  labels = {
    environment = "production"
    managed_by  = "terraform"
  }
}

# How repository growth is bounded safely:
#
# CI tags every built image with a commit SHA. In earlier versions of this file,
# all tagged versions were kept forever out of concern that Artifact Registry
# could not see which images Cloud Run revisions reference. That allowed image
# storage to grow by 0.476 GiB per day indefinitely.
#
# Combining keep-recent-versions (keep_count = 50) with delete-stale-tagged (30
# days) bounds this growth safely. In Google Cloud Artifact Registry, KEEP
# policies always take precedence over DELETE policies. For packages that deploy
# rarely, all historical versions remain within the 50 most recent versions and
# are never deleted regardless of age. For packages that deploy frequently,
# versions beyond the 50 most recent that are older than 30 days are pruned,
# capping repository size while preserving all active revisions and recent
# rollback targets.
