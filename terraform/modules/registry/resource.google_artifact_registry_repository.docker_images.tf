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
  #
  # Keep policies win over delete policies in Artifact Registry, so the two KEEP
  # rules are the safety net rather than decoration.

  # Floor under every package regardless of tag state. keep_count is per package,
  # so this is 50 rollback targets deep for each app image, which is well past
  # any window in which somebody is still reverting a bad deploy.
  cleanup_policies {
    id     = "keep-recent-versions"
    action = "KEEP"

    most_recent_versions {
      keep_count = 50
    }
  }

  # Everything CI pushes is tagged with a full commit SHA and nothing else: the
  # build job pushes no `latest`, and the release job refuses any image reference
  # ending in :latest. So "tagged" here means "a commit's image", and keeping all
  # of them is what makes the delete rule below unable to touch anything a
  # revision could be pulling. It also means this repository does not shrink on
  # its own; see the note at the end of this file.
  cleanup_policies {
    id     = "keep-tagged-versions"
    action = "KEEP"

    condition {
      tag_state = "TAGGED"
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

# What this does not fix, said plainly so nobody reads the policies above as a
# solved problem: because every image CI pushes is tagged and tagged versions are
# kept, these rules bound the orphan pile and not the growth. The growth is one
# tagged image per app per commit, and no cleanup policy can prune it safely,
# because Artifact Registry cannot see which digests Cloud Run revisions are
# still able to pull. Reducing it needs a step that reads the live revisions and
# Job executions, collects the digests they reference, and deletes tagged
# versions outside that set: a deploy-time job with the deployed state in hand,
# not a rule in this file. Until that exists, the bound on this line is the
# retention above, and it is honest about being a floor rather than a fix.
