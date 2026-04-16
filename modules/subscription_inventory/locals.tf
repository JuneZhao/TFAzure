locals {
  graph_raw  = data.external.resource_graph.result.result
  graph_data = jsondecode(local.graph_raw)

  resources = local.graph_data.data

  # -----------------------------
  # Cost Data
  # -----------------------------
  cost_raw  = data.external.costs.result.result
  cost_data = jsondecode(local.cost_raw)

  cost_columns = try(local.cost_data.properties.columns, [])
  cost_rows    = try(local.cost_data.properties.rows, [])

  cost_column_index = {
    for idx, col in local.cost_columns :
    col.name => idx
  }

  cost_idx_resource_id = lookup(local.cost_column_index, "ResourceId", -1)
  cost_idx_currency    = lookup(local.cost_column_index, "Currency", -1)
  cost_idx_pretax      = lookup(local.cost_column_index, "PreTaxCost", -1)
  cost_idx_cost        = lookup(local.cost_column_index, "Cost", -1)

  cost_entries = [
    for row in local.cost_rows : {
      resource_id = lower(trimspace(tostring(row[local.cost_idx_resource_id])))
      currency    = local.cost_idx_currency >= 0 ? tostring(row[local.cost_idx_currency]) : "USD"
      cost = local.cost_idx_pretax >= 0 ? try(tonumber(row[local.cost_idx_pretax]), 0) : (
        local.cost_idx_cost >= 0 ? try(tonumber(row[local.cost_idx_cost]), 0) : 0
      )
    }
    if local.cost_idx_resource_id >= 0
    && try(length(trimspace(tostring(row[local.cost_idx_resource_id]))), 0) > 0
  ]

  distinct_cost_resource_ids = distinct([for c in local.cost_entries : c.resource_id])

  costs_by_resource_id = {
    for rid in local.distinct_cost_resource_ids :
    rid => {
      cost = sum([
        for c in local.cost_entries :
        c.cost if c.resource_id == rid
      ])
      currency = try(element(distinct([
        for c in local.cost_entries :
        c.currency if c.resource_id == rid && c.currency != null && trimspace(c.currency) != ""
      ]), 0), "USD")
    }
  }

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
          id       = r.id
          name     = r.name
          type     = r.type
          location = r.location
          tags     = r.tags
        }
        if r.resourceGroup == rg
      ]
    }
  }

  resources_by_id = {
    for r in local.resources :
    lower(r.id) => r
    if try(r.id, null) != null
  }

  cost_ranked_resources = [
    for rid, cost_info in local.costs_by_resource_id :
    {
      resource_id    = rid
      name           = try(local.resources_by_id[rid].name, rid)
      type           = try(local.resources_by_id[rid].type, "unknown")
      resource_group = try(local.resources_by_id[rid].resourceGroup, "unknown")
      location       = try(local.resources_by_id[rid].location, "unknown")
      cost           = floor(cost_info.cost * 100 + 0.5) / 100
      currency       = cost_info.currency
    }
    if cost_info.cost > 0
  ]

  cost_ranked_resources_map = {
    for r in local.cost_ranked_resources :
    r.resource_id => r
  }

  cost_sortable = [
    for r in local.cost_ranked_resources :
    format("%020.6f|%s", r.cost, r.resource_id)
  ]

  cost_sorted_desc = reverse(sort(local.cost_sortable))

  top_cost_resources = slice([
    for s in local.cost_sorted_desc :
    local.cost_ranked_resources_map[split("|", s)[1]]
  ], 0, min(var.top_n_cost_resources, length(local.cost_sorted_desc)))

  top_cost_resources_markdown_lines = length(local.top_cost_resources) > 0 ? [
    for r in local.top_cost_resources :
    format("- %s (%s, %s): %s %.2f", r.name, r.type, r.resource_group, r.currency, r.cost)
  ] : ["- No cost data available."]

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

  top_10_resource_type_sortable = [
    for k, v in local.resource_type_stats :
    format("%05d|%s", v, k)
  ]

  top_10_resource_type_sorted_desc = reverse(sort(local.top_10_resource_type_sortable))

  top_10_resource_types = slice([
    for s in local.top_10_resource_type_sorted_desc : {
      type  = split("|", s)[1]
      count = tonumber(split("|", s)[0])
    }
  ], 0, min(10, length(local.top_10_resource_type_sorted_desc)))

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
    total_resources            = length(local.resources)
    total_resource_groups      = length(local.resource_groups)
    resource_type_distribution = local.resource_type_stats
    location_distribution      = local.location_stats
    top_10_resource_types      = local.top_10_resource_types
    top_cost_resources         = local.top_cost_resources
    untagged_resource_count    = length(local.untagged_resources)
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

## Top Cost Resources (Last 7 Days, AmortizedCost)
${join("\n", local.top_cost_resources_markdown_lines)}

## Location Distribution
${join("\n", [for k, v in local.location_stats : "- ${k}: ${v}"])}

EOT
}
