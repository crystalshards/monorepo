# trycrystal-runner. The identity that executes strangers' Crystal.
#
# THIS SERVICE ACCOUNT HOLDS NO IAM BINDINGS ANYWHERE, AND THAT IS THE DESIGN.
#
# Every /execute request is untrusted code by definition: a lesson submission
# is arbitrary Crystal, and running it compiles and executes macros too. The
# runner runs as this identity with the metadata server one HTTP call away, so
# any role bound to it becomes a role the submission holds. The docs-build
# identity is the precedent and the same rule applies here, with one
# difference in our favour: docs-build receives signed URLs to objects, while
# the runner needs nothing at all. Its input arrives over the request body,
# its output leaves over the response body, and the only identity it presents
# is the one the app checks before trusting the answer.
#
# If you are here because something in the runner path is failing with a 403
# and you are about to add a role: don't. Work out which side of the app to
# runner boundary the missing permission belongs on and give it to the app,
# which is trusted. Granting a role here is how the sandbox stops being a
# sandbox, and an identity with no permissions is the property that made this
# runtime usable for strangers' code at all.
#
# Platform-enforced confinement and its gaps are recorded in
# apps/trycrystal/sandbox/VERIFICATION.md. The platform provides the gVisor
# sandbox per instance, CPU and memory caps, the request timeout and the IAM
# gate on ingress. The platform does NOT provide egress denial or a non-root
# uid; the runner process enforces both itself and refuses to start when it
# cannot.
resource "google_service_account" "trycrystal_runner" {
  project      = var.project_id
  account_id   = local.trycrystal_runner_service_name
  display_name = "Untrusted Crystal execution identity for trycrystal, intentionally without permissions"
}
