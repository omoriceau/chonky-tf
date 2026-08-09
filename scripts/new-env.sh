#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Scaffolds backends/<env>.hcl + <env>.tfvars for every component, from the
# dev files as a base, for a brand new environment — so bucket/domain names
# are collision-safe by construction instead of discovered by trial and
# error (see: chonky-tfstate-production and chonky-admin-production, both
# squatted by other AWS accounts, 2026-08-04/05).
#
# Usage: scripts/new-env.sh <env-name> [--force]
#        scripts/new-env.sh <env-name> --remove [--yes]
#
# <env-name>: lowercase letters/digits/hyphens, e.g. "staging". Not dev/prod/
# production — those already exist.
# --force:  overwrite already-generated files for this env.
# --remove: delete the generated scaffold files for this env instead of
#           creating them. Local files only — see the warning it prints
#           before deleting anything.
# --yes:    skip the --remove confirmation prompt (for scripting).
#
# What it does NOT do: run terraform, or touch any AWS resource, in either
# mode. Review every generated file (domain names, callback URLs, personal
# emails/tokens copied from dev.tfvars) before applying, then deploy in the
# order printed at the end.
# ==============================================================================

log()  { echo -e "\033[0;32m[INFO]\033[0m  $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
die()  { echo -e "\033[0;31m[ERROR]\033[0m $*" >&2; exit 1; }

MODE="create"
FORCE=false
YES=false
ENV_NAME=""
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=true ;;
    --remove|--cleanup) MODE="remove" ;;
    --yes|-y) YES=true ;;
    -h|--help)
      sed -n '3,24p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *)
      [ -z "$ENV_NAME" ] || die "Unexpected extra argument: $arg"
      ENV_NAME="$arg"
      ;;
  esac
done

[ -n "$ENV_NAME" ] || die "Usage: $0 <env-name> [--force | --remove [--yes]]"
[[ "$ENV_NAME" =~ ^[a-z][a-z0-9-]{0,20}$ ]] || die "env name must be lowercase letters/digits/hyphens, starting with a letter (got: '$ENV_NAME')"
case "$ENV_NAME" in
  dev|prod|production) die "'$ENV_NAME' is a real, already-deployed environment — this script only manages scaffold files for NEW environments." ;;
esac

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Components that follow the backends/dev.hcl + dev.tfvars convention.
COMPONENTS=(
  secrets
  deployments/dynamodb
  deployments/cognito
  deployments/ses
  deployments/admin-hosting
  deployments/lambdas
  deployments/amplify-fe
  dynamodb_loader
  dev_image_loader
)

# ==============================================================================
# --remove: delete this env's generated files. Local scaffold only — never
# touches terraform state or AWS. If the env was actually applied, that
# leaves real resources (S3 buckets, DynamoDB tables, Cognito pools,
# CloudFront distributions, ...) running with no local config to manage
# them — the exact orphaned-resource problem this repo hit with
# chonky-tfstate-production and admin.chonkycat.ca-oac. Run `terraform
# destroy` per component (reverse deploy order) FIRST if that's the case.
# ==============================================================================
if [ "$MODE" = "remove" ]; then
  FILES=()
  f="bootstrap/${ENV_NAME}.tfvars"
  [ -f "$f" ] && FILES+=("$f")
  for comp in "${COMPONENTS[@]}"; do
    f="${comp}/backends/${ENV_NAME}.hcl"
    [ -f "$f" ] && FILES+=("$f")
    f="${comp}/${ENV_NAME}.tfvars"
    [ -f "$f" ] && FILES+=("$f")
  done

  if [ "${#FILES[@]}" -eq 0 ]; then
    log "No generated files found for '$ENV_NAME' — nothing to remove."
    exit 0
  fi

  echo
  warn "This deletes local scaffold files ONLY — it does not run terraform"
  warn "destroy or touch any AWS resource. If '$ENV_NAME' was ever actually"
  warn "applied, its S3 buckets/DynamoDB tables/Cognito pools/CloudFront"
  warn "distributions etc. will keep existing, just orphaned from any local"
  warn "config. Run terraform destroy for each component (reverse of the"
  warn "deploy order) FIRST if that's the case."
  warn "Note: *.tfvars is gitignored — deleted tfvars are NOT recoverable"
  warn "from git history. backends/*.hcl are tracked, so those are recoverable"
  warn "if committed."
  echo
  log "Files that would be deleted (${#FILES[@]}):"
  printf '  %s\n' "${FILES[@]}"
  echo

  if [ "$YES" != true ]; then
    read -r -p "Type '$ENV_NAME' to confirm deletion: " confirm
    [ "$confirm" = "$ENV_NAME" ] || die "Confirmation didn't match input — aborted, nothing deleted."
  fi

  rm -f "${FILES[@]}"
  log "Removed ${#FILES[@]} files for '$ENV_NAME'."
  exit 0
fi

# ==============================================================================
# create mode (default)
# ==============================================================================
command -v aws >/dev/null || die "aws CLI not found on PATH"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text) || die "Couldn't resolve AWS account id — check your AWS credentials."
[[ "$ACCOUNT_ID" =~ ^[0-9]{12}$ ]] || die "Unexpected AWS account id: '$ACCOUNT_ID'"

