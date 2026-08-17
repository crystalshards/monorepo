variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "Region every service and Job runs in"
  type        = string
}

variable "image_repository" {
  description = "Artifact Registry path images are tagged against, without a trailing slash, e.g. us-central1-docker.pkg.dev/<project>/docker-images"
  type        = string
}

variable "image_tag" {
  description = <<-DESC
    Image tag every service and Job is created at. Always a commit SHA, never
    "latest": CI pushes only SHA tags, and a floating tag makes the plan unable
    to answer what is actually serving.

    Terraform sets this at create time and then stops fighting for it. Every
    service and Job carries lifecycle.ignore_changes on the image so CI can roll
    subsequent revisions with `gcloud run services update`.
  DESC
  type        = string
}

variable "docs_launcher_image_name" {
  description = <<-DESC
    Image name within the repository for the docs-launcher service.

    It is "crystalshards", not "docs-launcher". There is no apps/docs-launcher
    and CI builds no such image: the launcher is the registry image deployed a
    second time under a second service name, because the trusted half of a
    documentation build already lives in that codebase. Defaulting this to
    "docs-launcher" would fail the first apply on an image that does not exist.
  DESC
  type        = string
  default     = "crystalshards"
}

variable "docs_build_image_name" {
  description = "Image name within the repository for the docs-build Job. This is the image that runs untrusted third party shard code"
  type        = string
  default     = "docs-build"
}

variable "docs_build_core_image_name" {
  description = <<-DESC
    Image name within the repository for the docs-build-core Job, which
    publishes the Crystal standard library's own documentation.

    Built from the SAME apps/docs-build Dockerfile as docs_build_image_name,
    with --build-arg EXTRA_PACKAGES="llvm-dev llvm-static" baked in at image
    build time. It is a distinct image, not a distinct Dockerfile: the
    confinement (the seccomp filter, the unprivileged compile user, the
    allowlisted invocation env vars) has to survive the extra packages
    unchanged, and a second Dockerfile is the one thing guaranteed to let it
    drift.
  DESC
  type        = string
  default     = "docs-build-core"
}

variable "cloud_sql_connection_name" {
  description = "Instance connection name, mounted as the /cloudsql/<connection_name> socket volume"
  type        = string
}

variable "database_url_secret_ids" {
  description = "Map of app slug to the Secret Manager secret_id holding that database's connection string"
  type        = map(string)
}

variable "mail_enabled_apps" {
  description = <<-DESC
    App slugs whose Resend secret CI has actually populated with a version.
    RESEND_API_KEY is attached to a revision only for these, because a revision
    referencing a versionless secret never reaches Ready.

    Names only, never a key value. Intersected with local.mail_senders, so a slug
    outside crystalgigs/crystalbits is dropped rather than wired. Empty is the
    normal case until the keys exist: all four services serve, and the two
    senders raise on an actual send attempt naming RESEND_API_KEY.
  DESC
  type        = set(string)
  default     = []
}

variable "discovery_enabled_hosts" {
  description = <<-DESC
    Git hosts whose discovery credentials CI has actually populated with a
    version. The matching token environment variable is attached to the
    discover-shards Job only for these, because an execution referencing a
    versionless secret never starts.

    Names only, never a token value. Intersected with
    local.discovery_host_credentials, so a host the crawler does not support is
    dropped rather than wired. Empty is the normal case until the tokens exist,
    and it is a supported state rather than a broken one: the sweep runs, reports
    every host as skipped naming the variable that would enable it, and exits
    successfully having indexed nothing.

    Use the host names Discovery::CrawlRunner::HOSTS uses, so "github.com" and
    not "github". bitbucket.org needs BOTH halves of its credential populated
    before it may appear here, because HTTP Basic carries the account as well as
    the password.
  DESC
  type        = set(string)
  default     = []
}

