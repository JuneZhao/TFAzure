#!/bin/bash
# Azure Resource Graph inventory for Terraform external data source.
# Output must be a single JSON object whose values are strings only.

set -euo pipefail

SUBSCRIPTION_ID="${1:-}"
if [[ -z "$SUBSCRIPTION_ID" ]]; then
  echo "query_resources.sh: subscription id argument is required" >&2
  exit 1
fi

if ! command -v az &>/dev/null; then
  echo "query_resources.sh: Azure CLI (az) is not installed or not on PATH" >&2
  exit 1
fi

if ! RESULT=$(az graph query \
  -q "Resources | project id, name, type, resourceGroup, location, tags" \
  --subscriptions "$SUBSCRIPTION_ID" \
  -o json 2>&1); then
  echo "query_resources.sh: az graph query failed:" >&2
  echo "$RESULT" >&2
  exit 1
fi

# Wrap graph JSON as one string (Terraform external data source requirement).
if command -v python3 &>/dev/null; then
  printf '%s' "$RESULT" | python3 -c 'import json,sys; print(json.dumps({"result": sys.stdin.read()}))'
elif command -v jq &>/dev/null; then
  ESCAPED=$(printf '%s' "$RESULT" | jq -Rs .)
  printf '{"result": %s}\n' "$ESCAPED"
else
  echo "query_resources.sh: install python3 or jq to format output (e.g. sudo apt install python3 jq)" >&2
  exit 1
fi
