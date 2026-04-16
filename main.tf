module "subscription_inventory" {
  source = "./modules/subscription_inventory"

  tenant_id            = var.tenant_id
  top_n_cost_resources = var.top_n_cost_resources
}
