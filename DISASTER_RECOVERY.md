# Disaster Recovery Runbook

## Scope

Covers data-loss recovery for the DynamoDB tables provisioned in
`deployments/dynamodb/`. Demonstrated against `chonky-products-production`
— **no dev environment is currently deployed in this AWS account** (only
`*-production` tables and the `chonky-tfstate-prod` state bucket exist; there
is no `chonky-tfstate-dev`/`chonky-tfstate-lock-dev`). If dev ever gets
provisioned via the README's Quick Start, the same procedure applies there
too, and to any other table in this stack — all of them have
`point_in_time_recovery_enabled = true` by default
(`deployments/dynamodb/variables.tf`).

**This runbook now operates on live production data.** `chonky-products-production`
currently holds 20 items (6 in the `Treat` category used by the `break` step
below). Read this whole document, and run `break --dry-run` first, before
running anything else in it.

## Failure scenario

**A bulk-delete bug or bad script deletes rows from the products table
in production.**

Realistic triggers: an admin-panel "remove discontinued items" feature with
an off-by-one filter, or `dynamodb_loader/seed.py` re-run against the wrong
`PRODUCTS_TABLE` environment variable. Neither requires an attacker — this
is the class of failure PITR exists for.

## Recovery objectives

| | Target | Why |
|---|---|---|
| RPO | ~0 (continuous backups) | DynamoDB PITR streams changes continuously once enabled; restorable to any second, not just a nightly snapshot. |
| RTO | < 15 minutes | Restore-table-to-point-in-time on a table this size (tens of items) typically completes in a few minutes; cutover is a one-parameter redeploy via the existing `chonky-cat-be` pipeline. |

## Backup strategy (already in place)

```hcl
# deployments/dynamodb/main.tf
resource "aws_dynamodb_table" "products" {
  ...
  point_in_time_recovery {
    enabled = var.point_in_time_recovery_enabled   # default: true
  }
}
```

No separate backup job to configure or maintain — this is AWS-managed
continuous backup, restorable to any point within the last 35 days.

## Recovery procedure

**This is live production data — no dev environment exists to rehearse
against instead.** `break` is destructive: it deletes real `Treat`-category
listings from the real storefront until step 5 is complete. Prefer running
this during a low-traffic window, and always run `break --dry-run` first to
confirm exactly what would be deleted before doing it for real.

### 1. Baseline (before the incident)

```bash
cd chonky-tf/disaster_recovery
python3 dr_demo.py baseline --table chonky-products-production
```

Scans the table, writes the full item set + count to
`dr_baseline_<table>_<timestamp>.json`, and prints the UTC timestamp to use
as the restore point. Keep this file and the printed timestamp — they're
your "before" evidence and your restore target.

### 2. Simulate the disaster

```bash
# Dry run first — lists what would be deleted, deletes nothing:
python3 dr_demo.py break --table chonky-products-production --category Treat --dry-run

# The real thing. --confirm must be the table name PLUS this suffix for any
# "-production" table (deliberately more than retyping the table name,
# since that's now the normal path here, not the mistake being guarded
# against):
python3 dr_demo.py break --table chonky-products-production --category Treat \
  --confirm chonky-products-production-I-UNDERSTAND-THIS-IS-PRODUCTION
```

