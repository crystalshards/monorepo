# trycrystal.org

A guided, in-browser Crystal tutorial in the spirit of the original tryruby.org: a console
that talks back, lessons that build on each other, no signup, an answer in under a second.

This document is the contract the implementation is held to. It records what was measured,
what was decided, and which tradeoffs are accepted rather than solved.

## 1. Product shape

Not a blank playground. A lesson-driven console:

- The user types one submission at a time and gets a response with personality.
- Lessons advance when the user's submission satisfies the lesson's expectation.
- Progress lives in the browser (localStorage). No accounts, no database read on the hot path.
- Every lesson is completable without leaving the keyboard.

## 2. Execution mode: compile and run, measured honestly

An earlier draft of this document claimed `crystal i` (the interpreter) at 401 ms and made
it the basis of the whole design. That was wrong, and the way it was wrong is worth
recording: the 401 ms was the **error path**. No official Crystal distribution ships the
interpreter, because it is a compile-time option (`make crystal interpreter=true`). Every
image tested (`crystallang/crystal:1.21.0`, the `-alpine` variant, `nightly`) and this
workstation's own toolchain answer `crystal i` with "Crystal was compiled without
interpreter support" and exit 1. On this machine that refusal takes 0.064 s. Something
timed a failure and reported it as speed.

Verified numbers, Crystal 1.18.2 on an M5 Max, three runs each:

| Mode | Trivial | With `require "json"` and `require "http/client"` |
|---|---|---|
| `crystal run` | 1.37 s cold, then 0.71 / 0.66 | 1.31 s cold, then 1.08 / 1.08 |
| `crystal build` (compile only) | 0.58 / 0.52 | n/a |
| exec already-compiled binary | 0.17 / 0.00 | n/a |

Decision: `crystal run`. Sub-second for a trivial submission and about a second with stdlib
requires is enough for a console that answers a submission, which is what the original
tryruby actually was. It needs no custom toolchain.

The interpreter is a phase 2 optimization, not a prerequisite. Adopting it means building
Crystal from source with `interpreter=true`, and it must be re-measured against a build that
actually has it rather than against a refusal.

Note that the compiled binary itself runs in effectively no time, so nearly all of the cost
is compilation. A build-then-exec split is the obvious later optimization. Phase 1 does not
do it.

Those are workstation figures. The deployed numbers are worse, and this is the number that
matters because it is the one a visitor experiences.

Measured through the production console at `trycrystal.org/api/executions`, pinned to the
load balancer, interpreter mode, warm:

| | wall clock | runner duration_ms |
|---|---|---|
| first submission after deploy | 2.95 s | 2499 |
| `1 + 1`, three consecutive runs | 1.74 to 1.87 s | 1584 / 1692 / 1619 |

So production is roughly three times the 544 to 621 ms measured in the same image locally.
The image and the execution mode are identical, so the difference is the platform: an M5 Max
core against whatever CPU allocation the Cloud Run service holds. This is a real gap against
the sub-second intent, not a rounding error, and the honest lever is the runner's CPU
allocation rather than anything in the code. Raise it and re-measure here before claiming
sub-second in production.

Sandbox cold start remains the other latency risk, which is why the runner is a long-lived
Cloud Run service rather than a container or a Job per request. It is no longer held warm:
`trycrystal_runner_min_instances` is 0, so the first submission after a quiet period pays an
instance start on top of the compile. Section 4 records that decision and what holding the
pool warm actually cost. The first-submission figure above is what a cold path costs *with* a
warm pool configured, which makes it the floor for the cold case rather than a measurement
of it.

### Proven against the deployed service

Confinement was verified in production, not only locally, by submitting hostile code through
the public console. Both attempts returned the seccomp filter's own errno rather than an
ambiguous failure:

- outbound TCP to `1.1.1.1:80`
  -> `BLOCKED: Failed to create socket: Address family not supported by protocol`
