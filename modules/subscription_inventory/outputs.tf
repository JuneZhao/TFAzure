output "inventory" {
  value = local.inventory
}

output "summary" {
  value = local.summary
}

output "markdown_report" {
  value = local.markdown_report
}

output "top_cost_resources" {
  value = local.top_cost_resources
}

output "over_threshold_resources" {
  description = "Resources whose cost exceeds var.cost_alert_threshold (empty when alerts are disabled)."
  value       = local.over_threshold_resources
}
