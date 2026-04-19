# Azure Subscription Inventory

[中文说明](README.md)

An Azure subscription inventory, cost ranking, and alerting tool built with Terraform + Azure AzAPI provider.
This project is implemented with **pure Terraform** (no `az`, `jq`, or `python3` runtime dependency) and supports **multi-subscription aggregation**, **cost alerts**, and **history snapshot archiving**.

## Capabilities

- Pull resource inventory via **Azure Resource Graph** (provider-level action, azapi v2):
  `id / name / type / kind / sku / resourceGroup / location / subscriptionId / tags`
- Query cost data via **Cost Management Query API** (azapi v2), with configurable timeframe and cost type (`AmortizedCost` / `ActualCost`)
- Generate resource-group hierarchy, resource-type/location distribution, and full untagged resource list
- Top 10 resource types + Top N most expensive resources
- **Cost alerting**: mark/highlight over-threshold resources using `cost_alert_threshold`, and expose `over_threshold_resources`
- **Multi-subscription**: root module iterates over `subscription_ids` and produces per-subscription reports plus aggregated cross-subscription reports
- **History archiving**: when `enable_history = true`, each apply copies the current `reports/` snapshot into `reports/_history/<timestamp>/`

## Project Structure

```text
.
├── main.tf                               # Root entrypoint (for_each over subscription_ids)
├── variables.tf / outputs.tf / provider.tf / versions.tf
├── terraform.tfvars(.example)
└── modules/subscription_inventory/
    ├── main.tf      # azapi_resource_action: ResourceGraph + CostManagement
    ├── locals.tf    # data shaping / statistics / alerts / Markdown
    ├── variables.tf / outputs.tf / versions.tf
```

## Prerequisites

### Runtime

- **Linux** host required (Azure VM / any Linux / WSL; native Windows execution is not supported)
- Terraform `>= 1.5.0`
- Additional tools for `enable_history = true`: `bash`, `cp` (available in almost all Linux distros)

### Provider Versions

- `hashicorp/azurerm ~> 4.0`
- `azure/azapi ~> 2.0`
- `hashicorp/local ~> 2.4`
- `hashicorp/null ~> 3.2`

### Azure Permissions (for each target subscription)

- `Reader` (for inventory)
- `Cost Management Reader` (for cost data)

`resource_provider_registrations = "none"` is enabled in the provider config to ensure this project **never mutates tenant-level provider registrations**.

## Authentication

Recommended order:

1. **Azure CLI session** (most convenient for local development)
   ```bash
   az login
   ```
2. **Environment variables** (recommended for CI)
   ```bash
   export ARM_TENANT_ID=...
   export ARM_SUBSCRIPTION_ID=...     # any accessible subscription; actual targets are in tfvars
   export ARM_CLIENT_ID=...
   export ARM_CLIENT_SECRET=...       # or ARM_USE_OIDC=true
   ```
3. **Managed Identity** (Azure VM / ACI / AKS / GitHub Actions OIDC)
   ```hcl
   use_msi                    = true
   managed_identity_client_id = "<UAMI Client ID>"
   ```

## Usage

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars, at minimum fill tenant_id + subscription_ids

terraform init
terraform plan
terraform apply
```

After apply, outputs are written under `reports/`:

```text
reports/
├── _aggregated_summary.json          # Cross-subscription summary
├── _combined_report.md               # Combined Markdown report
├── <subscription_id>/
│   ├── inventory.json
│   ├── summary.json
│   └── inventory_report.md
└── _history/                         # Exists only when enable_history=true
    ├── 2026-04-17T091500Z/           # Snapshot (timestamp format from history_timestamp_format)
    │   ├── _aggregated_summary.json
    │   ├── _combined_report.md
    │   └── <subscription_id>/...
    └── 2026-04-18T091500Z/
        └── ...
