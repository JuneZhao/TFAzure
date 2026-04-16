data "azurerm_subscription" "current" {}

#data "azurerm_resources" "all" {}

data "external" "resource_graph" {
  program = [
    "bash",
    "${path.module}/../../query_resources.sh",
    data.azurerm_subscription.current.subscription_id
  ]
}

data "external" "costs" {
  program = [
    "bash",
    "${path.module}/../../query_costs.sh",
    data.azurerm_subscription.current.subscription_id
  ]
}

#data "azapi_resource_list" "resource_groups" {
# type      = "Microsoft.Resources/resourceGroups@2021-04-01"
#  parent_id = data.azurerm_subscription.current.id

#response_export_values = ["value"]
#}