Deletes every item in the `Treat` category (a scoped, realistic blast
radius — not the whole table; currently 6 of the table's 20 items). Take a
screenshot of the storefront/admin UI here showing the missing category —
this is your "before recovery" evidence the rubric asks for. Move on to
step 3 promptly; this category is genuinely missing from the live site
until then.

### 3. Restore

```bash
aws dynamodb restore-table-to-point-in-time \
  --source-table-name chonky-products-production \
  --target-table-name chonky-products-production-restored \
  --restore-date-time <timestamp printed by `baseline`, ISO 8601>

# poll until ACTIVE
aws dynamodb describe-table --table-name chonky-products-production-restored \
  --query "Table.TableStatus"
```

DynamoDB restores into a **new** table — it cannot restore in place or
rename a table. That's a real constraint, not a demo shortcut; see
Limitations below.

### 4. Verify

```bash
python3 dr_demo.py verify --table chonky-products-production-restored --baseline dr_baseline_chonky-products-production_<timestamp>.json
```

Diffs the restored table's item count and contents against the baseline
capture. Print/screenshot this — it's your proof the restore is complete
and correct, not just "the table exists."

### 5. Cutover (in `chonky-cat-be`)

The Lambdas read the table name from a deploy parameter, not a hardcoded
string (`template.yaml` → `!Ref ProductsTableName`), so cutover is a
one-line config change plus a redeploy through the pipeline that's already
built:

```bash
# in chonky-cat-be/samconfig.toml, [prod.deploy.parameters]:
# ProductsTableName=chonky-products-production-restored

sam build && sam deploy --config-env prod
# or: ./ci-deploy.sh --environment prod
```

Reload the storefront/admin and confirm the Treat category is back. This
is the moment to capture "confirmation the service was successfully
recovered."

### 6. Clean up (after recording)

- Revert `ProductsTableName` back to `chonky-products-production` in
  `samconfig.toml` and redeploy.
- Either copy the restored items back into `chonky-products-production` (a
  small boto3 batch-write) or leave `chonky-products-production-restored`
  and re-seed the original table with `dynamodb_loader/seed.py` — don't
  leave production pointing at a table named `-restored` long-term.
- Delete `chonky-products-production-restored` once you no longer need it
  as evidence.

## Limitations and lessons learned

- **No restore-in-place.** DynamoDB always restores to a new table name;
  there is no native rename. Production recovery therefore always involves
  either (a) a parameter/redeploy cutover like above, or (b) copying
  restored items back into the original table. Both add a manual step
  beyond "click restore."
- **~5 minute restore lag.** The latest restorable time is typically a few
  minutes behind now, not instantaneous — plan the demo's timing around
  this rather than trying to restore to "right now."
- **Scoped to DynamoDB.** This runbook doesn't cover:
  - **Cognito pool loss.** Verified against the live account
    (`aws cognito-idp list-user-pools`) — three pools currently exist, all
    production, no dev:
    - `chonky-admins-production` — owned by `deployments/cognito`, and
      actually used (its ID matches `CognitoUserPoolId` in
      `chonky-cat-be/samconfig.toml`). Pool deletion is not cleanly
      recoverable: `terraform apply` rebuilds the pool but not its user
      identities.
    - `amplifyAuthUserPool...` — the **real** customer pool. Owned by
      `chonky-cat-fe`'s Amplify Gen2 backend (`amplify/auth/resource.ts`,
      deployed via `ampx pipeline-deploy`/CDK on every Amplify build), not
      by this repo's Terraform — see `customer_cognito_pool_id`'s
      description in `deployments/lambdas/variables.tf`. Recovering it
      means working through `chonky-cat-fe`'s own pipeline, not
      `terraform apply` here.
    - `chonky-customers-production` — created by `deployments/cognito`'s
      unconditional `module "customers"` block, but **orphaned**: nothing
      in `samconfig.toml` or `lambdas/production.tfvars` references its ID.
      Worth cleaning up or gating behind a flag separately; not something
      this runbook fixes.
  - **Frontend hosting loss.** `admin-hosting` (S3 + CloudFront) is still
    fully recoverable via `terraform apply` from this repo's state, and now
    also redeploys automatically through `chonkycat-admin`'s GitHub Actions
    workflow (OIDC deploy role added in `deployments/admin-hosting/main.tf`).
    The customer storefront moved off S3/CloudFront onto AWS Amplify
    (`deployments/amplify-fe/`): the Amplify *app* itself (IAM role, branch
    config) is Terraform-managed and recoverable the same way, but the
    actual build and backend deploy run through Amplify's own git-triggered
    pipeline, outside this repo's `terraform apply`.

  Neither is exercised in this runbook — worth naming as known gaps rather
  than implying full DR coverage.