variable "discovery_max_pages" {
  description = <<-DESC
    How many pages of each host's search API one scheduled sweep walks before it
    stops. Published to the Job as DISCOVERY_MAX_PAGES.

    A sweep is bounded on purpose. The crawler persists its cursor after every
    page, so a run that stops early is a run that resumes, and the next scheduled
    execution continues from the same place. An unbounded sweep has the opposite
    property: it runs until the Job timeout kills it, mid page, having spent the
    host's whole rate limit budget in one window.

    Ten is not a round number, it is one full GitHub code search result window.
    GithubCrawler has RESULT_CAP 1000 and PER_PAGE 100 and computes
    last_page = (min(total, 1000) - 1) // 100 + 1, which is 10; at page >=
    last_page it advances to the next file-size window instead. So ten pages stops
    the sweep exactly on a window boundary and cannot overshoot the 1000 result
    cap, and a smaller number would stop partway through a window for no benefit.

    It is also about a minute of search budget. GET /search/code is the tightest
    limiter in the set, and the only way to ask which repositories have a
    shard.yml at their root: it requires authentication and allows 10 requests per
    minute. Not the 30 per minute figure, which GitHub's docs apply to every
    search endpoint EXCEPT code search. The other three hosts are looser, and all
    four back off on their own rate limit headers regardless of this number.
  DESC
  type        = number
  default     = 10

  validation {
    condition     = var.discovery_max_pages >= 1 && var.discovery_max_pages <= 50
    error_message = "discovery_max_pages must be between 1 and 50. Below 1 the sweep would walk no pages at all and report success; above 50 a single run exceeds what GitHub's code search will return for one query (1000 results) and spends the rest of the run being throttled."
  }
}

variable "discovery_high_value_pages" {
  description = <<-DESC
    How many pages of GitHub's star-ranked repository search one scheduled run
    seeds from before the exhaustive sweep starts. Published to the Job as
    DISCOVERY_HIGH_VALUE_PAGES.

    This is the pass that puts the shards people have heard of in the registry
    early. The exhaustive sweep partitions code search on shard.yml file size
    ascending, which is the only quantity that endpoint will partition on, and
    that order reaches trivial repositories first: measured on github.com, about
    3000 manifests are smaller than kemal's 363 byte one. Repository search
    accepts sort=stars, which code search does not, so a small slice of it read
    first fixes the order without touching the sweep that guarantees coverage.

    Three pages is 300 candidates, and the binding cost is core rather than
    search. A page is one search request plus up to 100 contents requests to
    confirm a root shard.yml, so three pages is up to 300 core requests against
    the 5000 an hour a token gets, on top of about 1000 for the sweep and 900
    for indexing. The three search requests are not part of that figure and must
    not be added to it: measured live, GET /search/repositories reports
    x-ratelimit-resource: search at 30 a minute, a different bucket from both
    core and the 10 a minute code_search the exhaustive sweep uses.

    Three is also enough to matter on the first run. Every Crystal shard with
    more than 500 stars is inside the first three pages of language:Crystal.
  DESC
  type        = number
  default     = 3

  validation {
    condition     = var.discovery_high_value_pages >= 1 && var.discovery_high_value_pages <= 20
    error_message = "discovery_high_value_pages must be between 1 and 20. Below 1 the pass would read no pages and report success; above 20 there is nothing left to read, because both seeds together are 20 pages of GitHub's 1000 result cap and the pass starts the ranking again rather than going deeper."
  }
}

variable "index_max_shards" {
  description = <<-DESC
    How many shards one scheduled run indexes after the crawl finishes.
    Published to the Job as INDEX_MAX_SHARDS.

    Discovery finds repositories and records identity. Indexing is the second
    phase, and the one that turns a row into a page with stars, versions, a
    manifest and a README. It is bounded for the same reason the crawl is: the
    cursor is shards.index_attempted_at, stamped per shard before its fetch, so
    a run that stops early resumes rather than restarting.

    300 is sized from what the crawl leaves behind. An authenticated token gets
    5000 core requests an hour; a 10 page sweep of github.com spends roughly
    1010 of them, leaving about 3900. Indexing one shard costs three core
    requests: the repository, its tags, and one commit to date the version being
    indexed. shard.yml and README come from the raw file endpoint, which is not
    the API and does not draw on the core pool. So 300 shards is about 900
    requests, well inside the remainder with room for retries and for another
    host gaining a credential.

    It also clears the whole current backlog in one run and covers all 5696
    discoverable repositories in roughly 19 runs.
  DESC
  type        = number
  default     = 300

  validation {
    condition     = var.index_max_shards >= 1 && var.index_max_shards <= 2000
    error_message = "index_max_shards must be between 1 and 2000. Below 1 the phase would index nothing and report success; above 2000 one run's three-requests-per-shard cost exceeds what remains of GitHub's 5000/hour core budget after a sweep, and the run ends throttled partway through with its cursor mid-batch."
  }
}

