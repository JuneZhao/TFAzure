locals {

  graph_raw  = data.external.resource_graph.result.result
  graph_data = jsondecode(local.graph_raw)

  resources = local.graph_data.data

  # -----------------------------
  # RG Hierarchical Structure
  # -----------------------------
  resource_groups = distinct([
    for r in local.resources :
    r.resourceGroup
    if r.resourceGroup != null
  ])

  resources_by_rg = {
    for rg in local.resource_groups :
    rg => {
      resources = [
        for r in local.resources :
        {
          name     = r.name
          type     = r.type
          location = r.location
          tags     = r.tags
        }
        if r.resourceGroup == rg
      ]
    }
  }

  # -----------------------------
  # Resource Type Statistics
  # -----------------------------
  resource_type_stats = {
    for t in distinct([for r in local.resources : r.type]) :
    t => length([
      for r in local.resources :
      r if r.type == t
    ])
  }

  # ✅ Top 10 Resource Types (sorted by count DESC)
  resource_type_sortable = [
    for k, v in local.resource_type_stats :
    format("%05d|%s", v, k)
  ]

  resource_type_sorted_strings = sort(local.resource_type_sortable)

  resource_type_sorted_desc = reverse(local.resource_type_sorted_strings)

  top_10_resource_types = slice([
    for s in local.resource_type_sorted_desc : {
      type  = split("|", s)[1]
      count = tonumber(split("|", s)[0])
    }
  ], 0, min(10, length(local.resource_type_sorted_desc)))

  # -----------------------------
  # Location Distribution
  # -----------------------------
  location_stats = {
    for l in distinct([for r in local.resources : r.location]) :
    l => length([
      for r in local.resources :
      r if r.location == l
    ])
  }

  # -----------------------------
  # Untagged Resources
  # -----------------------------
  untagged_resources = [
    for r in local.resources :
    {
      name          = r.name
      type          = r.type
      resourceGroup = r.resourceGroup
      location      = r.location
    }
    if r.tags == null || length(r.tags) == 0
  ]

  # -----------------------------
  # Full Inventory Structure
  # -----------------------------
  inventory = {
    subscription = {
      id   = data.azurerm_subscription.current.subscription_id
      name = data.azurerm_subscription.current.display_name
    }

    resource_groups = local.resources_by_rg
  }

  # -----------------------------
  # Summary Structure
  # -----------------------------
  summary = {
    total_resources              = length(local.resources)
    total_resource_groups        = length(local.resource_groups)
    resource_type_distribution   = local.resource_type_stats
    location_distribution        = local.location_stats
    top_10_resource_types        = local.top_10_resource_types
    untagged_resource_count      = length(local.untagged_resources)
  }

  # -----------------------------
  # Markdown Report
  # -----------------------------
  markdown_report = <<EOT
# Azure Inventory Report

## Subscription
- ID: ${data.azurerm_subscription.current.subscription_id}
- Name: ${data.azurerm_subscription.current.display_name}

## Summary
- Total Resources: ${length(local.resources)}
- Total Resource Groups: ${length(local.resource_groups)}
- Untagged Resources: ${length(local.untagged_resources)}

## Top Resource Types
${join("\n", [for r in local.top_10_resource_types : "- ${r.type}: ${r.count}"])}

## Location Distribution
${join("\n", [for k, v in local.location_stats : "- ${k}: ${v}"])}

EOT
}
