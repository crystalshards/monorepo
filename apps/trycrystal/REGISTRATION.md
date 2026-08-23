# trycrystal registration

This is the wiring checklist for making trycrystal a real deployable on this
stack. It exists because "deployed green while serving nothing" is the default
failure mode here: several registrations are hand-written steps in
deploy.yml, and terraform cannot notice one missing.

The stack on this branch is Google Cloud Run with a shared global external
Application Load Balancer. There is no Kubernetes, no per-app terraform
directory, and no Cloud Run Job per request. Apps are registered by adding
entries to locals maps and workflow matrices, not by authoring resource files.

## What was registered

### Terraform

| Registration | File | Symptom if missed |
|---|---|---|
| `trycrystal` in `public_apps` | `terraform/locals.tf` | No site map entry, so no load balancer backend, no certificate, no DNS records. A Cloud Run service exists that nothing routes to. |
| `trycrystal` deliberately NOT in `database_apps` | `terraform/locals.tf` | Being wrongly present provisions a fifth Cloud SQL database, role and connection secret nothing connects to. Being wrongly absent elsewhere would stop migrations. |
| `trycrystal = "trycrystal.org"` in `site_domains` | `terraform/locals.sites.tf` | Plan fails on the missing key, which is the intended loud failure rather than a quiet one. |
| `trycrystal = "trycrystal-org"` in `site_dns_zones` | `terraform/locals.sites.tf` | Plan fails on the missing key. |
| `trycrystal` entry in `app_config` | `terraform/modules/services/locals.tf` | No service, no service account, no invoker grant, no image reference. `public_apps` naming a slug with no `app_config` entry fails the plan, by design. |
| `database = false` on the trycrystal entry | `terraform/modules/services/locals.tf` | True would add a Cloud SQL socket volume, a migration Job and a cloudsql.client grant to a service designed to hold no database. |
| `trycrystal` in `serving_apps` derivation (from `app_config` keys) | `terraform/modules/services/locals.tf` | Missing identity, invoker grant or SECRET_KEY_BASE secret; the first revision never reaches Ready. |
| Runner locals (service name, audience, image, env) | `terraform/modules/services/locals.tf` | The app and the runner drift on the audience string and every call from the console is a 403 with nothing visibly wrong in either service. |
| Runner variables (sizing, timeout, port, health path, concurrency) | `terraform/modules/services/variables.tf` | Defaults only; the concurrency validation is the load-bearing one, see the confinement section below. |
| Runner service account | `terraform/modules/services/resource.google_service_account.trycrystal_runner.tf` | Any IAM binding added here is a permission held by whoever submits a lesson. It ships with zero, like docs-build. |
| Runner Cloud Run service | `terraform/modules/services/resource.google_cloud_run_v2_service.trycrystal_runner.tf` | No execution backend: the console's RUNNER_URL points at nothing and every submission fails. |
| Runner invoker IAM (trycrystal app SA only) | `terraform/modules/services/resource.google_cloud_run_v2_service_iam_member.trycrystal_runner_invoker.tf` | Without it the app gets 403 on every submission. With an allUsers grant instead, an arbitrary code execution endpoint becomes anonymously callable. |
| `trycrystal_runner_service` module and root outputs | `terraform/modules/services/outputs.tf`, `terraform/outputs.tf` | The release job cannot roll the runner image. CI's deploy-output wiring check fails first, which is the point of that check. |
| `database_backed_hostnames` root output | `terraform/outputs.tf` | The smoke job cannot tell which apexes should report a healthy database. |
| `trycrystal-org` managed zone | `terraform/modules/dns/resource.google_dns_managed_zone.trycrystal_org.tf` | A records fail to create; the certificate never validates; the domain never resolves. |
| `trycrystal` in `zones_by_site` | `terraform/modules/dns/locals.tf` | Zone outputs miss the new zone; the nameservers to delegate at the registrar are not reported anywhere. |
| Zone in the A record `depends_on` list | `terraform/modules/dns/resource.google_dns_record_set.a.tf` | Ordering only, but a first apply could race its own records. |
| Edge module | nothing to edit | Certificates, URL map host rules, serverless NEGs and backends are all derived from `local.sites` in `terraform/locals.sites.tf`. This is why the site is registered there once rather than in four places. |

### Workflows