variable "dependency_max_candidates" {
  description = <<-DESC
    How many repositories one scheduled run harvests from the dependency graph
    it already holds. Published to the Job as DEPENDENCY_MAX_CANDIDATES.

    This is the fourth phase, and it exists because the crawl's ceiling is not
    its speed. github.com reported completed_exhaustive at roughly 5000 shards,
    which is everything GitHub's code search index will admit for a root
    shard.yml, and the three other hosts have no credential at all. A manifest
    declaring `radix: {github: luislavena/radix}` names that repository exactly
    whether or not any crawler could ever see it, so the graph reaches all four
    hosts, plus forks and anything code search never indexed.

    Each lead is resolved locally first and then, finding nothing, read from
    its host and stored: the row lands with the repository's own name, stars,
    versions and README rather than an identity and a placeholder. A lead
    naming a repository that has been deleted or renamed is marked unavailable
    in the same run rather than sitting in the listing looking live.

    Finding the leads costs no host requests, because they are a query over
    rows we already hold. Reading one costs the three core requests indexing
    any shard costs, so this bound is sized against what the phases before it
    leave unspent: a 10 page sweep is about 1000 requests of GitHub's 5000 an
    hour, the 3 page seed about 300 and indexing 300 shards about 900, leaving
    roughly 2800. 200 leads is about 600 of those, well inside the remainder
    with room for retries and for another host gaining a credential.

    Leads are never lost to the bound. An unregistered slug stays in the
    dependency table and the next run takes the next batch, most depended-upon
    first, so this sets the rate and never the reach.
  DESC
  type        = number
  default     = 200

  validation {
    condition     = var.dependency_max_candidates >= 1 && var.dependency_max_candidates <= 900
    error_message = "dependency_max_candidates must be between 1 and 900. Below 1 the phase would harvest nothing and report success; above 900 its three-requests-per-lead cost exceeds what remains of GitHub's 5000/hour core budget after the sweep, the seed and the indexing phase, and the run ends throttled partway through."
  }
}

variable "discovery_timeout_seconds" {
  description = <<-DESC
    Ceiling on one scheduled sweep, as the discover-shards Job's task timeout.

    Not the 600s Cloud Run defaults to. Four hosts are swept in sequence, and a
    host that hits its rate limit sleeps for as long as its own headers ask,
    which for GitHub's search API is up to a minute at a time. At 600s a sweep
    that is merely being throttled gets killed for it.

    Not unbounded either, and 3600s is the ceiling rather than a preference:
    Cloud Scheduler's own attempt is irrelevant here because the :run call
    returns as soon as the execution is created, but a sweep still has to finish
    before the next one starts or two executions crawl the same cursor. At the
    6 hour cadence in modules/scheduler that leaves a wide margin.
  DESC
  type        = number
  default     = 1800

  validation {
    condition     = var.discovery_timeout_seconds >= 600 && var.discovery_timeout_seconds <= 3600
    error_message = "discovery_timeout_seconds must be between 600 and 3600. Below 600 a sweep that is merely backing off on a host's rate limit headers is killed for it; above 3600 it exceeds the maximum task timeout Cloud Run accepts."
  }
}

variable "docs_bucket_name" {
  description = "Built documentation bucket"
  type        = string
}

variable "packages_bucket_name" {
  description = "Package artifact bucket"
  type        = string
}

variable "docs_build_queue_name" {
  description = "Short name of the Cloud Tasks queue documentation builds are enqueued on"
  type        = string
}

variable "docs_build_queue_location" {
  description = "Location of the Cloud Tasks queue"
  type        = string
}

