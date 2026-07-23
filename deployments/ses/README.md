# SES Deployment

Verifies an SES domain identity (DKIM, custom MAIL FROM domain, bounce/complaint
tracking via SNS) so `chonky-cat-be`'s `email_service` Lambda can send order
confirmation, order-failure, and welcome/newsletter emails. DNS records are
created automatically via the Cloudflare provider — no manual DNS work needed.

## Why dev and prod verify different domains

SES domain identities and an AWS account's sandbox status are scoped to the
**account + region**, not to a Terraform stack. To keep dev and prod fully
independent (and avoid two Terraform states fighting over one shared AWS
resource), each env verifies its own domain:

- **dev** → `dev.chonkycat.ca`
- **prod** → `chonkycat.ca`

Both live in the same Cloudflare zone (`chonkycat.ca`), so `cloudflare_zone_id`
is the same for both — only `domain_name` differs.

## Setup

1. Set Cloudflare credentials (same token/zone as `deployments/custom-domain`):
   ```bash
   export TF_VAR_cloudflare_api_token="..."
   export TF_VAR_cloudflare_zone_id="..."
   ```

2. Update `sandbox_test_recipients` in `dev.tfvars` (and optionally
   `prod.tfvars`) with an inbox you can actually check. SES sandbox mode only
   delivers to verified recipients — this should match `DEV_EMAIL` /
   `deployments/lambdas`' `dev_email` var.

3. Deploy:
   ```bash
   terraform init -backend-config=backends/dev.hcl
   terraform plan -var-file=dev.tfvars
   terraform apply -var-file=dev.tfvars
   ```

   `apply` will hang for a few minutes on `aws_ses_domain_identity_verification`
   while it polls for AWS to see the Cloudflare TXT record — that's expected,
   not a hang. Repeat with `backends/prod.hcl` / `prod.tfvars` for prod.

4. Deploy `deployments/lambdas` after this — it reads `EMAIL_FROM_ADDRESS`,
   `SUPPORT_EMAIL`, and `SES_CONFIGURATION_SET` from this stack's outputs via
   remote state.

## Staying in / leaving SES sandbox

New SES accounts start in **sandbox mode**: you can only send *from* a
verified identity and *to* verified recipient addresses, and volume is capped.
This stack keeps everything in sandbox by design for now — moving out of
sandbox is an AWS Support Center case ("Request production access" under the
SES console), not something Terraform can do, since it's a manual AWS review
of your sending use case (relevant here: mention both transactional order
emails and the newsletter, and describe your bounce/complaint handling — the
SNS topics this stack creates are exactly what AWS asks about). Do this only
when you're ready to send to real, unverified customer addresses.

## Outputs

- `no_reply_address` — customer-facing sender (orders, newsletter)
- `admin_address` — internal/support sender
- `configuration_set_name` — pass to Lambdas as `SES_CONFIGURATION_SET`
- `bounce_topic_arn` / `complaint_topic_arn` — subscribe an email or Lambda to
  these if you want alerting; nothing subscribes to them by default
