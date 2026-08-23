# trycrystal

The web app behind trycrystal.org: a guided Crystal console in the browser, in
the lineage of the original tryruby.org. A visitor types a line of Crystal,
the line runs for real in a sandboxed runner, and the console answers with
output and a personality. Three lessons that build on each other, progress
kept in the browser's localStorage, no accounts, no database.

This is a [Lucky](https://luckyframework.org) application, deliberately
without Avram or any database: nothing in phase 1 needs server-side state.

## Running the app and the runner together, locally

The console is two processes: this web app, and the sandbox runner it talks
to over HTTP (`apps/trycrystal/runner`, a separate deployable with its own
Dockerfile). The web app serves pages and decides lessons; the runner
executes submitted code. They are started separately.

1. Install Crystal 1.17.1 (the version `.crystal-version` pins) and run
   `shards install` in this directory.

2. Start the runner. From `apps/trycrystal/runner`, follow that directory's
   own instructions; it fails closed when its confinement is unconfigured,
   and the documented way to run it loose for local development is
   `ALLOW_UNSAFE=true` (the exact string, never any other truthy value).

3. Start the web app:

   ```
   crystal run src/trycrystal.cr
   ```

   It listens on http://localhost:3004 (see `config/watch.yml`).

4. Point the app at the runner with `RUNNER_URL`. The default is
   `http://localhost:9292`, which is where the runner binds locally. In
   production there is no default; the revision refuses to boot without
   `RUNNER_URL` set, because a deployed app silently pointed at a localhost
   that does not exist would look fine and answer every submission with
   "the sandbox is not answering".

`Procfile.dev` runs the web side (`foreman start -f Procfile.dev` if you use
foreman). `Procfile` runs the release binary from `shards build trycrystal`.

## The endpoint contract

- `POST /api/executions` with `{"code": "...", "lesson_id": "..."}`. The
  web app forwards the code to the runner verbatim (plus `timeout_ms`),
  evaluates the lesson check against what came back, and answers with the
  runner's fields untouched (`stdout`, `stderr`, `value`, `exit_code`,
  `timed_out`, `duration_ms`) plus a `lesson` object: the verdict, the
  reaction, and the next lesson's prompt when the check advanced.
- `GET /api/health` answers `{"status": "ok", ...}`, which is what the
  deploy workflow's startup probe polls. It deliberately does NOT probe the
  runner: a sandbox outage degrades the console in character, it does not
  take the site's revisions out of Ready.

Everything a visitor's code produced travels as JSON and is rendered with
`textContent`, on both sides of the wire. Nothing anywhere renders it as
HTML.

## Where the words and the look live

Art direction and voice are deliberately isolated so they can be redirected
without touching structure:

- Every sentence the product says is in `src/copy.cr`. Actions, pages, and
  the console script render strings but author none.
- The palette is the custom-property blocks at the top of
  `public/css/app.css`. Everything below them is structure.
- The lessons themselves (prompt, code sample, hint, success reaction, and
  the check that decides advancement) are in `src/lessons/`.

Lesson checks see the runner's result only: `stdout`, `value`, exit status,
timeout. Two spellings that behave the same both pass; a submission that
prints the right words while crashing still fails. Checks never
string-match the source the visitor typed, and they run server side, never
in the browser.

## Tests

```
crystal spec
```

The specs run against `spec/support/fake_runner.cr`, a real local HTTP
server speaking the runner's exact contract over a real socket, so the
client's transport paths (success, malformed bodies, refused connections)
are exercised for real. No database is needed.

## Deployment notes

This app has no database and no migrations, which makes it the first app in
the monorepo without a `src/migrate.cr`. CI's build step and the deploy
workflow's migration handling are written for apps that have one; adding
this app to those matrices requires accounting for that (see the comment in
the Dockerfile build stage). `RUNNER_URL` must reach the runner's service;
the deploy wiring for that variable lives in terraform and the deploy
workflow, not in this app.