| Registration | File | Symptom if missed |
|---|---|---|
| `trycrystal` in the test matrix | `.github/workflows/ci.yml` | The app ships untested; CI passes because it never ran. |
| `database: false` flag on the matrix entry | `.github/workflows/ci.yml` | With the old unconditional build, CI fails trying to compile `src/migrate.cr`, which trycrystal does not have. With a file-existence skip instead of a flag, a database app that loses its migrator would ship silently uncompiled. |
| `trycrystal` image in the build matrix | `.github/workflows/deploy.yml` | The build job's context assertion fails the deploy loudly. If removed along with that assertion: the service is created by terraform pointing at a tag nobody pushed, and the first revision never starts. |
| `trycrystal-runner` image in the build matrix | `.github/workflows/deploy.yml` | Same as above for the runner: CrashLoopBackOff on the first apply, or worse, a stale image serving forever after the first deploy. |
| `trycrystal` in the release roll loop | `.github/workflows/deploy.yml` | THE IMAGE TRAP. Every service carries `lifecycle { ignore_changes = [template[0].containers[0].image, ...] }`, so terraform sets the image once at creation and CI owns every roll after that. The roll steps are a hand-written literal list, not a loop over a terraform output. A deployable missing from that list deploys green forever on its creation image. This is why the loop, not the terraform, is the registration that matters. |
| Runner roll after the loop | `.github/workflows/deploy.yml` | Same trap, second deployable. The runner is NOT in the `services` output (that map feeds the load balancer's backends and the runner must never sit behind the load balancer), so it cannot ride the loop. It gets its own `roll` call, with the same `assert_serving` proof: Ready, 100 percent of traffic on the new revision, and the revision's image digest matching the tag this run pushed. |
| `trycrystal_runner_service` and `database_backed_hostnames` in the infra outputs map and emits | `.github/workflows/deploy.yml` | Empty values downstream. `emit_raw` refuses an empty output by name, and `.github/deploy_outputs_test.sh` (run in CI) fails the missing wiring before any deploy. |
| Hostname count expectation raised to ten | `.github/workflows/deploy.yml` | The smoke job would accept a truncated hostname list; a silently dropped hostname is a routing hole the count check exists to catch. |
| Database health assertion made conditional on `database_backed_hostnames` | `.github/workflows/deploy.yml` | Unconditional, it fails every deploy of trycrystal.org, which reports no database because it has none. Emptied, it silently stops asserting database health for the four sites that do have one; the count check on the list guards that side. |
| trycrystal identities and services in the migrate bootstrap's adoption lists | `.github/workflows/deploy.yml` | A partial first apply that creates the trycrystal service, the runner service or either service account without recording it in state leaves every later deploy dying on `Error 409: already exists`. The adoption step exists to self-heal exactly that; a deployable missing from it is unrecoverable without hand state surgery. |
| `runner-confinement` job running the confinement proof on Linux | `.github/workflows/ci.yml` | The proof exists and nothing runs it, so the runner's confinement is asserted by a document rather than by a check. A defect in the seccomp filter, the uid drop or the environment scrub reaches production green. |
| The gate on that job's own summary line | `.github/workflows/ci.yml` | THE SECOND SILENCE. `crystal spec` exits 0 when every example is PENDING, and this spec pends itself when docker or the image is missing. Verified locally: one passing plus one pending example prints "2 examples, 0 failures, 0 errors, 1 pending" and exits 0. Without parsing the counts, a job that tested nothing is indistinguishable from a job that proved everything. |
| `trycrystal` and `trycrystal-runner` in the image scan matrix | `.github/workflows/security.yml` | The two newest images, one of which executes hostile input by design, get no Trivy or Scout scan. The matrix also had to gain a `context` per entry, because the runner is not at `apps/<name>`. |
| trycrystal and the runner in local dev | `Makefile`, `docker-compose.yml` | A developer cannot run the console at all, or runs it against no sandbox and sees every lesson fail. `APPS` gained trycrystal while a new `DB_APPS` keeps `services`, `migrate`, `seed` and `reset` on the four database apps, so no trycrystal database is ever created. `make dev` starts the runner with the exact-string waiver and hands only trycrystal its `RUNNER_URL`. |
| An explicit `dockerfile` on every build matrix entry, and `file:` on the build action | `.github/workflows/deploy.yml` | THE WRONG IMAGE UNDER THE RIGHT TAG. The runner deploys from `Dockerfile.interpreter`, which sits in the same context as the run-mode `Dockerfile`. Defaulting to `<context>/Dockerfile` builds and pushes the run-mode image under the runner's tag: the service reaches Ready, containment still holds, every submission is four to six times slower, and nothing anywhere says why. The context assertion checks the declared path for the same reason. |
| The confinement proof pointed at the interpreter image | `.github/workflows/ci.yml` | Proving containment on an image that does not ship is theatre. The interpreter's compile phase is a different code path from `crystal run` and macros still execute there, so the filter and the rlimits have to be proven binding on that path. |
| The baked-mode assertion on the built image | `.github/workflows/ci.yml` | An interpreter image that lost `RUNNER_EXEC_MODE=i` would pass every containment assertion while silently running run mode. The step reads the value out of `docker image inspect` and fails unless it is `i`; verified against the real image, which reports `i`. |
| `Dockerfile.interpreter` as the runner's scanned image | `.github/workflows/security.yml` | The scanned image would be one production does not run. The interpreter image is the larger surface: Crystal built from source with the interpreter enabled, plus Alpine's LLVM 20 runtime libraries. |

### Cost of the interpreter image, measured

`docker build --no-cache -f Dockerfile.interpreter` took 623s (10m23s) on an
M5 Max, exit 0. Runner measured the `make crystal interpreter=1 release=1`
step inside it at about 335s, and a warm rebuild with the toolchain stage
cached at 68s. A GitHub-hosted runner has 4 vCPU, so CI should be expected to
take materially longer than 623s on a cold build. That is an inference from
the core count, not a measurement.

Both affected jobs now carry a 90 minute ceiling instead of 45. The deploy
build has a GitHub Actions cache scoped per context, and the toolchain stage
depends only on the base image and the pinned Crystal tag, so it should hit on
nearly every run. The confinement job is deliberately uncached: it proves the
boundary of the image as built from the tree, and a cache is one more thing
that can serve a stale answer to a security proof. If that cost proves
unacceptable on every commit, the fix is a separately tagged prebuilt
toolchain base this Dockerfile can `FROM`, not dropping the proof; note that
moves the compiler out of the per-commit proof path.

## The image trap, precisely

Measured in this tree, not inferred from memory:

- `terraform/modules/services/resource.google_cloud_run_v2_service.apps.tf` carries
  `lifecycle { ignore_changes = [template[0].containers[0].image, client, client_version] }`.
- `resource.google_cloud_run_v2_service.trycrystal_runner.tf` (new) carries the same.
- The release job's service loop is a literal list,
  `.github/workflows/deploy.yml` "Deploy service revisions":
  `for app in crystalshards crystaldocs crystalgigs crystalbits trycrystal`.
- Every long-lived Job has its own hand-written `gcloud run jobs update`
  step, each with a read-back that the template actually holds the image.

So "registered in terraform" is necessary and not sufficient. Both deployables
are registered in every place that rolls an image: the five-app loop for the
console, and a dedicated roll call for the runner.

## Confinement posture of the deployment

The runner deployment follows the docs-build precedent on this stack, which is
the existing untrusted-execution design: an identity with zero IAM bindings,
everything it needs arriving in the request and leaving in the response.

Platform provides: gVisor sandbox per instance, CPU and memory caps, request
timeout, min and max instances, and the IAM gate (only the trycrystal app's
identity holds run.invoker).

Platform does NOT provide, and the runner process enforces itself: egress
denial, non-root uid, environment allowlist, rlimits, per-execution wall clock
and process-group kill, scratch wipe, recycle-after-N executions. The runner
refuses to start when its confinement is unconfigured; the opt-out is the
exact string `ALLOW_UNSAFE=true`, which terraform never sets.

The stated gap, rather than a hidden one: concurrent submissions on one
instance share a uid, and kill(2) between siblings is not denied by the
sandbox's filters. That is a denial of service on one warm instance, not
exfiltration. It is closed by pinning concurrency to 1
(`trycrystal_runner_concurrency` validates exactly that) and scaling on
instances. If concurrency is ever raised, the runner needs per-execution uid
isolation first; see `apps/trycrystal/sandbox/VERIFICATION.md` for the full
platform-versus-runner analysis.

## Sizing

The runner's defaults in `terraform/modules/services/variables.tf` are
`cpu = "2"`, `memory = "4Gi"` on Runner's preliminary floor: `crystal run`
peak memory with stdlib requires, and sub-two-second compiles on the real
image. These are Runner's numbers, to be replaced by its measured figures
before launch; the variables exist so that replacement is a value change and
not a resource edit.

## Not done, and outside code

1. Registrar nameserver delegation for trycrystal.org. The zone
   `trycrystal-org` is created by terraform with DNSSEC on, and its
   nameservers are reported by `terraform output dns_name_servers` once
   applied. Until those nameservers are set at the registrar for the apex,
   nothing under trycrystal.org resolves, the managed certificate for both
   hostnames stays PROVISIONING, and the smoke job correctly defers them.
   The deploy is green through this period; the domain is dark.
2. The DNSSEC DS record, published at the registrar ONLY AFTER delegation is
   confirmed resolving. This ordering is not stylistic. A DS record that does
   not match the serving zone's keys makes the entire domain SERVFAIL, not
   just the new records, for every validating resolver. Delegate, confirm
   resolution (for example `dig trycrystal.org NS` answering with the zone's
   nameservers, and the apex A record resolving to the load balancer), then
   publish the DS from the zone's key record and re-verify with a validating
   resolver.
3. Search Console, if wanted. trycrystal is deliberately excluded from
   `search_console_properties` in `terraform/module.services.tf` because the
   property is only half the wiring: a human must register
   `sc-domain:trycrystal.org` and add `trycrystal@<project>.iam.gserviceaccount.com`
   as a Restricted user on it. The terraform entry and the human steps should
   land together.
