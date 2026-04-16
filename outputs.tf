output "inventory" {
  value = module.subscription_inventory.inventory
}

output "summary" {
  value = module.subscription_inventory.summary
}

output "markdown_report" {
  value = module.subscription_inventory.markdown_report
}

output "top_cost_resources" {
  value = module.subscription_inventory.top_cost_resources
}

resource "local_file" "inventory_json" {
  content  = jsonencode(module.subscription_inventory.inventory)
  filename = "${path.root}/inventory.json"
}

resource "local_file" "summary_json" {
  content  = jsonencode(module.subscription_inventory.summary)
  filename = "${path.root}/summary.json"
}

resource "local_file" "inventory_report_md" {
  content  = module.subscription_inventory.markdown_report
  filename = "${path.root}/inventory_report.md"
}