- the metadata server at `169.254.169.254`, which mints tokens
  -> `BLOCKED: Failed to create socket: Address family not supported by protocol`

Both returned `exit_code: 0` with real output, so the refusals are not execution breaking.
The metadata case is the one worth naming: on Cloud Run that address is how a process asks
for credentials, so it is the first thing hostile code should try.

## 3. Inline per-line values: deferred, with a known path

`crystal play` (built into the compiler) produces the inline per-line value display that
makes a playground feel alive. Its mechanism, read from upstream source at tag 1.21.0:

- `src/compiler/crystal/tools/playground/agent_instrumentor_transformer.cr` rewrites every
  expression to `_agent.i(line) { expr }`.
- `src/compiler/crystal/tools/playground/agent.cr` opens a **WebSocket back to the server**
  and streams each value as JSON.

Two consequences:

1. The technique is reusable. It is ~8 KB of Apache-2.0 source, and vendoring it is viable.
2. Its transport is incompatible with confinement. The agent's network callback is exactly
   what `--network none` must forbid. If vendored, `Agent#send` gets rewritten to append
   newline-delimited JSON to a file in the output mount. No socket, no egress.

`crystal play` itself is **not** a deployable substrate: upstream ships it with no
confinement at all and it is a local developer tool.

Phase 1 does not vendor the transformer, because it depends on compiler-internal AST APIs.
Phase 1 returns stdout, stderr, and the value of the final expression. Inline per-line
values are phase 2.

## 4. Confinement

Untrusted Crystal runs here, and compiling it executes it. Macros run at compile time, so
a macro that shells out is execution during what looks like "just building". The compile
step and the run step are both hostile territory.


Trust split:

| Phase | Network | Runs user code | Where |
|---|---|---|---|
| serve UI, lesson content | yes | no | `trycrystal` service, has what it needs |
| execute submission | **no** | **yes** | separate runner service, no credentials |

This platform is Cloud Run, so the confinement vocabulary is not Kubernetes'. There is no
securityContext, no capability dropping, no NetworkPolicy, no `runtimeClassName`. What
substitutes, and which side enforces it, is recorded in
`apps/trycrystal/sandbox/VERIFICATION.md`. The properties still required:

- The runner is a **separate deployable** from the web app, following the existing
  `docs-build` precedent for untrusted execution in this repo.
- No credentialed service account. Nothing worth stealing is reachable from it.
- Egress blocked. Ingress restricted so only the web app can reach it, not the internet.
- No secrets and no platform environment variables carrying anything sensitive.
- Per-execution: fresh scratch directory, wall-clock timeout, rlimits for memory and cpu
  time, a process cap, and a process-group kill on expiry so a timed-out submission cannot
  leave a survivor.
- Non-root user, read-only root filesystem where the toolchain permits it.
- Instances recycle after a bounded number of executions.
- The runner **refuses to start** when confinement is unconfigured. The opt-out is the
  exact string `ALLOW_UNSAFE=true`, not any truthy value.

### Accepted tradeoff, stated plainly

A long-lived instance means consecutive submissions from different users can share one. That
is weaker than an instance per execution, and it is chosen for latency, because compilation
already costs most of the budget. It is made survivable by the instance holding nothing worth
stealing, by concurrency 1 so there are never sibling submissions on it, and by recycling
after a bounded number of executions. It is not equivalent to per-request isolation and this
document does not claim it is.

This tradeoff does not come from the warm pool and did not leave with it. `min_instances = 0`
removes the instance that waits, not the instance that serves: a submission arriving while a
previous one's instance is still up still lands on it.

### Warm pool: chosen, priced, withdrawn

The runner was specified as a warm pool, `min_instances = 1`, and that was a deliberate
choice rather than an oversight. A cold started instance boots the toolchain before it can
answer anything, and this tutorial is built around an answer in under a second. Sections 2
and 4 were both written on that basis.