# Bucket/lock-table suffixes:
#  - S3 bucket names are globally unique across ALL AWS accounts, so the
#    state bucket gets the account id baked in — it can never collide with
#    anyone else's bucket, ever, no discovery cycle needed.
#  - DynamoDB table names are only unique within this account+region, so the
#    lock table just uses the plain env name, matching dev/prod's existing
#    convention.
STATE_SUFFIX="${ENV_NAME}-${ACCOUNT_ID}"
LOCK_SUFFIX="${ENV_NAME}"

log "New environment: $ENV_NAME"
log "AWS account:      $ACCOUNT_ID"
log "State bucket:      chonky-tfstate-${STATE_SUFFIX}"
log "Lock table:        chonky-tfstate-lock-${LOCK_SUFFIX}"
echo

# Components whose remote_state data source rebuilds the bucket name from
# var.state_env (see main.tf) rather than reading it from a static backend
# file — these need state_env added explicitly, since it has no default that
# matches this new environment's (account-id-suffixed) bucket.
STATE_ENV_COMPONENTS=(
  dynamodb_loader
  deployments/lambdas
)

needs_state_env() {
  local comp="$1"
  for c in "${STATE_ENV_COMPONENTS[@]}"; do
    [ "$c" = "$comp" ] && return 0
  done
  return 1
}

check_overwrite() {
  local f="$1"
  if [ -e "$f" ] && [ "$FORCE" != true ]; then
    die "$f already exists — pass --force to overwrite."
  fi
}

GENERATED=()

# --- bootstrap ---------------------------------------------------------------
# bootstrap has no per-env tfvars today (just variables.tf's mutable
# default — the exact footgun this script exists to avoid repeating). Giving
# it one here too, rather than hand-editing variables.tf per environment.
BOOTSTRAP_TFVARS="bootstrap/${ENV_NAME}.tfvars"
check_overwrite "$BOOTSTRAP_TFVARS"
cat > "$BOOTSTRAP_TFVARS" <<EOF
env           = "${ENV_NAME}"
bucket_suffix = "${STATE_SUFFIX}"
EOF
GENERATED+=("$BOOTSTRAP_TFVARS")

# --- each component ------------------------------------------------------
for comp in "${COMPONENTS[@]}"; do
  dev_hcl="${comp}/backends/dev.hcl"
  dev_tfvars="${comp}/dev.tfvars"
  new_hcl="${comp}/backends/${ENV_NAME}.hcl"
  new_tfvars="${comp}/${ENV_NAME}.tfvars"

  if [ ! -f "$dev_hcl" ] || [ ! -f "$dev_tfvars" ]; then
    warn "Skipping $comp — no backends/dev.hcl or dev.tfvars found."
    continue
  fi

  check_overwrite "$new_hcl"
  check_overwrite "$new_tfvars"

  sed \
    -e "s/chonky-tfstate-dev/chonky-tfstate-${STATE_SUFFIX}/g" \
    -e "s#env/dev/#env/${ENV_NAME}/#g" \
    -e "s/chonky-tfstate-lock-dev/chonky-tfstate-lock-${LOCK_SUFFIX}/g" \
    -e "s#backends/dev\.hcl#backends/${ENV_NAME}.hcl#g" \
    "$dev_hcl" > "$new_hcl"
  GENERATED+=("$new_hcl")

  sed \
    -e "s/\"dev\"/\"${ENV_NAME}\"/g" \
    -e "s/dev\.chonkycat\.ca/${ENV_NAME}.chonkycat.ca/g" \
    -e "s/admin\.chonkycat\.ca/${ENV_NAME}-admin.chonkycat.ca/g" \
    "$dev_tfvars" > "$new_tfvars"

  if needs_state_env "$comp"; then
    printf '\nstate_env = "%s"\n' "$STATE_SUFFIX" >> "$new_tfvars"
  fi
  GENERATED+=("$new_tfvars")
done

echo
log "Generated ${#GENERATED[@]} files:"
printf '  %s\n' "${GENERATED[@]}"
echo
warn "Review before applying — this is a scaffold, not a finished config:"
warn "  - Domain/callback URLs (ses, admin-hosting, cognito) were rewritten to"
warn "    <env>-prefixed subdomains — double check they're what you want, and"
warn "    that DNS/Cloudflare records for them exist."
warn "  - Cloudflare token, sandbox_test_recipients, admin_alert_email etc."
warn "    were copied from dev.tfvars verbatim — same account/zone assumed."
warn "  - dev_image_loader / dynamodb_loader are optional dev-convenience seeders."
echo
log "Deploy in this order (matches README's Deployment Order):"
cat <<EOF
  1. cd bootstrap && terraform apply -var-file=${ENV_NAME}.tfvars
  2. cd secrets && terraform init -backend-config=backends/${ENV_NAME}.hcl && terraform apply -var-file=${ENV_NAME}.tfvars
  3. cd deployments/dynamodb && terraform init -backend-config=backends/${ENV_NAME}.hcl && terraform apply -var-file=${ENV_NAME}.tfvars
  4. cd deployments/cognito && terraform init -backend-config=backends/${ENV_NAME}.hcl && terraform apply -var-file=${ENV_NAME}.tfvars
  5. cd deployments/ses && terraform init -backend-config=backends/${ENV_NAME}.hcl && terraform apply -var-file=${ENV_NAME}.tfvars
  6. cd deployments/lambdas && terraform init -backend-config=backends/${ENV_NAME}.hcl && terraform apply -var-file=${ENV_NAME}.tfvars
  7. cd deployments/admin-hosting && terraform init -backend-config=backends/${ENV_NAME}.hcl && terraform apply -var-file=${ENV_NAME}.tfvars
EOF
