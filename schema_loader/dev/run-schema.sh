#!/bin/bash
set -e

# All values injected as env vars from Terraform — no escaping issues
echo "Encoding SQL files..."
SCHEMA=$(base64 -w 0 "$SCHEMA_PATH")
SEED=$(base64 -w 0 "$SEED_PATH")

MAX_RETRIES=5
RETRY_COUNT=0
COMMAND_ID=""

echo "Sending SSM command to instance $INSTANCE_ID..."

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  echo "Attempt $(( RETRY_COUNT + 1 ))/$MAX_RETRIES..."

  COMMAND_ID=$(aws ssm send-command \
    --region "$REGION" \
    --instance-ids "$INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters commands="[
      \"echo $SCHEMA | base64 -d > /tmp/01-schema.sql\",
      \"echo $SEED | base64 -d > /tmp/02-seed.sql\",
      \"PGPASSWORD='$DB_PASS' psql -h $DB_HOST -U $DB_USER -d $DB_NAME -f /tmp/01-schema.sql\",
      \"PGPASSWORD='$DB_PASS' psql -h $DB_HOST -U $DB_USER -d $DB_NAME -f /tmp/02-seed.sql\"
    ]" \
    --query "Command.CommandId" \
    --output text 2>/dev/null || true)

  if [ -z "$COMMAND_ID" ] || [ ${#COMMAND_ID} -lt 36 ]; then
    echo "Failed to get valid CommandId, retrying in 10s..."
    RETRY_COUNT=$(( RETRY_COUNT + 1 ))
    sleep 10
    continue
  fi

  echo "SSM Command ID: $COMMAND_ID"
  break
done

if [ -z "$COMMAND_ID" ] || [ ${#COMMAND_ID} -lt 36 ]; then
  echo "ERROR: Failed to send SSM command after $MAX_RETRIES attempts"
  exit 1
fi

echo "Waiting for command to complete..."
aws ssm wait command-executed \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --region "$REGION" || true

sleep 5

STATUS=$(aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --region "$REGION" \
  --query "Status" \
  --output text)

echo "SSM Status: $STATUS"

# Print output for debugging
aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --region "$REGION" \
  --query "StandardOutputContent" \
  --output text

aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --region "$REGION" \
  --query "StandardErrorContent" \
  --output text

[ "$STATUS" = "Success" ] || exit 1
