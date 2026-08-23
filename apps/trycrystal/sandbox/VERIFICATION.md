# trycrystal runner confinement: what is proven, and by what

This document is the confinement proof record for the trycrystal runner. The
executable proof lives in `apps/trycrystal/runner/spec/confinement_spec.cr`
(run from `apps/trycrystal/runner` with
`crystal spec spec/confinement_spec.cr`; it requires docker), and the hostile
submission it executes is
`apps/trycrystal/runner/spec/fixtures/hostile_submission.cr`. This file
records what that spec demonstrates, what it cannot, and which properties
come from the platform versus from the runner process itself. It follows
DESIGN.md section 5 (proof obligations) and section 4 (confinement).

The platform is Cloud Run, not Kubernetes. An earlier draft of this slice
produced Kubernetes manifests; that was wrong for this repository's
infrastructure and they were discarded. Cloud Run offers no securityContext,
no capability drop, and no NetworkPolicy, so most of the confinement the
DESIGN requires must be enforced by the runner process. That split is section
3 below and is the crux of this document.

## 1. The precedent: what the docs_build sandbox actually guarantees

An untrusted-execution sandbox already exists in this repository:
`google_cloud_run_v2_job.docs_build` compiles third party shards, which means
executing stranger-authored macros, which is the same threat the trycrystal
runner faces. What it guarantees, by file and line:

**Identity and IAM scope.** The Job runs as a service account described as
"intentionally without permissions"
(`terraform/modules/services/resource.google_service_account.docs_build.tf:23-26`).
The docs-launcher, the only thing that starts it, holds
`roles/run.jobsExecutorWithOverrides` bound on that one Job and nowhere else
(`terraform/modules/services/resource.google_cloud_run_v2_job_iam_member.docs_launcher_runs_docs_build.tf`,
role at line 21); the role is exactly three permissions, and the file's
comment explains why the next role up (run.developer) would let the launcher
rewrite what the Job runs. The scheduler that starts the related discovery
Job holds a custom role whose permission list is literally
`["run.jobs.run"]`
(`terraform/modules/scheduler/resource.google_project_iam_custom_role.run_job.tf:38`).
The pattern: the untrusted executor's identity holds zero bindings, and every
caller's authority is enumerated to the permission.

**Environment and secret exposure.** The Job's environment carries no
secrets, no database, no Cloud SQL volume and no bucket names
(`resource.google_cloud_run_v2_job.docs_build.tf:8-11`). Its only inputs are
two per-execution signed URLs delivered as execution overrides, minted by the
launcher and expiring in minutes; the container cannot choose where they
land (`apps/docs-build/entrypoint.sh:9-19`). Inside the container, the
untrusted compile is execed through `env -i` so it inherits nothing, and the
signed URLs never cross into it (`apps/docs-build/entrypoint.sh:235-236`,
`:273-282`). `no-egress` additionally refuses to start if a `DOCS_`
capability-bearing variable is present in its own environment
(`apps/docs-build/sandbox/no-egress.c:421-459`).

**Egress.** Not arranged by terraform and explicitly could not be:
"THERE IS DELIBERATELY NO vpc_access BLOCK, AND NO EGRESS SETTING"
(`resource.google_cloud_run_v2_job.docs_build.tf:23`), because a Cloud Run
egress setting is a property of the whole task (the task's own fetch and
upload phases need the network), and because no egress setting covers
169.254.169.254: the metadata server is answered inside the sandbox and never
traverses a VPC (`:25-33`). The denial is in the image instead: the compile
runs under `no-egress`, a seccomp filter the process installs on itself,
which survives execve and has no removal interface
(`apps/docs-build/sandbox/no-egress.c:1-36`). socket(2) and socketpair(2)
are restricted to AF_UNIX and AF_NETLINK; io_uring is denied outright
(IORING_OP_SOCKET bypasses a socket-only filter, `no-egress.c:20-26`,
`:84-90`); ptrace and process_vm_readv/writev are denied. The filter is
proven in-process on every run before the exec, by exact errno, and an
unprovable confinement is a failed build rather than an unconfined one
(`no-egress.c:276-341`).

