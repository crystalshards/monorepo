# trycrystal runner

The execution service behind trycrystal.org. It takes untrusted Crystal source
over HTTP, compiles and runs it under confinement, and answers with what the
program printed and what its final expression evaluated to.

It is deliberately dependency-free (stdlib only) and deliberately boring: one
binary, two endpoints, one process per submission.

## API

    POST /execute
    request:  {"code": "<crystal source>", "timeout_ms": 5000}
    response: {"stdout": "...", "stderr": "...", "value": "...",
               "exit_code": 0, "timed_out": false, "duration_ms": 412}

    GET /health -> {"status": "ok", "crystal_version": "Crystal 1.21.0 (...)"}

`value` is the inspected value of the submission's final expression, as a
string, or `null` when the submission ends in something with no value (a `def`,
a `class`, a `require`). `"nil"` and `null` are different answers: the first
means the final expression evaluated to nil, the second means there was no
final expression.

Failures in user code are not server errors. A compile error or an unhandled
exception is HTTP 200 with `stderr` populated and a non-zero `exit_code`. HTTP
400 means the request itself was malformed; HTTP 500 means the runner broke.

`timeout_ms` is clamped to `RUNNER_MAX_TIMEOUT_MS` (default 10000). The clock
covers compile plus run, because that is what the learner waits for.

## Running it

Deployed (Cloud Run), confinement on:

    TRYC_SANDBOX=cloudrun trycrystal-runner

Developer workstation, confinement off, opt-out spelled exactly:

    ALLOW_UNSAFE=true trycrystal-runner

Anything else refuses to start and says what is missing. `ALLOW_UNSAFE=1`,
`ALLOW_UNSAFE=yes` and `ALLOW_UNSAFE="true "` are all refusals: the opt-out is
the exact string `true`, so it cannot be typed by accident or inherited from
another variable's convention. Setting both markers is also a refusal.

### Configuration

| Variable | Default | Meaning |
|---|---|---|
| `PORT` | 9292 | Listen port |
| `TRYC_SANDBOX` | unset | `cloudrun` enables confined mode |
| `ALLOW_UNSAFE` | unset | exactly `true` runs unconfined (dev only) |
| `RUNNER_CRYSTAL_BIN` | `crystal` | Compiler used for executions |
| `RUNNER_SCRATCH_ROOT` | `/scratch` confined, `/tmp/trycrystal-runner` unsafe | Per-execution scratch parent |
| `RUNNER_DEFAULT_TIMEOUT_MS` | 20000 | Used when a request omits `timeout_ms` |
| `RUNNER_MAX_TIMEOUT_MS` | 30000 | Ceiling on a requested timeout |
| `RUNNER_MAX_OUTPUT_BYTES` | 1048576 | Per-stream cap; exceeding it kills the run |
| `RUNNER_CONCURRENCY` | 1 | Executions in flight per instance |
| `RUNNER_LIMIT_AS` | 3221225472 | RLIMIT_AS, bytes (0 disables) |
| `RUNNER_LIMIT_CPU_S` | 15 | RLIMIT_CPU, seconds (0 disables) |
| `RUNNER_LIMIT_NPROC` | 256 confined, 0 unsafe | RLIMIT_NPROC (0 disables) |
| `RUNNER_LIMIT_FSIZE` | 67108864 | RLIMIT_FSIZE, bytes (0 disables) |
| `RUNNER_LIMIT_NOFILE` | 256 | RLIMIT_NOFILE (0 disables) |

## What happens to one submission

1. A fresh scratch directory, mode 0700, under the scratch root.
2. The source is wrapped so the final expression's value can be captured
   (see below) and written to `submission.cr`.