variable "docs_build_concurrency" {
  description = <<-DESC
    The global documentation build concurrency cap, taken from the queue module
    rather than restated. docs-launcher's max_instances is pinned to it, so the
    dispatcher can never be asked to hold more builds open than the queue is
    willing to have in flight, and the Job's own parallelism is 1.
  DESC
  type        = number
}

variable "docs_build_timeout_seconds" {
  description = <<-DESC
    Ceiling on a single documentation build, and the single number four things
    derive from. docs-launcher holds the Cloud Tasks request open for the whole
    execution so it can record the outcome from an identity that has the
    database, so the launcher's request timeout, the docs-build Job's timeout
    and the per-task Cloud Tasks dispatchDeadline set by each producer all have
    to agree. The sandbox timeout is derived from this too, but deliberately
    NOT equal to it: see docs_build_launcher_margin_seconds.

    Changing this here is sufficient, and that is deliberate. This value becomes
    local.docs_build_deadline_seconds, which sets both timeouts directly and is
    also published to crystalshards, crystaldocs and docs-launcher as
    DOCS_BUILD_DEADLINE_SECONDS. The two producers read that env var rather than
    carrying a literal, so there is no second number to keep in step and no way
    to move one without the other.

    It is wired that way because the drift is undetectable. Nothing in the
    pipeline can see a mismatch: /api/health answers in milliseconds so every
    readiness probe and deploy gate stays green, and the app side specs can only
    observe the task half. The only symptom of a dispatch deadline shorter than
    the build is documentation that never appears, while Cloud Tasks abandons
    and redelivers a build that is still running.
  DESC
  type        = number
  default     = 1800

  # Upper bound: 1800 is not a preference, it is the ceiling. Cloud Tasks
  # accepts a dispatchDeadline for an HTTP target only in [15s, 1800s], and this
  # value is published to the producers as DOCS_BUILD_DEADLINE_SECONDS. Raise it
  # to 3600 and two of the three consumers accept it happily: the launcher's
  # Cloud Run timeout and the Job's timeout both allow it. The third does not,
  # so every CreateTask call is rejected, and because the enqueue path rescues
  # and logs, that surfaces as "queue unreachable" while documentation is simply
  # never commissioned.
  #
  # Lower bound: 900 rather than the 15 Cloud Tasks would tolerate, because
  # docs_build_launcher_margin_seconds is subtracted from this to produce the
  # sandbox timeout, and that subtraction has to stay comfortably positive. The
  # two bounds are checked independently on purpose. A single cross-variable
  # condition would be more direct but needs Terraform 1.9 for a validation to
  # reference another variable, and this configuration declares >= 1.7, so it
  # would be a check that only runs where someone happens to be newer.
  #
  # The apps validate the same bounds at boot. These refuse at plan time, which
  # is the cheaper place to find out.
  validation {
    condition     = var.docs_build_timeout_seconds >= 900 && var.docs_build_timeout_seconds <= 1800
    error_message = "docs_build_timeout_seconds must be between 900 and 1800. It is published to the documentation build producers as DOCS_BUILD_DEADLINE_SECONDS, and Cloud Tasks rejects a dispatchDeadline outside [15s, 1800s] for an HTTP target; the 900 floor keeps docs_build_timeout_seconds minus docs_build_launcher_margin_seconds positive."
  }
}

variable "docs_build_launcher_margin_seconds" {
  description = <<-DESC
    How much longer docs-launcher lives than the sandbox it is waiting on.

    The sandbox timeout is docs_build_timeout_seconds minus this, so it is
    strictly smaller than the launcher's request timeout and the dispatch
    deadline. That inequality is the point and it must not be tidied into
    equality. docs-launcher holds the Cloud Tasks request open for the whole
    build and is the ONLY party in the chain holding a database credential, so
    it has to outlive the sandbox in order to write the outcome. If the sandbox
    is allowed to run right up to the launcher's own deadline, the launcher is
    killed mid wait and records nothing: the row stays in building forever, no
    failed_at is ever written so the retry floor has nothing to measure from,
    nothing reconsiders it, and no log line says why. A build orphaned that way
    is invisible rather than noisy, which is why it earns a variable and a
    comment rather than a subtraction someone can smooth away.

    The margin is not padding. It covers the work the launcher does outside the
    sandbox wait: clone, checkout, `shards install --skip-postinstall`, then
    downloading the artifact, validating it parses, publishing it and writing
    status. `shards install` on a dependency heavy shard is the slow one.
  DESC
  type        = number
  default     = 300

  validation {
    condition     = var.docs_build_launcher_margin_seconds >= 300 && var.docs_build_launcher_margin_seconds <= 600
    error_message = "docs_build_launcher_margin_seconds must be between 300 and 600. Below 300 the launcher may be killed before it can record the build outcome, which orphans the build silently; above 600 it would exceed what the 900 floor on docs_build_timeout_seconds can absorb."
  }
}

