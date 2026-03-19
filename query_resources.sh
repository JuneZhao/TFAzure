#!/bin/bash

# Azure Resource Graph full resource inventory query
# Terraform external data source requires output format:
# { "key": "string_value" }

set -e

SUBSCRIPTION_ID="$1"

# Execute Resource Graph query
RESULT=$(az graph query \
  -q "Resources | project name, type, resourceGroup, location, tags" \
  --subscriptions "$SUBSCRIPTION_ID" \
  -o json)

# Ensure jq exists
if ! command -v jq &> /dev/null; then
  echo '{"error":"jq is required but not installed"}'
  exit 1
fi

# Wrap JSON result as string to satisfy Terraform external data source requirements
ESCAPED=$(printf "%s" "$RESULT" | jq -Rs .)

echo "{\"result\": $ESCAPED}"