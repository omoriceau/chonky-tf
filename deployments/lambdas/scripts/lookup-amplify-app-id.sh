#!/usr/bin/env bash
set -euo pipefail

# Terraform `external` data source contract: read a flat JSON object of
# query args from stdin, write a flat JSON object of string results to
# stdout. Used because the AWS provider only exposes aws_amplify_app as a
# *resource* (for creating one) — there's no data source to look up an
# existing app by name, only by id, which defeats the purpose when the id
# itself is what changes if the app is ever torn down and recreated.
QUERY=$(cat)
NAME=$(echo "$QUERY" | jq -r '.name')
REGION=$(echo "$QUERY" | jq -r '.region')

APP_ID=$(aws amplify list-apps --region "$REGION" \
    --query "apps[?name=='${NAME}'].appId | [0]" --output text)

if [ -z "$APP_ID" ] || [ "$APP_ID" = "None" ]; then
    echo "Amplify app named '$NAME' not found in region $REGION" >&2
    exit 1
fi

printf '{"app_id":"%s"}\n' "$APP_ID"