3. The server re-execs its own binary as a trampoline
   (`trycrystal-runner --sandbox-exec -- crystal run --no-color submission.cr`).
   Between fork and the compiler, the trampoline: `setsid` so the execution is
   its own process group; applies rlimits; in confined mode, execs the
   vendored `no-egress` helper (the same C filter docs-build already ships),
   which installs and PROVES the filter then execs `crystal`; closes every
   inherited descriptor above stderr; `chdir` into the scratch directory.
4. Both streams are read with a byte cap. A wall-clock timer kills the whole
   process group on expiry, as does a cap breach.
5. The value file is read, the scratch directory is wiped, the JSON goes back.

The child environment is an allowlist, not a copy: `PATH`, `HOME`, `TMPDIR`,
`TERM`, `CRYSTAL_CACHE_DIR`, `TC_VALUE_PATH` and the numeric `TC_*` limits.
Nothing the platform set on the server reaches user code.

`CRYSTAL_CACHE_DIR` is per execution, inside the scratch directory. A shared
warm cache would be faster and is not used: instances are shared between
submissions, and a cache one submission can write is a cache the next
submission's compile reads.

## Capturing the final expression's value

Crystal rejects declarations inside expressions, verified against 1.21.0:

    v = begin
      def foo; 1; end   # Error: can't declare def dynamically
    end

`require`, `class` and `macro` fail the same way, so the whole program cannot
be wrapped in something that yields a value. What works is wrapping only the
final top-level statement:

    <every earlier line, untouched, declarations included>
    __tc_v = begin
      <the final statement, verbatim>
    end
    File.write(ENV["TC_VALUE_PATH"], __tc_v.inspect)

`src/wrap.cr` finds where that statement starts by walking lines backward,
counting block closers against openers, and handling heredoc terminators. It
declines to wrap whenever it cannot establish a start, when the statement is
itself a declaration, or when a declaration is nested inside it (a `def` inside
a conditional, say, which Crystal rejects anyway). Declining costs a `null`
value; wrapping the wrong range would break the program.

If a wrapped run still fails with a wrap-shaped error (`syntax error`,
`can't declare`, `unexpected token`, `unterminated`, `expecting`), the executor
reruns the user's exact bytes unwrapped. A user's own error of that class
reproduces itself on the retry, so the cost is one extra run on a typo, never a
wrong answer.

Compiler line numbers are mapped back to the user's numbering, both in
`In submission.cr:N:C` references and in the `N | source` excerpt lines.

## Confinement

Process-level, which is what this service controls:

| Control | Mechanism | Binds where |
|---|---|---|
| No egress | seccomp filter: `socket`/`socketpair` restricted to AF_UNIX and AF_NETLINK, io_uring denied outright, ptrace and `process_vm_*` denied, `no_new_privs` set | Linux, confined mode |
| Process group kill | `setsid` before exec, `kill(-pgid)` on timeout or cap breach | everywhere |
| Address space | RLIMIT_AS | Linux only (see below) |
| CPU time | RLIMIT_CPU | everywhere |
| Process count | RLIMIT_NPROC | confined mode (per-uid, so only where the uid is ours) |
| File size | RLIMIT_FSIZE | everywhere |
| Descriptors | RLIMIT_NOFILE | everywhere |
| No inherited descriptors | trampoline closes everything above stderr | everywhere |
| Clean environment | allowlist, `clear_env` | everywhere |
| No platform env in `/proc/1/environ` | boot-time `execve` of self with a scrubbed environment | confined mode |
| Fresh filesystem per execution | scratch directory created and wiped per run | everywhere |

The seccomp filter is `sandbox/no-egress.c`, vendored from
`apps/docs-build/sandbox/no-egress.c`. A Crystal BPF port of the same filter
hung `crystal run` on aarch64 (exit 137, empty streams) and was withdrawn.
The C helper is single-threaded, installs with TSYNC, proves the filter
in-process (AF_INET/INET6/PACKET/VSOCK return EAFNOSUPPORT, io_uring returns
EPERM, AF_UNIX still works), and execs. A proof failure refuses the
execution rather than running it unconfined.