```

## Input Variables (Root Module)

| Variable | Type | Required | Default | Description |
|---|---|---|---|---|
| `tenant_id` | string | Yes | - | Azure AD tenant ID |
| `subscription_ids` | list(string) | Yes | - | List of subscription IDs to inventory |
| `use_msi` | bool | No | `false` | Whether to use managed identity authentication |
| `managed_identity_client_id` | string | No | `""` | UAMI client ID (effective only when `use_msi=true`) |
| `top_n_cost_resources` | number | No | `10` | Number of top cost resources per subscription |
| `cost_timeframe` | string | No | `Last7Days` | `Last7Days` / `MonthToDate` / `BillingMonthToDate` |
| `cost_type` | string | No | `AmortizedCost` | `AmortizedCost` / `ActualCost` |
| `cost_alert_threshold` | number | No | `0` | Cost alert threshold per resource (`0` disables alerting) |
| `reports_dir` | string | No | `reports` | Output directory for generated artifacts |
| `enable_history` | bool | No | `false` | Enable history snapshot archiving |
| `history_timestamp_format` | string | No | `YYYY-MM-DD'T'hhmmss'Z'` | Timestamp format for history folders (`formatdate` syntax) |

## Outputs (Terraform Outputs)

- `inventories` - `map(subscription_id -> inventory)`
- `summaries` - `map(subscription_id -> summary)`, including full `untagged_resources` and `over_threshold_resources`
- `markdown_reports` - `map(subscription_id -> markdown)`
- `top_cost_resources_by_subscription` - `map(subscription_id -> list)`
- `over_threshold_resources_by_subscription` - `map(subscription_id -> list)`
- `aggregated_summary` - cross-subscription aggregated summary (including `total_over_threshold`)
- `combined_markdown_report` - merged Markdown report
- `history_snapshot_dir` - archive directory for current apply (`null` when `enable_history=false`)

## Cost Alerting

Set `cost_alert_threshold > 0` to surface over-threshold resources in multiple places:

- In Markdown `Top Cost Resources`, over-threshold rows are prefixed with `**[ALERT]**`
- Additional Markdown section: `## Cost Alerts (> <threshold>)`
- Per-subscription summary includes `over_threshold_resources`, `over_threshold_count`, and `cost_alert_threshold`
- Aggregated output includes `aggregated_summary.total_over_threshold`

Threshold unit follows the Cost Management `Currency` field (usually the subscription billing currency).

## History Archiving

Implementation details:

- Terraform state only tracks the "latest" artifacts (`reports/<sub_id>/`, `reports/_aggregated_summary.json`, etc.)
- History snapshots are created via `null_resource` + `local-exec` with `cp -r` and are **not** in Terraform state
- Benefit: unlimited applies do not destroy old snapshots; state file does not grow with history
- Trade-off: Linux host required; `terraform destroy` does not remove history folders (`rm -rf reports/_history/` manually if needed)

Snapshot path for each apply is exposed in `history_snapshot_dir`.

## Upgrade from v1

If you are upgrading from early versions (azurerm 3.x / azapi 1.x / bash scripts), run `terraform init -upgrade`.
`local_file` resources were migrated from singleton to `for_each`; first plan may show destroy + create for local JSON/Markdown files only, which is expected.

## Cost Data Semantics

- Time window: `cost_timeframe`
- Cost type: `cost_type`
- Aggregation: grouped by `ResourceId` with `PreTaxCost` sum
- Notes:
  - Cost data typically has **8-24 hours** latency
  - Recently deleted resources may still appear in cost data; `name/type/resource_group` may be `unknown`
  - Only positive costs are currently included (`cost > 0`; refunds/credits are filtered out)

## Known Limitations

- **Resource Graph hard limit of 1000 rows per query**: `modules/subscription_inventory/main.tf` uses `options.top = 1000`. Large subscriptions may be truncated. For full coverage, implement pagination with `$skipToken` (hard to do elegantly in pure Terraform), or prefetch with scripts and ingest via `jsondecode(file())`.
- **Positive costs only**: refund/credit negative values are filtered out. To include them, relax `if cost_info.cost > 0` in `locals.tf`.
- **No currency-aware threshold map**: `cost_alert_threshold` is a raw number. For mixed-currency subscriptions, run separate applies per currency or extend to a `map(currency, number)` design.

## FAQ

**Q: Why do I get 403 from Cost Management query?**  
A: Each target subscription must have `Cost Management Reader`. It is independent from `Reader`.

**Q: Why is Resource Graph query empty?**  
A: Check `Reader` scope assignment; newly created subscriptions may take several minutes to appear in ARG index.

**Q: In multi-subscription mode, one subscription failure breaks the whole apply?**  
A: Temporarily remove that subscription from `subscription_ids`, then re-run.

**Q: Disk usage keeps growing after `enable_history=true`?**  
A: Use external cleanup (cron/systemd timer), for example:

```bash
find reports/_history -maxdepth 1 -mindepth 1 -mtime +30 -exec rm -rf {} +
```

## Minimal Self-Check

```bash
terraform init -upgrade
terraform validate
terraform fmt -recursive -check
terraform plan
```