**Filesystem writability.** The untrusted compile runs as uid 1000 while the
supervisor stays root; everything on PATH is root-owned, so nothing the
compile can write is anything the later upload phase runs
(`apps/docs-build/Dockerfile:44-66`, especially the `adduser -D -u 1000
builder` at line 60 and the "No USER line" rationale at lines 68-71). The
same uid split is what closes `/proc/1/environ` and `/proc/1/mem` to the
compile (`no-egress.c:44-50`).

**Execution timeout.** The Job's task `timeout` is
`local.docs_build_timeout` (`resource.google_cloud_run_v2_job.docs_build.tf:55`),
`max_retries = 0` because the Cloud Tasks queue already owns retry policy
(`:26-31`), and the application side enforces an ordering: the sandbox must
give up strictly before the launcher's deadline or a slow build orphans
(`apps/crystalshards/src/services/docs_sandbox.cr`,
`DocsSandbox.timeout_seconds` and `TimeoutOrdering`).

**Whether one execution can observe another.** Each build is a fresh Job
execution: `parallelism = 1`, `task_count = 1`, a new container per build, a
per-build scratch directory, and per-build signed URLs
(`resource.google_cloud_run_v2_job.docs_build.tf:51-53` plus the entrypoint's
per-execution `mktemp` workdir). Two builds share nothing but the image. The
docs sandbox's own containment spec proves all of this with the same
negative-control discipline this slice copies
(`apps/crystalshards/spec/services/docs_sandbox_containment_spec.cr`).

## 2. Reusable for interactive per-submission execution? No.

The docs_build mechanism is batch, and the reasons it works are the reasons
it cannot serve a console that answers in under a second:

- A Cloud Run Job execution is a container start: image resolution, container
  boot, then our compile. The measured budget for the whole interaction is
  about one second (`crystal run` warm on this M5 Max: 0.71s and 0.66s for a
  trivial submission, 1.08s with stdlib requires, Main's three-run
  measurements after the interpreter correction). A Job per submission spends
  its entire budget before the compiler is even running. This is not
  measurable locally without deploying, and I am not asserting a number for
  it; the structural argument stands on its own.
- The docs_build design leans on per-execution identity handoff (signed URLs,
  fresh container, a supervisor that outlives one build). A warm interactive
  service cannot mint a fresh container per submission without becoming the
  batch design again.
- The launcher/queue architecture (Cloud Tasks dispatch, request held open
  for the whole build) is built for throughput on minutes-long work, not
  latency on sub-second work.

**The interactive variant, which is what the runner implements:** a dedicated
Cloud Run SERVICE, warm (`min_instances = 1`), whose identity holds zero IAM
bindings, no secrets, no volumes; ingress is IAM-gated (only the trycrystal
app's service account holds run.invoker, the docs-launcher precedent of
ingress ALL plus IAM rather than internal ingress); each submission executes
in-process through a trampoline that does setsid, setrlimit, fd-close, an
environment allowlist, and installs the no-egress seccomp filter before
exec, proven in-child before the compiler starts; a fresh scratch directory
per execution, wiped after; instance and runner concurrency 1 (pinned by a
terraform validation until per-execution uid isolation exists); the process
self-exits after a bounded number of executions and Cloud Run replaces the
instance, which is the recycle property. This is Runner's design, recorded
here because the proof obligations are against it.

## 3. Platform-provided versus self-enforced

On Cloud Run we control none of securityContext, capabilities, or
NetworkPolicy. What actually substitutes:

