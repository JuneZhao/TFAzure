variable "subscription_id" {
  description = "Azure subscription ID this module should inventory."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.subscription_id))
    error_message = "subscription_id must be a 36-char Azure subscription GUID."
  }
}

variable "top_n_cost_resources" {
  description = "Number of highest-cost resources to include in the report."
  type        = number
  default     = 10
}

variable "cost_timeframe" {
  description = "Cost Management timeframe (e.g. Last7Days, MonthToDate, BillingMonthToDate)."
  type        = string
  default     = "Last7Days"
}

variable "cost_type" {
  description = "Cost Management cost type: AmortizedCost or ActualCost."
  type        = string
  default     = "AmortizedCost"

  validation {
    condition     = contains(["AmortizedCost", "ActualCost"], var.cost_type)
    error_message = "cost_type must be either AmortizedCost or ActualCost."
  }
}

variable "cost_alert_threshold" {
  description = "Per-resource cost threshold within the cost_timeframe window. Resources whose aggregated cost exceeds this value are flagged in outputs and highlighted in the Markdown report. Set to 0 to disable."
  type        = number
  default     = 0

  validation {
    condition     = var.cost_alert_threshold >= 0
    error_message = "cost_alert_threshold must be >= 0."
  }
}
