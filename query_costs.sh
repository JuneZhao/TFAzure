#!/bin/bash
# Azure Cost Management query for Terraform external data source.
# Output must be a single JSON object whose values are strings only.

set -euo pipefail

SUBSCRIPTION_ID="${1:-}"
if [[ -z "$SUBSCRIPTION_ID" ]]; then
  echo "query_costs.sh: subscription id argument is required" >&2
  exit 1
fi

if ! command -v az &>/dev/null; then
  echo "query_costs.sh: Azure CLI (az) is not installed or not on PATH" >&2
  exit 1
fi

SCOPE="/subscriptions/$SUBSCRIPTION_ID"
URL="https://management.azure.com${SCOPE}/providers/Microsoft.CostManagement/query?api-version=2023-03-01"
BODY='{
  "type": "AmortizedCost",
  "timeframe": "Last7Days",
  "dataset": {
    "granularity": "None",
    "aggregation": {
      "totalCost": {
        "name": "PreTaxCost",
        "function": "Sum"
      }
    },
    "grouping": [
      {
        "type": "Dimension",
        "name": "ResourceId"
      }
    ]
  }
}'

if ! RESULT=$(az rest \
  --method post \
  --url "$URL" \
  --headers Content-Type=application/json \
  --body "$BODY" \
  -o json 2>&1); then
  echo "query_costs.sh: cost query failed:" >&2
  echo "$RESULT" >&2
  exit 1
fi

# Wrap JSON as one string (Terraform external data source requirement).
if command -v python3 &>/dev/null; then
  printf '%s' "$RESULT" | python3 -c 'import json,sys; print(json.dumps({"result": sys.stdin.read()}))'
elif command -v jq &>/dev/null; then
  ESCAPED=$(printf '%s' "$RESULT" | jq -Rs .)
  printf '{"result": %s}\n' "$ESCAPED"
else
  echo "query_costs.sh: install python3 or jq to format output (e.g. sudo apt install python3 jq)" >&2
  exit 1
fi