### Stated residuals, not fixed in phase 1

- **Same-uid server access.** Server and submissions share uid 10001. ptrace
  and `process_vm_readv` are denied by the filter, and `/proc/1/environ` is
  scrubbed by the boot re-exec, but an `open` and `read` of `/proc/1/mem` is a
  credential-free path to server memory, which can retain earlier submissions'
  text until the GC reuses it. Bounded by `RUNNER_CONCURRENCY=1` and instance
  recycling, not eliminated. Closing it needs a uid split, which needs a root
  supervisor (what docs-build does, because it holds signed URLs; this service
  holds nothing).
- **Same-uid signals.** A submission can `kill` the server process. That is a
  denial of service against one instance, not exfiltration; the platform
  restarts it.
- **`setsid` escape from the group kill.** A descendant that calls `setsid`
  leaves the process group and survives the timeout kill. RLIMIT_CPU still
  binds it, and the instance's own lifetime bounds it.
- **RLIMIT_AS is unenforceable on macOS.** Darwin rejects every
  `setrlimit(RLIMIT_AS, ...)` with EINVAL (verified: `ulimit -v` fails for
  every value tested, 256 MiB through 4 GiB). Confined mode refuses to run an
  execution whose rlimits cannot be set; `ALLOW_UNSAFE` mode skips what the
  kernel will not accept. Memory limiting is therefore a Linux property, which
  is where this service is deployed.
- **Macro-time execution.** `crystal run` expands macros, and a macro can
  shell out. The seccomp filter, rlimits and scratch isolation all apply to
  the compiler process as well, which is why they are installed before exec
  rather than around the user's binary.

## Building the image

    docker build -t trycrystal-runner:dev apps/trycrystal/runner
    docker build --build-arg CRYSTAL_VERSION=1.21.0 -t trycrystal-runner:dev apps/trycrystal/runner

Run it confined (Linux container, seccomp active):

    docker run --rm -p 9292:9292 -e TRYC_SANDBOX=cloudrun \
      --tmpfs /scratch:rw,exec,mode=0700,uid=10001,size=512m \
      --read-only trycrystal-runner:dev

## Measured latency

Through the service, `duration_ms` from the response, fresh compiler cache per
execution, on an Apple M5 Max workstation running the binary natively
(Crystal 1.21.0, ALLOW_UNSAFE mode):

| Submission | duration_ms |
|---|---|
| `1 + 1` | 1005 |
| `puts "hello trycrystal"` | 1058 |
| `require "json"` + `require "http/client"` + `JSON.parse("[1,2,3]")` | 1645 |

Bare `crystal run` on the same machine with a fresh cache measures 1.03-1.06s
for the trivial program, so the service (trampoline re-exec, scratch setup,
wrap, capture, wipe) adds single-digit milliseconds rather than a tax worth
optimizing. The compile is the cost.

Same calls through the confined container (`trycrystal-runner:dev`,
TRYC_SANDBOX=cloudrun, read-only root, tmpfs /scratch, uid 10001, aarch64
Alpine, Crystal 1.21.0, `crystal run`, seeded read-only cache):

| Submission | duration_ms |
|---|---|
| `1 + 1` | 1842 |
| `require "json"` + `JSON.parse("[1,2,3]")` | 1830 |
| `require "json"` + `require "http/client"` + parse | 2892 |

Without the seed, the same json case was 6334-6584ms cold, which is why the
default timeout had to move from 5000 to 20000.

Interpreter tag (`trycrystal-runner:interpreter`, `Dockerfile.interpreter`,
`crystal i`, same confinement):

| Submission | duration_ms |
|---|---|
| `1 + 1` | 396 |
| `require "json"` + `JSON.parse("[1,2,3]")` | 397 |
| `require "json"` + `require "http/client"` + parse | 538 |

Build: `docker build -f Dockerfile.interpreter -t trycrystal-runner:interpreter .`
