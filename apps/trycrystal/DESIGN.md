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

## 2. Execution mode: the interpreter

Measured on this workstation, Crystal 1.21.0:

| Mode | Trivial script | With stdlib requires (JSON/HTTP) |
|---|---|---|
| `crystal i` (interpreter) | 401 ms | 693 ms |
| `crystal run` | 970 ms | 1278 ms |
| `crystal build` (compile only) | 454 ms | n/a |

Decision: `crystal i`. The original tryruby was submit-a-line-and-answer, not
keystroke-level, so sub-second is enough. `crystal run` is not.

The language is not the latency risk. Sandbox cold start is, which is why the runner is a
warm pool (section 4) rather than a container or Kubernetes Job per request.

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

Untrusted Crystal runs here, and interpreting it executes it. Macros execute too.

Trust split:

| Phase | Network | Runs user code | Where |
|---|---|---|---|
| serve UI, lesson content | yes | no | `trycrystal` namespace, has creds |
| execute submission | **no** | **yes** | `trycrystal-sandbox` namespace, no creds |

Runner properties, all required:

- Its **own namespace**. NetworkPolicies are additive, so isolation cannot be added to a
  namespace where any existing policy uses an empty pod selector.
- Deny-all egress. No environment variables from the platform. No mounted secrets.
- `automountServiceAccountToken: false`.
- Read-only root filesystem, non-root uid, all capabilities dropped,
  `allowPrivilegeEscalation: false`.
- Per-execution: fresh scratch directory, wall-clock timeout, rlimits, pid and memory caps.
- `runtimeClassName` exposed as a variable so gVisor can be selected, not hardcoded.
- Pods recycle after a bounded number of executions.
- The runner **refuses to start** when confinement is unconfigured. The opt-out is the
  exact string `ALLOW_UNSAFE=true`, not any truthy value.

### Accepted tradeoff, stated plainly

A warm pool means consecutive submissions from different users share a pod. That is weaker
than a container per execution, and it is chosen for latency. It is made survivable by the
pod holding nothing worth stealing (no credentials, no tokens, no egress) and by recycling.
It is not equivalent to per-request isolation and this document does not claim it is.

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

Infrastructure is GKE with a shared Envoy Gateway. There is no Cloud Run in this repo and
no `lifecycle { ignore_changes = [image] }` anywhere in `terraform/`, so the silent
image-roll trap that affects Cloud Run jobs does not apply. Image tags roll via the commit
SHA in the deployment annotation plus `image_pull_policy = "Always"`.

`trycrystal.org` is a new apex domain, so unlike the existing apps it needs a new Cloud DNS
managed zone and its own gateway listeners. Registrar delegation order matters: delegate
nameservers and confirm resolution first, publish the DNSSEC DS record second. Publishing a
DS record that does not match the serving zone breaks the whole domain.

Toolchain note: the existing apps pin Crystal 1.17.1 while this workstation runs 1.21.0.
The runner image version must be chosen deliberately, since the version the user's code
runs against is a product decision, not an accident of the build host.

## 7. Open, and owned by Jason

- Art direction and the console's voice. The joy is the product here, and inventing his
  taste is not this document's job.
- Accepting the section 4 tradeoff.
