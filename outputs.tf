locals {
  inventories = {
    for sid, m in module.subscription_inventory : sid => m.inventory
  }

  summaries = {
    for sid, m in module.subscription_inventory : sid => m.summary
  }

  markdown_reports = {
    for sid, m in module.subscription_inventory : sid => m.markdown_report
  }

  top_cost_resources_by_sub = {
    for sid, m in module.subscription_inventory : sid => m.top_cost_resources
  }

  over_threshold_by_sub = {
    for sid, m in module.subscription_inventory : sid => m.over_threshold_resources
  }

  # -----------------------------
  # Cross-subscription aggregation
  # -----------------------------
  aggregated_summary = {
    subscription_count    = length(var.subscription_ids)
    subscriptions         = var.subscription_ids
    total_resources       = sum([for s in local.summaries : s.total_resources])
    total_resource_groups = sum([for s in local.summaries : s.total_resource_groups])
    total_untagged        = sum([for s in local.summaries : s.untagged_resource_count])
    total_over_threshold  = sum([for s in local.summaries : s.over_threshold_count])
    cost_timeframe        = var.cost_timeframe
    cost_type             = var.cost_type
    cost_alert_threshold  = var.cost_alert_threshold
    per_subscription = {
      for sid, s in local.summaries : sid => {
        name                    = s.subscription_name
        total_resources         = s.total_resources
        total_resource_groups   = s.total_resource_groups
        untagged_resource_count = s.untagged_resource_count
        over_threshold_count    = s.over_threshold_count
      }
    }
  }

  combined_header = join("\n", concat(
    [
      "# Azure Multi-Subscription Inventory",
      "",
      "- Subscriptions: ${length(var.subscription_ids)}",
      "- Total Resources: ${local.aggregated_summary.total_resources}",
      "- Total Resource Groups: ${local.aggregated_summary.total_resource_groups}",
      "- Total Untagged Resources: ${local.aggregated_summary.total_untagged}",
      "- Cost Window: ${var.cost_timeframe} (${var.cost_type})",
    ],
    var.cost_alert_threshold > 0 ? [
      "- Cost Alert Threshold: ${var.cost_alert_threshold}",
      "- Resources Over Threshold: ${local.aggregated_summary.total_over_threshold}",
    ] : []
  ))

  combined_markdown_report = join("\n\n---\n\n", concat(
    [local.combined_header],
    [for sid in var.subscription_ids : local.markdown_reports[sid]]
  ))

  # Captured once per plan. Used only as a trigger / path component for the
  # history snapshot; does not cause recreation of any tracked files.
  history_stamp = formatdate(var.history_timestamp_format, plantimestamp())
  history_root  = "${path.root}/${var.reports_dir}/_history/${local.history_stamp}"
}

# -----------------------------
# Terraform outputs
# -----------------------------
output "inventories" {
  description = "Per-subscription inventory keyed by subscription ID."
  value       = local.inventories
}

output "summaries" {
  description = "Per-subscription summary keyed by subscription ID."
  value       = local.summaries
}

output "markdown_reports" {
  description = "Per-subscription Markdown report keyed by subscription ID."
  value       = local.markdown_reports
}

output "top_cost_resources_by_subscription" {
  description = "Top-N cost resources keyed by subscription ID."
  value       = local.top_cost_resources_by_sub
}

output "over_threshold_resources_by_subscription" {
  description = "Resources exceeding cost_alert_threshold, keyed by subscription ID."
  value       = local.over_threshold_by_sub
}

output "aggregated_summary" {
  description = "Cross-subscription aggregated statistics."
  value       = local.aggregated_summary
}

output "combined_markdown_report" {
  description = "Single Markdown report combining all subscriptions."
  value       = local.combined_markdown_report
}

output "history_snapshot_dir" {
  description = "Directory where the current apply's history snapshot was written (null when enable_history = false)."
  value       = var.enable_history ? local.history_root : null
}

# -----------------------------
# Local file artifacts - the "latest" snapshot, always overwritten.
# -----------------------------
resource "local_file" "inventory_json" {
  for_each = local.inventories

  content  = jsonencode(each.value)
  filename = "${path.root}/${var.reports_dir}/${each.key}/inventory.json"
}

resource "local_file" "summary_json" {
  for_each = local.summaries

  content  = jsonencode(each.value)
  filename = "${path.root}/${var.reports_dir}/${each.key}/summary.json"
}

resource "local_file" "inventory_report_md" {
  for_each = local.markdown_reports

  content  = each.value
  filename = "${path.root}/${var.reports_dir}/${each.key}/inventory_report.md"
}

resource "local_file" "aggregated_summary_json" {
  content  = jsonencode(local.aggregated_summary)
  filename = "${path.root}/${var.reports_dir}/_aggregated_summary.json"
}

resource "local_file" "combined_report_md" {
  content  = local.combined_markdown_report
  filename = "${path.root}/${var.reports_dir}/_combined_report.md"
}

# -----------------------------
# History archiving.
#
# We deliberately use null_resource + local-exec rather than local_file so that
# previous archive directories are NOT managed by Terraform state. If we tracked
# them via local_file with for_each keyed by timestamp, every new apply would
# destroy the prior run's archive (because the old key leaves the for_each set).
# The null_resource runs once per apply (plantimestamp trigger) and simply
# copies the freshly-written reports into a timestamped directory on disk.
# -----------------------------
resource "null_resource" "history_snapshot" {
  count = var.enable_history ? 1 : 0

  triggers = {
    run_at = plantimestamp()
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      SRC="${path.root}/${var.reports_dir}"
      DST="${local.history_root}"
      mkdir -p "$DST"
      # Copy every top-level entry except the _history dir itself, so archives
      # don't grow recursively.
      find "$SRC" -maxdepth 1 -mindepth 1 ! -name '_history' \
        -exec cp -r {} "$DST/" \;
    EOT
  }

  depends_on = [
    local_file.inventory_json,
    local_file.summary_json,
    local_file.inventory_report_md,
    local_file.aggregated_summary_json,
    local_file.combined_report_md,
  ]
}
