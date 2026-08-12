# GitHub Repository Setup Requirements

For continuous deployment to work, you need to configure the following in your GitHub repository:

## 1. Repository Secrets

Go to Settings → Secrets and variables → Actions and add:

### Required Secrets

Eleven names, and the workflows read no others. Four are mandatory, seven are
feature switches.

Two authenticate CI to Google Cloud, and nothing deploys without them:

- `GCP_SA_KEY` - Service account JSON key CI authenticates with
- `GCP_PROJECT_ID` - The Google Cloud project to deploy into

Four are third party application credentials. The deploy workflow's
`Populate the application secrets` step reads them and adds a Secret Manager
version from each, so these are the only place an operator enters a value. Two of
the four are mandatory:

| GitHub secret | What it unblocks |
| --- | --- |
| `CRYSTALGIGS_STRIPE_SECRET_KEY` | CrystalGigs payments, server side. Required: the service exits at boot without it |
| `CRYSTALGIGS_STRIPE_PUBLISHABLE_KEY` | CrystalGigs payments, browser side. Required, same reason |
| `CRYSTALGIGS_RESEND_KEY` | CrystalGigs mail, which delivers job applications. Optional |
| `CRYSTALBITS_RESEND_KEY` | CrystalBits mail, which sends the newsletter. Optional |

Five are the discovery host credentials, one per git host the registry crawls,
except Bitbucket, which needs two. Every one of them is optional and every one is
independent:

| GitHub secret | Host it turns on |
| --- | --- |
| `DISCOVERY_GITHUB_TOKEN` | `github.com`. Most of the Crystal ecosystem is here, so this is the one that matters most |
| `GITLAB_TOKEN` | `gitlab.com` |
| `CODEBERG_TOKEN` | `codeberg.org` |
| `BITBUCKET_USERNAME` | `bitbucket.org`, with the secret below. Neither half alone turns it on |
| `BITBUCKET_APP_PASSWORD` | `bitbucket.org`, with the secret above |

**With none of those five set, the registry discovers nothing and stays empty.**
The scheduled sweep still runs and still succeeds: it reports each host as skipped
and names the variable that would enable it, so a run that indexed zero shards
reads as nobody having given it a token, not as an empty ecosystem. Adding one
repository secret is the entire act of turning a host on. There is no code change
and no Terraform change.

`DISCOVERY_GITHUB_TOKEN` is the odd name in that table, and it has to be. GitHub
reserves the `GITHUB_` prefix for secret names, so a repository secret called
`GITHUB_TOKEN` cannot be created at all, and `${{ secrets.GITHUB_TOKEN }}` in a
workflow always resolves to the installation token GitHub mints for that run.
That token is present, non empty, scoped to this repository and expires in an
hour, so using it would pass every check the populate step makes and produce a
sweep that authenticates successfully and finds nothing on github.com. Do not
rename this to match its neighbours. The Secret Manager container is still
`github-token` and the variable the crawler reads is still `GITHUB_TOKEN`; the
alias exists only on the input side.

Terraform creates the nine Secret Manager containers those application and
discovery secrets populate, and never a version for any of them. No third party
credential is a Terraform variable and none is written into Terraform state.
`GCP_SA_KEY` and `GCP_PROJECT_ID` are not among the nine: they are CI's own
credentials and never reach Secret Manager.

CrystalGigs will not start until its two Stripe keys have a version, and the
populate step fails closed rather than deploying without them. Everything else
here is a feature switch: a missing mail key disables mail on one service, a
missing host token disables discovery of one host, and the deploy carries on.
CrystalShards, CrystalDocs, CrystalBits and docs-launcher hold no mandatory third
party secret and serve on a clean apply with none of the seven optional secrets
set; CrystalGigs is the one service that needs a value before it can serve.
[`.github/SETUP.md`](.github/SETUP.md) has the container ids, how to mint the
Google Cloud key, and how to add a version by hand.

## 2. Service Account Permissions

