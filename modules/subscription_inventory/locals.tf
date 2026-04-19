locals {
  # -----------------------------
  # Raw API payloads (azapi v2 - output is a typed HCL object already)
  # -----------------------------
  resources = try(data.azapi_resource_action.resource_graph.output.data, [])

  cost_columns = try(data.azapi_resource_action.costs.output.properties.columns, [])
  cost_rows    = try(data.azapi_resource_action.costs.output.properties.rows, [])

  # -----------------------------
  # Cost data normalization
  # -----------------------------
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
  # Resource group hierarchy
  # -----------------------------
  resource_groups = distinct([
    for r in local.resources :
    r.resourceGroup
    if try(r.resourceGroup, null) != null
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
          kind     = try(r.kind, null)
          sku      = try(r.sku, null)
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

  # -----------------------------
  # Cost ranking + threshold flag
  # NOTE: format("%020.6f|...", cost) is a lexicographic sort trick because
  # Terraform's sort() only accepts strings. Keep positive cost assumption.
  # -----------------------------
  alert_enabled = var.cost_alert_threshold > 0

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
      over_threshold = local.alert_enabled && (floor(cost_info.cost * 100 + 0.5) / 100) > var.cost_alert_threshold
    }
    if cost_info.cost > 0
  ]

  cost_ranked_resources_map = {
    for r in local.cost_ranked_resources :
    r.resource_id => r
  }

  cost_sortable    = [for r in local.cost_ranked_resources : format("%020.6f|%s", r.cost, r.resource_id)]
  cost_sorted_desc = reverse(sort(local.cost_sortable))

  top_cost_resources = slice([
    for s in local.cost_sorted_desc :
    local.cost_ranked_resources_map[split("|", s)[1]]
    ], 0, min(var.top_n_cost_resources, length(local.cost_sorted_desc))
  )

  over_threshold_resources = [
    for r in local.cost_ranked_resources :
    r if r.over_threshold
  ]

  top_cost_resources_markdown_lines = length(local.top_cost_resources) > 0 ? [
    for r in local.top_cost_resources :
    format(
      "- %s%s (%s, %s): %s %.2f",
      r.over_threshold ? "**[ALERT]** " : "",
      r.name, r.type, r.resource_group, r.currency, r.cost
    )
  ] : ["- No cost data available."]

  # -----------------------------
  # Resource type statistics
  # -----------------------------
  resource_type_stats = {
    for t in distinct([for r in local.resources : r.type]) :
    t => length([for r in local.resources : r if r.type == t])
  }

  top_10_resource_type_sortable    = [for k, v in local.resource_type_stats : format("%05d|%s", v, k)]
  top_10_resource_type_sorted_desc = reverse(sort(local.top_10_resource_type_sortable))

  top_10_resource_types = slice([
    for s in local.top_10_resource_type_sorted_desc : {
      type  = split("|", s)[1]
      count = tonumber(split("|", s)[0])
    }
    ], 0, min(10, length(local.top_10_resource_type_sorted_desc))
  )

  # -----------------------------
  # Location distribution
  # -----------------------------
  location_stats = {
    for l in distinct([for r in local.resources : r.location]) :
    l => length([for r in local.resources : r if r.location == l])
  }

  # -----------------------------
  # Untagged resources
  # -----------------------------
  untagged_resources = [
    for r in local.resources :
    {
      id             = r.id
      name           = r.name
      type           = r.type
      resource_group = r.resourceGroup
      location       = r.location
    }
    if try(r.tags, null) == null || length(r.tags) == 0
  ]

  # -----------------------------
  # Full inventory + summary
  # -----------------------------
  inventory = {
    subscription = {
      id   = var.subscription_id
      name = data.azurerm_subscription.target.display_name
    }
    resource_groups = local.resources_by_rg
  }

  summary = {
    subscription_id            = var.subscription_id
    subscription_name          = data.azurerm_subscription.target.display_name
    total_resources            = length(local.resources)
    total_resource_groups      = length(local.resource_groups)
    resource_type_distribution = local.resource_type_stats
    location_distribution      = local.location_stats
    top_10_resource_types      = local.top_10_resource_types
    top_cost_resources         = local.top_cost_resources
    over_threshold_resources   = local.over_threshold_resources
    over_threshold_count       = length(local.over_threshold_resources)
    cost_alert_threshold       = var.cost_alert_threshold
    untagged_resource_count    = length(local.untagged_resources)
    untagged_resources         = local.untagged_resources
    cost_timeframe             = var.cost_timeframe
    cost_type                  = var.cost_type
  }

  # -----------------------------
  # Markdown report
  # Built as a list of pre-rendered sections; compact() drops the alert
  # section when disabled, join("\n\n") guarantees exactly one blank line
  # between sections (no trailing empties regardless of toggles).
  # -----------------------------
  section_subscription = join("\n", [
    "## Subscription",
    "- ID: ${var.subscription_id}",
    "- Name: ${data.azurerm_subscription.target.display_name}",
  ])

  section_summary = join("\n", concat(
    [
      "## Summary",
      "- Total Resources: ${length(local.resources)}",
      "- Total Resource Groups: ${length(local.resource_groups)}",
      "- Untagged Resources: ${length(local.untagged_resources)}",
    ],
    local.alert_enabled ? [
      "- Cost Alert Threshold: ${var.cost_alert_threshold}",
      "- Resources Over Threshold: ${length(local.over_threshold_resources)}",
    ] : []
  ))

  section_top_types = join("\n", concat(
    ["## Top Resource Types"],
    [for r in local.top_10_resource_types : "- ${r.type}: ${r.count}"]
  ))

  section_top_cost = join("\n", concat(
    ["## Top Cost Resources (${var.cost_timeframe}, ${var.cost_type})"],
    local.top_cost_resources_markdown_lines
  ))

  section_alert = local.alert_enabled ? join("\n", concat(
    ["## Cost Alerts (> ${var.cost_alert_threshold})"],
    length(local.over_threshold_resources) > 0 ? [
      for r in local.over_threshold_resources :
      format("- %s (%s, %s): %s %.2f", r.name, r.type, r.resource_group, r.currency, r.cost)
    ] : ["- No resources exceed the threshold."]
  )) : ""

  section_location = join("\n", concat(
    ["## Location Distribution"],
    [for k, v in local.location_stats : "- ${k}: ${v}"]
  ))

  markdown_report = join("\n\n", concat(
    ["# Azure Inventory Report"],
    compact([
      local.section_subscription,
      local.section_summary,
      local.section_top_types,
      local.section_top_cost,
      local.section_alert,
      local.section_location,
    ])
  ))
}