| Property | Provided by | Where it comes from |
|---|---|---|
| Kernel isolation from host and other instances | Platform | gVisor sandbox per instance (Gen2 execution environment, `docs_build.tf:57` precedent) |
| CPU / memory ceiling per instance | Platform | Cloud Run resources limits (deploy config; hard cap) |
| Request ceiling | Platform | Cloud Run request timeout on the service |
| Warm pool size / fleet cap | Platform | `min_instances` / `max_instances` |
| Who may call the runner at all | Platform | IAM run.invoker on exactly the app's service account (docs-launcher precedent: ingress ALL, IAM is the gate) |
| No ambient authority to Google APIs | Platform + config | Service account with zero IAM bindings; the platform still mints tokens at the metadata server, which is why egress denial must ALSO cover 169.254.169.254 (it is answered inside the sandbox; no egress setting reaches it) |
| Egress denial (internet, DNS, metadata, AF_VSOCK) | **Us, in-process** | seccomp filter installed by the trampoline before exec, ported from `apps/docs-build/sandbox/no-egress.c`; survives execve, no removal interface, proven in-child by exact errno |
| Non-root execution | **Us** | Cloud Run runs the image's USER and an image with no USER line runs as root; there is no runAsNonRoot knob. The runner image pins uid 10001 for server and submissions alike (`apps/trycrystal/runner/Dockerfile`, `adduser -D -u 10001 runner` plus `USER 10001`), and confined boot refuses outright when it finds itself uid 0 (`src/main.cr`, `confine_self_checks`) |
| Capability drop / no privilege escalation | **Us** | non-root uid leaves CapEff empty; the trampoline sets no_new_privs so a setuid binary cannot regain privilege |
| System paths read-only to submissions | **Us** | not a read-only filesystem (Cloud Run's container fs is writable in-memory); root-owned paths are unwritable because the submission is uid 10001 |
| Environment hygiene | **Us** | boot-time exec-scrub of the server environment (execve replaces the kernel env area; clearenv does not) plus a per-execution allowlist (PATH, HOME, TMPDIR, TERM, CRYSTAL_CACHE_DIR) |
| PID / fd / file-size / address-space ceilings | **Us** | setrlimit in the trampoline (NPROC, NOFILE, FSIZE, AS, CPU); the platform does not cap pids per container |
| Per-submission wall clock | **Us** | trampoline timeout with process-group kill (setsid); the platform's request timeout is per request, not per submission |
| Scratch freshness | **Us** | fresh directory per execution under the scratch root, wiped after |
| Recycle after bounded executions | **Us** | runner self-exits after N executions; Cloud Run replaces the instance, min_instances keeps the pool warm |
| No sibling submissions on one instance | Config, pinned | concurrency 1 enforced by terraform validation on the runner service until per-execution uid isolation exists |

The load-bearing line in that table is egress: **the platform cannot deny
egress to a Cloud Run container**, and the metadata server that mints tokens
for the (otherwise empty) service account is reachable from inside the
sandbox no matter what VPC settings exist. The in-process seccomp filter is
not defense in depth on this platform; it is the boundary.

## 4. What is proven locally

Machine: macOS host (OrbStack 29.4.0 docker, Linux VM), M5 Max. Everything
below was run from `apps/trycrystal/runner`. The whole spec passes: 5
examples, 0 failures, 0 errors, 0 pending, with the service legs pointed at
the runner image via `TRYC_RUNNER_IMAGE=trycrystal-runner:dev`. Without that
variable and without a built image the two service examples report
`pending!` with a stated reason rather than passing quietly.

### The mechanism layer

The spec proves the confinement primitives on the docs-build substrate
(`trycrystal-proof:substrate`, built from `apps/docs-build`) with `crystal
run`, in docker on a Linux kernel, with the container's network UP the whole
time, because the production platform cannot remove the network either. Two
legs, identical in every dimension except confinement: same image, same
fixture, same machine, same network, same supervising pid 1 holding the
canary `TRYC_CANARY=canary-must-not-escape`. The confined leg adds exactly
three things: `env -i` (scrub), `no-egress --user 1000:1000` (filter + uid),
and a scratch HOME/TMPDIR/cache.

Unconfined leg (negative control), verbatim:

```
PROBE macro-env: LEAKED
PROBE macro-net: REACHABLE
PROBE macro-proc1: READABLE
LESSON_OK sum=20 hello from crystal, visitor
PROBE runtime-env: LEAKED
PROBE runtime-net: REACHABLE
PROBE runtime-metadata: REFUSED (IO::TimeoutError: Connect timed out)
PROBE runtime-dns: RESOLVED
PROBE runtime-proc1env: READABLE+CANARY-FOUND
PROBE runtime-proc1mem: OPEN-UNREADABLE (IO::Error)
PROBE runtime-uid: uid=0
PROBE runtime-rootfs: WRITABLE-root
PROBE runtime-rootfs-etc: WRITABLE-etc
PROBE runtime-caps: CapEff: 00000000a80425fb | NoNewPrivs: 0 | Seccomp: 2
```

Confined leg (same fixture, same canary on the same pid 1), verbatim:

```
no-egress: verified in-process as uid 1000, ip and vsock sockets denied, io_uring denied, no_new_privs set
PROBE macro-env: scrubbed
PROBE macro-net: REFUSED
PROBE macro-proc1: REFUSED
LESSON_OK sum=20 hello from crystal, visitor
PROBE runtime-env: scrubbed
PROBE runtime-net: REFUSED (Socket::Addrinfo::Error: Hostname lookup for example.com failed: Address family not supported by protocol)
PROBE runtime-metadata: REFUSED (Socket::Error: Failed to create socket: Address family not supported by protocol)
PROBE runtime-dns: REFUSED (Socket::Addrinfo::Error)
PROBE runtime-proc1env: REFUSED
PROBE runtime-proc1mem: REFUSED
PROBE runtime-uid: uid=1000
PROBE runtime-rootfs: root-refused
PROBE runtime-rootfs-etc: etc-refused
PROBE runtime-caps: CapEff: 0000000000000000 | NoNewPrivs: 1 | Seccomp: 2
```

What the pair establishes, probe by probe:

- **Canary env**: LEAKED at both macro and run time unconfined; scrubbed in
  both places confined. The scrub (`env -i`) is what removes it; the spec
  asserts the exact values, and a missing PROBE line is a hard failure (see
  the fail-loud section below), so neither leg can pass on an execution that
  never ran. LESSON_OK appears in BOTH legs: the confined leg demonstrably
  still compiles and executes real Crystal.
- **Network**: REACHABLE both boundaries unconfined; REFUSED both boundaries
  confined, and the runtime refusals carry "address family not supported",
  which is the seccomp filter's own errno for a denied address family. That
  exact errno is the difference between "we denied it" and "it would have
  failed anyway"; the metadata probe in the leak leg shows why that rigor
  matters (it reads REFUSED with a connect timeout there, because no metadata
  server exists on a local docker network: the socket was created fine).
- **Supervisor**: `/proc/1/environ` READABLE+CANARY-FOUND unconfined (same
  uid as pid 1); REFUSED confined (uid 1000 under a root pid 1). `/proc/1/mem`
  likewise refuses under the uid split.
- **uid**: 0 unconfined, 1000 confined.
- **Root filesystem**: writable at `/` and `/etc` unconfined; refused at both
  confined, by the non-root uid (the filesystem itself is writable; that is
  the platform shape and the uid is the control).
- **Kernel account**: CapEff nonzero / NoNewPrivs 0 unconfined; CapEff all
  zero / NoNewPrivs 1 / Seccomp 2 confined, read from `/proc/self/status` by
  the submission itself.

### The service layer: the real runner path

The whole spec, including both service legs, passes against
`trycrystal-runner:dev`:

```
$ TRYC_RUNNER_IMAGE=trycrystal-runner:dev crystal spec spec/confinement_spec.cr
.....
Finished in 1:28 minutes
5 examples, 0 failures, 0 errors, 0 pending
```

Both legs POST the same hostile submission to `/execute` on the same image,
differing only in the boot mode (`TRYC_SANDBOX=cloudrun` versus exactly
`ALLOW_UNSAFE=true`; the runner refuses to boot if handed both). Response
envelope and probes, verbatim:

```
confined:  exit_code=0 timed_out=false value="confinement-proof-complete"
PROBE macro-env: scrubbed
PROBE macro-net: REFUSED
PROBE macro-proc1: READABLE
LESSON_OK sum=20 hello from crystal, visitor
PROBE runtime-env: scrubbed
PROBE runtime-net: REFUSED (Socket::Addrinfo::Error: Hostname lookup for example.com failed: Address family not supported by protocol)
PROBE runtime-metadata: REFUSED (Socket::Error: Failed to create socket: Address family not supported by protocol)
PROBE runtime-dns: REFUSED (Socket::Addrinfo::Error)
PROBE runtime-proc1env: READABLE
PROBE runtime-proc1mem: OPEN-UNREADABLE (IO::Error)
PROBE runtime-uid: uid=10001
PROBE runtime-rootfs: root-refused
PROBE runtime-rootfs-etc: etc-refused
PROBE runtime-caps: CapEff: 0000000000000000 | NoNewPrivs: 1 | Seccomp: 2

unsafe:    exit_code=0 timed_out=false value="confinement-proof-complete"
PROBE macro-env: scrubbed
PROBE macro-net: REACHABLE
PROBE macro-proc1: READABLE
LESSON_OK sum=20 hello from crystal, visitor
PROBE runtime-env: scrubbed
PROBE runtime-net: REACHABLE
PROBE runtime-metadata: REFUSED (IO::TimeoutError: Connect timed out)
PROBE runtime-dns: RESOLVED
PROBE runtime-proc1env: READABLE+CANARY-FOUND
PROBE runtime-proc1mem: OPEN-UNREADABLE (IO::Error)
PROBE runtime-uid: uid=10001
PROBE runtime-rootfs: root-refused
PROBE runtime-rootfs-etc: etc-refused
PROBE runtime-caps: CapEff: 0000000000000000 | NoNewPrivs: 0 | Seccomp: 2
```

What this pair does and does not establish, precisely:

- **Egress is denied in the runner, at both boundaries, and the refusal is
  ours.** Confined: the macro-time fetch is REFUSED and the runtime socket
  attempts fail with "Address family not supported by protocol", the errno
  the filter itself returns. Unsafe: the identical probes on the identical
  image read REACHABLE and RESOLVED. That contrast is the measurement.
- **The canary leaks without confinement and not with it.** Unsafe reads
  `/proc/1/environ` and finds `TRYC_CANARY`; confined finds the file
  readable (server and submission share uid 10001, so there is no uid
  barrier here) and the canary ABSENT, because confined boot re-execs the
  server with a scrubbed environment. The barrier is the scrub, not the uid,
  and the probe distinguishes those two outcomes rather than collapsing them
  into "blocked".
- **The submission's own environment is scrubbed in BOTH modes**
  (`runtime-env: scrubbed`), because the per-execution allowlist runs
  regardless of mode. Worth knowing: if this were the only env probe, the
  negative control would show no env leak at all and the scrub would look
  proven when it was merely unexercised. The `/proc/1/environ` probe is what
  makes the difference visible.
- **Real work still happened.** Both legs produce `LESSON_OK sum=20`, exit 0,
  and the inspected final expression `"confinement-proof-complete"` in
  `value`, so no assertion above is satisfied by a broken execution.
- **What it does not establish**: `runtime-metadata` reads REFUSED in the
  unsafe leg too, because a local docker network has no metadata server at
  169.254.169.254. Only the confined leg's errno ("address family") makes the
  metadata claim, and only the deployed probe can make it against a real one.
  `runtime-proc1mem` is OPEN-UNREADABLE in both legs: same-uid open succeeds
  and the read fails, which is the residual recorded in section 6, not a
  property proven here. And `runtime-rootfs` refuses in both legs because
  the image is non-root in both, so that line proves the uid, not the mode.

### The fail-loud discipline, demonstrated

`probe_result` raises `MissingProbe` when an expected `PROBE <name>:` line is
absent, carrying the entire output in the error. The spec contains an example
that feeds it output missing the `runtime-net` probe and asserts the raise.
This is obligation 5.2: the naive helper returns "" for a missing probe and
every `should_not contain("LEAKED")` assertion then passes on an execution
that never happened. Absence is an error, never an empty string.

A lesson from making this proof honest, recorded so the next harness does not
re-learn it: busybox ash tail-execs a `-c` body that is a single AND-list, so
a wrapper shaped `sh -c 'prep && exec-me'` silently turns exec-me into pid 1.
The confined child then reads its own (scrubbed) `/proc/1/environ` and the
uid-split boundary is never exercised at all; the first version of this spec
passed everything except the proc1 probe and the investigation is why both
legs now end with `; status=$?; sleep 0.2; exit $status` to hold the
supervisor as pid 1. A boundary you are not actually standing on one side of
reads as proven from the outside.

### The interpreter finding, recorded for phase 2

DESIGN.md originally specified `crystal i` as the execution mode, on a
measurement that turned out to be the error path being timed: no interpreter
exists on any distribution tested. Exact commands and results:

```
$ echo 'puts "interp-ok #{40 + 2}"' | docker run --rm -i crystallang/crystal:1.21.0 crystal i
Crystal was compiled without interpreter support   # exit 1

$ echo 'puts "interp-ok #{40 + 2}"' | docker run --rm -i crystallang/crystal:1.21.0-alpine crystal i
Crystal was compiled without interpreter support   # exit 1

$ echo 'puts "interp-ok #{1+1}"' | docker run --rm -i crystallang/crystal:nightly crystal i
Crystal was compiled without interpreter support

$ echo 'puts "host #{1+1}"' | crystal i          # workstation, mise crystal 1.18.2
Crystal was compiled without interpreter support
```

The interpreter is a compile-time option (`make crystal interpreter=true`);
no official image or brew/mise distribution ships it. Phase 2's interpreter
work starts with building Crystal from source at the pinned version, and the
latency claim must be re-measured on that build with a success check before
any number is recorded. Phase 1 executes with `crystal run`.

### Status of the service layer, and what the harness caught on the way

The runner image is `trycrystal-runner:dev`. Getting the service legs to run
at all surfaced four real defects, which is the point of having them:

1. **The image did not build.** `crystal build -o /out/trycrystal-runner`
   with no `/out` directory: `ld: cannot open output file`. Reported, fixed
   with `mkdir -p /out`.
2. **Confined boot died by SIGKILL.** `refusing to start: boot self-test
   failed (exit 137, stdout "", stderr "")` on `aarch64`, while
   `ALLOW_UNSAFE=true` booted fine. Reported with the reading that a
   seccomp arch gate was killing every syscall (the filter it is ported
   from selects `GUARD_AUDIT_ARCH` per architecture,
   `apps/docs-build/sandbox/no-egress.c:74-82`). Root cause per the Runner
   slice was two stacked things: a Crystal BPF port that hung `crystal run`
   (now replaced by exec'ing the vendored `no-egress` helper, same reviewed
   filter) and `RLIMIT_NPROC=64`, too tight once Linux counted the server's
   threads plus the compiler's (now 256).
3. **A probe that lied.** The macro-time network probe used `curl`, and the
   runner image ships no `curl`, so it reported REFUSED in a deliberately
   UNCONFINED run. The negative control is what caught it: in the confined
   leg that probe looked like perfect confinement. Every macro probe now
   names the tool it needs and reports `NO-TOOL-<name>` when it is absent,
   so a missing binary can never again read as a refusal. This is the
   failure the docs-build authors warned about in
   `apps/docs-build/sandbox/egress-probe.c:8-12`, and it happened here.
4. **A scratch permission regression.** Confined boot refused with
   `Error opening file with mode 'w':
   '/scratch/run-<id>/.cache/scratch-run-<id>-submission.cr/bc_flags.o0':
   Permission denied` from the compiler's codegen. Reproduced with both my
   arguments and the Runner slice's own, and shown NOT to be an environment
   problem: the same image, same tmpfs, same uid 10001 compiles and runs
   `puts 1+1` through `crystal run` with `CRYSTAL_CACHE_DIR` pointed at the
   same kind of directory. Cause was the read-only cache seed being copied
   into the per-execution cache without making the copy writable; fixed by
   chmod on the copy, with the seed in `/opt/crystal-cache` still
   unwritable.
5. **Both modes set at once.** My first service-layer attempt passed
   `TRYC_SANDBOX=cloudrun` and added `ALLOW_UNSAFE=true` for the negative
   control; the runner refused to boot: "a confined runner must not also opt
   out of confinement". That refusal is correct, and the spec now sets
   exactly one mode per leg.

All five are resolved, and the final run is the green one quoted above.

Three things worth stating plainly. First, the fail-closed gate did its job
every time: the runner refused to serve rather than serving unconfined, and
it named what was missing. Second, the harness reports these as failures
carrying the container's own words within about twelve seconds, because it
reads the dead container's exit code and logs into the message and
deliberately does not pass `--rm` so there is a corpse to read; a
confinement defect that reads as a flake is how a broken sandbox ships.
Third, every one of those defects was found by running the proof, not by
reading the code, and the one that mattered most (the probe that lied) was
found by the negative control rather than by the confined assertions.

## 5. What is NOT proven locally, and must be re-proven

- **CI wiring.** The service legs pass here, driven by hand:
  `TRYC_RUNNER_IMAGE=trycrystal-runner:dev crystal spec
  spec/confinement_spec.cr`. Nothing runs them automatically yet. They
  belong in CI against the image CI itself builds (that env var exists for
  exactly this: proving the image that ships beats rebuilding a different
  one inside the spec). Without that, this proof is a thing someone
  remembered to run.
- **Linux CI.** The local docker is OrbStack on macOS: a real Linux kernel
  in a VM, so seccomp, uid, and /proc semantics measured here are genuinely
  Linux rather than emulated, but it is not the production kernel. Docker
  also applies its own default seccomp profile to every container (that is
  the Seccomp: 2 in the leak leg; ours stacks on top in the confined leg,
  and the exact-errno assertions isolate our filter's actions from the
  runtime's). uid ownership inside the VM can be remapped relative to a bare
  Linux host. The mechanism-layer spec should run unchanged on a Linux CI
  runner, and its green there supersedes this local run.
- **The deployed surface.** gVisor implements seccomp and /proc inside the
  sandbox rather than passing them to the host kernel, so the filter's
  behavior must be re-proven against the real service after deploy: the
  service-layer spec pointed at the deployed URL (or an equivalent probe)
  asserting the same PROBE lines, particularly the metadata refusal with the
  filter's errno. That probe does not exist yet and belongs to the deploy
  pipeline once the runner ships.
- **Cloud Run Job latency** (the negative claim in section 2) is structural,
  not measured; no local measurement of Job cold start was possible without
  deploying, and none was attempted.

## 6. Residual gaps, stated rather than hidden

- **Same-uid kill(2).** The server and the submission share uid 10001, and the
  egress filter does not deny signal syscalls, so a running submission can
  kill the server process: a DoS on one warm instance, which recycles. Not
  exfiltration. Mitigated by concurrency 1 (no sibling submissions to
  signal) and instance recycling; not eliminated. Recorded by the Runner
  slice and pinned in terraform by the concurrency validation.

  How it reaches a visitor, per the Console slice: the client raises
  `RunnerClient::Unreachable` and the endpoint answers 502 with in-character
  copy ("The sandbox is not answering right now. Your code did not run,
  nothing was lost, and it is not anything you typed."), never a stack
  trace. So the residual degrades honestly rather than invisibly. It is
  still a real outage for whoever is queued behind it, and the copy does not
  pretend otherwise.

  Also visitor-facing, and a capacity question rather than a confinement
  one: concurrency 1 plus recycling means concurrent visitors queue rather
  than execute in parallel. The console's HTTP read timeout sits above the
  sandbox's execution budget so a queued submission waits instead of
  false-reporting unreachable, but queue depth under real traffic is not
  something either slice can absorb and belongs with whoever sizes the
  service.
- **Same-uid /proc/<pid>/mem open.** The easy paths (ptrace,
  process_vm_readv) are denied by the filter, but open+read of
  `/proc/<server>/mem` may succeed at the open for a same-uid process;
  reading it without an attach fails (EIO). Pre-GC server memory may retain
  earlier submissions' text. Mitigated by concurrency 1, the boot env
  scrub, scratch wiping, and recycling; not eliminated. The spec asserts
  the probe never reads READABLE and records OPEN-UNREADABLE as the known
  shape.
- **Kernel residual.** A bug in seccomp, io_uring, or gVisor itself is the
  residual every container has (`no-egress.c:51-53` names it for
  docs_build).

## 7. Artifacts

- `apps/trycrystal/runner/spec/confinement_spec.cr`: the proof. Three
  mechanism examples (leak, blocked, fail-loud demonstration) and two
  service examples driving the real HTTP path, all passing; the service pair
  reports `pending!` with a stated reason when no runner image is available,
  and never passes quietly.
- `apps/trycrystal/runner/spec/fixtures/hostile_submission.cr`: the hostile
  submission: canary env read (macro and runtime), outbound network (macro
  and runtime), DNS, metadata server, supervisor environ and memory reads,
  uid report, root-filesystem writes, kernel capability/seccomp status, and
  legitimate lesson output plus a final expression so a passing run cannot
  mean a broken one.
- Cross-references: `apps/trycrystal/REGISTRATION.md` carries the
  confinement posture summary; the runner service terraform pins concurrency
  to 1 by validation citing this file.

How to run it:

```
cd apps/trycrystal/runner
crystal spec spec/confinement_spec.cr                    # mechanism layer
TRYC_RUNNER_IMAGE=<tag> crystal spec spec/confinement_spec.cr   # plus service layer
```