It is 0 now, because the choice was priced against traffic that never arrived. One warm
instance at the runner's CPU and memory, with `cpu_idle` false so CPU is billed
continuously, was measured at $115.63 a month against 10 lifetime requests to the runner.
That is not a latency budget, it is a subscription to an empty room, and it was the second
largest line on the bill.

What that costs, plainly: the first submission after a quiet period pays an instance start
while the toolchain boots, so the tutorial's opening interaction is slow for that visitor. At
ten lifetime requests essentially every submission is that visitor, which reads like an
argument for pinning the pool warm and is the opposite. There is nobody here to keep warm
for.

What would justify going back to 1: sustained runner traffic where the gap between
submissions is routinely shorter than Cloud Run's idle window, so a warm instance is serving
rather than waiting. Concretely, enough requests per day that the instance would be up
anyway, which turns `min_instance_count` into a latency guarantee instead of a floor on the
bill. Until the runner's own request count shows that, this stays at 0.

The value itself lives on `trycrystal_runner_min_instances` in
`terraform/modules/services/variables.tf`, and the same reasoning is recorded in that
variable's description. If the two ever disagree, the variable is the one that ships.

## 5. Proof obligations

Not done until these pass:

1. A hostile fixture, executed through the real runner path, writes probe results showing:
   canary env var unreadable, network blocked, host file unreachable, uid non-zero,
   root filesystem read-only, **and real output still produced** so the test cannot pass
   merely because execution broke.
2. Missing probe files fail loudly. A helper returning empty string for a missing file
   would make every negative assertion pass vacuously.
3. The same fixture run unsandboxed as a negative control, confirming it leaks. A
   containment test that cannot fail proves nothing.
4. One lesson completed end to end in a real browser against the real runner.

## 6. Deployment surface

Infrastructure is Google Cloud Run. Public apps are produced from a locals map in
`terraform/modules/services/locals.tf` and sit behind a load balancer via serverless NEGs
with `INTERNAL_AND_CLOUD_LOAD_BALANCING` ingress.

An earlier draft of this document claimed GKE with an Envoy Gateway and no image trap. That
was read from a checkout 91 commits stale and was wrong in both particulars. Corrected:

- The image trap is REAL here. Every service and Job carries
  `lifecycle { ignore_changes = [...containers[0].image, client, client_version] }`.
  `locals.tf` says outright that terraform sets the image once and CI rolls subsequent tags.
  A new deployable whose image CI never explicitly rolls deploys green and never updates.
  Both deployables, the web app and the runner, must be registered wherever images roll.
- A precedent for confining untrusted execution already exists in this repo. The
  `docs-build` Job is described in its own comments as the untrusted documentation build,
  dispatched by the `docs-launcher` service through Cloud Tasks with OIDC, with narrowly
  scoped IAM (one service account whose permission list is exactly `["run.jobs.run"]`).
  Building a shard's docs runs that shard's macros, so it is the same threat. The runner
  follows this precedent rather than inventing a parallel mechanism.

Because this is Cloud Run rather than Kubernetes, section 4's confinement is enforced
differently: there is no securityContext, no capability dropping, and no NetworkPolicy. The
substitutes are the absence of a credentialed service account, ingress restriction, egress
settings, request timeout, instance concurrency, and process-level limits the runner imposes
on itself. Which properties come from the platform and which the runner must enforce is
recorded in `apps/trycrystal/sandbox/VERIFICATION.md`.

`trycrystal.org` is a new apex domain, so unlike the existing apps it needs a new Cloud DNS
managed zone and its own hostname attachment. Registrar delegation order matters: delegate
nameservers and confirm resolution first, publish the DNSSEC DS record second. Publishing a
DS record that does not match the serving zone breaks the whole domain.

Toolchain note: the existing apps and this workstation may pin different Crystal versions.
The runner image version must be chosen deliberately, since the version the user's code
runs against is a product decision, not an accident of the build host.

## 7. Open, and owned by Jason

- Art direction and the console's voice. The joy is the product here, and inventing his
  taste is not this document's job.
- Accepting the section 4 tradeoff.