variable "job_ads_url" {
  description = <<-DESC
    Where the job ad strip reads promotable jobs from. CrystalShards, CrystalDocs
    and CrystalBits all refuse to boot in production without it, by design.

    No default, because any default would hardcode the CrystalGigs hostname a
    third time. The caller builds it from app_domains["crystalgigs"], so the
    strip cannot end up pointed at a host the edge does not serve.
  DESC
  type        = string
}

variable "app_domains" {
  description = <<-DESC
    Map of app slug to the public origin it serves on. Lucky calls
    ENV.fetch("APP_DOMAIN") at boot in production and raises without it.

    Required, with no default, on purpose. These same four hostnames drive the
    managed certificates, the load balancer host rules and the DNS records, and
    a default here would be a second copy of them that nothing compares against
    the first. The failure that prevents is the quiet one: terraform validates,
    the plan is clean, the services boot, and the only symptom is an app
    generating absolute URLs and callbacks for a hostname the load balancer does
    not serve. The single source is local.sites in terraform/locals.sites.tf.
  DESC
  type        = map(string)
}

variable "search_console_properties" {
  description = <<-DESC
    Map of app slug to the Search Console property that site is registered as,
    published to the service as SEARCH_CONSOLE_PROPERTY.

    A property is a domain property ("sc-domain:example.org") or a URL prefix
    ("https://example.org/"). Which one a site is depends on how a human
    registered it, so it is passed in rather than derived from the origin: the
    two are different strings for the same site and the API rejects the wrong
    one.

    An app absent from this map, or mapped to "", is not wired to Search
    Console. That is a supported state, not a failure: the service reads the
    variable as optional and the stats page says the section is not
    configured. Fetching also needs this service's own account added as a user
    on the property, which no terraform in this repo can do.
  DESC
  type        = map(string)
  default     = {}
}

variable "docs_launcher_app_domain" {
  description = <<-DESC
    APP_DOMAIN for docs-launcher. It serves no public origin of its own and the
    value only feeds Lucky's route helper, so the caller passes the registry
    origin it belongs to. No default, for the same reason as app_domains: a
    hostname written here is a copy nothing reconciles.
  DESC
  type        = string
}

variable "request_concurrency" {
  description = "Concurrent requests per instance. Held below Cloud Run's default of 80 because each instance backs them with a connection pool of five"
  type        = number
  default     = 40
}

variable "request_timeout_seconds" {
  description = "Request timeout for the four public services. A page that has not answered in a minute is not going to"
  type        = number
  default     = 60
}

variable "health_path" {
  description = "Startup probe path. The apps mount health at /api/health, not /health, and a probe on the wrong path burns its whole failure budget on Lucky 404s and then fails the deploy looking like a broken app"
  type        = string
  default     = "/api/health"
}

variable "container_port" {
  description = "Port the container listens on. Cloud Run derives the injected PORT from this and config/server.cr binds to it"
  type        = number
  default     = 8080
}


variable "warm_scan_shards" {
  description = "How far down the popularity ranking one warming run looks. The scan is cheap: one query plus one batched lookup against the docs database, and no host traffic at all"
  type        = number
  default     = 200
}

variable "warm_max_builds" {
  description = "How many documentation builds one warming run commissions. This is the expensive bound: the build fleet is shared with the requests readers are waiting on, so throughput comes from the schedule rather than from the batch size"
  type        = number
  default     = 25
}
