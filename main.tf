module "subscription_inventory" {
  source   = "./modules/subscription_inventory"
  for_each = toset(var.subscription_ids)

  subscription_id      = each.value
  top_n_cost_resources = var.top_n_cost_resources
  cost_timeframe       = var.cost_timeframe
  cost_type            = var.cost_type
  cost_alert_threshold = var.cost_alert_threshold
}