The CI identity deploys the services and runs Terraform, so it needs permission over
everything Terraform manages, not only Cloud Run and Artifact Registry:

- `roles/run.admin`
- `roles/artifactregistry.writer`
- `roles/cloudsql.client`
- `roles/compute.loadBalancerAdmin`
- `roles/dns.admin`
- `roles/secretmanager.admin`
- `roles/iam.serviceAccountUser`
- `roles/storage.admin`
- `roles/serviceusage.serviceUsageAdmin`
- `roles/cloudscheduler.admin`
- `roles/iam.roleAdmin`

The last two are what the discovery schedule costs. `roles/cloudscheduler.admin`
creates the one Cloud Scheduler job in the stack.

`roles/iam.roleAdmin` is the one worth pausing on, because it is
project-wide authority to create and edit custom IAM roles, not a permission
anything at runtime holds. It buys exact least privilege for the schedule: the
identity Cloud Scheduler calls the Cloud Run Jobs API as holds a custom role whose
permission list is exactly `run.jobs.run`, because no predefined role is that
small. `roles/run.invoker` also carries `run.instances.invoke` and
`run.routes.invoke`, and `roles/run.jobsExecutor` also carries
`run.executions.cancel`, which is the ability to kill a sweep in progress. If you
would rather not give CI this role, create
`projects/<project>/roles/runDiscoveryJob` by hand once and remove
`terraform/modules/scheduler/resource.google_project_iam_custom_role.run_job.tf`,
replacing the reference with a `data` lookup. The trade is a role nothing
reconciles against the binding that uses it.

[`.github/SETUP.md`](.github/SETUP.md) holds the commands that create this
identity, bind the roles, and configure Artifact Registry. Follow it there rather
than duplicating the setup here.

## 3. Branch Protection Rules

Configure for `main` branch:

- ✅ Require pull request reviews before merging
- ✅ Require status checks to pass before merging
  - `test-crystalshards`
  - `test-crystaldocs`
  - `test-crystalgigs`
  - `build-images`
- ✅ Require branches to be up to date before merging
- ✅ Include administrators

## 4. GitHub Environments

Create environments for deployment stages:

### `staging`

- No required reviewers
- Deployment branches: `main`, `staging/*`
- Secrets: Can inherit from repository

### `production`

- Required reviewers: 1
- Deployment branches: `main`
- Wait timer: 5 minutes
- Secrets: Production-specific overrides

## 5. Webhook Configuration

For CrystalGigs Stripe integration:

1. Add webhook endpoint: `https://crystalgigs.com/webhooks/stripe`
2. Events to listen for:
   - `checkout.session.completed`
   - `invoice.payment_succeeded`
   - `customer.subscription.deleted`

## 6. Actions Permissions

Settings → Actions → General:

- Actions permissions: Allow all actions and reusable workflows
- Workflow permissions: Read and write permissions
- ✅ Allow GitHub Actions to create and approve pull requests

## 7. Container Images

CI pushes to Artifact Registry:

- Repository `docker-images` in `us-central1`
- Image path: `us-central1-docker.pkg.dev/<project>/docker-images/<image>:<sha>`
- Tag: the full 40 character commit SHA
- Five images: `crystalshards`, `crystaldocs`, `crystalgigs`, `crystalbits`, `docs-build`

No `latest` tag is pushed or referenced. That is deliberate rather than an omission:
it means nothing can resolve to a tag the pipeline did not produce.

## 8. Deployment Triggers

Deployments happen on:

- Push to `main` → Deploy to staging
- GitHub release → Deploy to production
- Manual workflow dispatch → Deploy to any environment

## 9. Cost Alerts

Set up billing alerts in GCP:

- Alert at $50/month
- Alert at $100/month
- Hard cap at $150/month (optional)

## 10. Monitoring Integration

GitHub Actions will send metrics to:

- Deployment success/failure → Slack
- Application errors → Sentry
- Performance metrics → Cloud Monitoring, published by Cloud Run
