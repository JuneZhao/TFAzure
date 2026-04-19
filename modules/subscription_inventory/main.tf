data "azurerm_subscription" "target" {
  subscription_id = var.subscription_id
}

# Resource Graph query (provider-level action, native via azapi v2).
# API: POST https://management.azure.com/providers/Microsoft.ResourceGraph/resources?api-version=2021-03-01
data "azapi_resource_action" "resource_graph" {
  type                   = "Microsoft.ResourceGraph@2021-03-01"
  resource_id            = "/providers/Microsoft.ResourceGraph"
  action                 = "resources"
  method                 = "POST"
  response_export_values = ["data", "count", "totalRecords"]

  body = {
    subscriptions = [var.subscription_id]
    query = join(" | ", [
      "Resources",
      "project id, name, type, kind, resourceGroup, location, subscriptionId, tags, sku",
    ])
    options = {
      resultFormat = "objectArray"
      # Hard cap to stay well below ARG per-call row limits. Pagination
      # would require $skipToken handling; revisit if a subscription ever
      # exceeds this.
      top = 1000
    }
  }
}

# Cost Management query at subscription scope.
# API: POST /subscriptions/{id}/providers/Microsoft.CostManagement/query?api-version=2023-03-01
data "azapi_resource_action" "costs" {
  type                   = "Microsoft.CostManagement@2023-03-01"
  resource_id            = "/subscriptions/${var.subscription_id}/providers/Microsoft.CostManagement"
  action                 = "query"
  method                 = "POST"
  response_export_values = ["properties.columns", "properties.rows"]

  body = {
    type      = var.cost_type
    timeframe = var.cost_timeframe
    dataset = {
      granularity = "None"
      aggregation = {
        totalCost = {
          name     = "PreTaxCost"
          function = "Sum"
        }
      }
      grouping = [
        {
          type = "Dimension"
          name = "ResourceId"
        },
      ]
    }
  }
}
