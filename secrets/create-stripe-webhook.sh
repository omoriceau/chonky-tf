#!/bin/bash
# Creates the Stripe webhook endpoint used by StripeWebhookFunction (chonky-cat-be)
# and prints an `export TF_VAR_stripe_webhook_secret=...` line on stdout, so the
# real signing secret never has to be copy-pasted from the Stripe dashboard.
#
# Usage:
#   eval "$(./create-stripe-webhook.sh)"
#   terraform apply -var-file=dev.tfvars
#
# If an endpoint for this URL already exists, Stripe will not re-expose its
# secret (it's only returned once, at creation time). Pass --recreate to
# delete and recreate the endpoint with a fresh secret -- this immediately
# invalidates the old secret, so only do this when you're ready to redeploy
# secrets/ right after.
#
# Requires: curl, jq, and a Stripe secret key in $TF_VAR_stripe_secret_key
# (or $STRIPE_SECRET_KEY).

set -euo pipefail

WEBHOOK_URL="${WEBHOOK_URL:-https://api.chonkycat.ca/webhook}"
STRIPE_KEY="${TF_VAR_stripe_secret_key:-${STRIPE_SECRET_KEY:-}}"
ENABLED_EVENTS=("payment_intent.succeeded" "payment_intent.payment_failed")
RECREATE=false

for arg in "$@"; do
  case "$arg" in
    --recreate) RECREATE=true ;;
    *) ;;
  esac
done

log() { echo "[create-stripe-webhook] $*" >&2; }
die() { log "ERROR: $*"; exit 1; }

command -v curl >/dev/null || die "curl is required"
command -v jq   >/dev/null || die "jq is required"
[ -n "$STRIPE_KEY" ] || die "Set TF_VAR_stripe_secret_key (or STRIPE_SECRET_KEY) before running this script"

log "Looking for an existing webhook endpoint at $WEBHOOK_URL"

EXISTING_ID=$(curl -sS https://api.stripe.com/v1/webhook_endpoints \
  -u "${STRIPE_KEY}:" \
  -G --data-urlencode "limit=100" \
  | jq -r --arg url "$WEBHOOK_URL" '.data[]? | select(.url == $url) | .id' | head -n1)

if [ -n "$EXISTING_ID" ]; then
  if [ "$RECREATE" != true ]; then
    die "Endpoint already exists (${EXISTING_ID}) and Stripe won't re-expose its secret. Re-run with --recreate to delete and recreate it with a fresh secret, or fetch the existing one from the Stripe dashboard."
  fi
  log "Deleting existing endpoint ${EXISTING_ID} so it can be recreated with a fresh secret"
  curl -sS -X DELETE "https://api.stripe.com/v1/webhook_endpoints/${EXISTING_ID}" \
    -u "${STRIPE_KEY}:" >/dev/null
fi

log "Creating webhook endpoint for $WEBHOOK_URL"
DATA_ARGS=(--data-urlencode "url=$WEBHOOK_URL")
for evt in "${ENABLED_EVENTS[@]}"; do
  DATA_ARGS+=(--data-urlencode "enabled_events[]=$evt")
done

RESPONSE=$(curl -sS https://api.stripe.com/v1/webhook_endpoints \
  -u "${STRIPE_KEY}:" \
  "${DATA_ARGS[@]}")

ERROR_MSG=$(echo "$RESPONSE" | jq -r '.error.message // empty')
[ -z "$ERROR_MSG" ] || die "Stripe API error: $ERROR_MSG"

SECRET=$(echo "$RESPONSE" | jq -r '.secret // empty')
[ -n "$SECRET" ] || die "Stripe response did not include a signing secret: $RESPONSE"

log "Webhook endpoint ready: $(echo "$RESPONSE" | jq -r '.id') -> $WEBHOOK_URL"
echo "export TF_VAR_stripe_webhook_secret=\"$SECRET\""
