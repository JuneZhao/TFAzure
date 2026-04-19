variable "subscription_ids" {
  description = "List of Azure subscription IDs to inventory. Each subscription gets its own set of output files."
  type        = list(string)

  validation {
    condition     = length(var.subscription_ids) > 0
    error_message = "subscription_ids must contain at least one subscription ID."
  }

  validation {
    condition = alltrue([
      for s in var.subscription_ids :
      can(regex("^[0-9a-fA-F-]{36}$", s))
    ])
    error_message = "Every element of subscription_ids must be a 36-char Azure subscription GUID."
  }
}

variable "tenant_id" {
  description = "Azure AD tenant ID the subscriptions belong to."
  type        = string
}

variable "managed_identity_client_id" {
  description = "Client ID of the User-Assigned Managed Identity (only used when use_msi = true)."
  type        = string
  default     = ""
}

variable "use_msi" {
  description = "Use Managed Identity for authentication (true on Azure VM / CI, false for local az CLI / ARM_* env vars)."
  type        = bool
  default     = false
}

variable "top_n_cost_resources" {
  description = "Number of highest-cost resources to include per subscription."
  type        = number
  default     = 10
}

variable "cost_timeframe" {
  description = "Cost Management timeframe (Last7Days, MonthToDate, BillingMonthToDate, etc.)."
  type        = string
  default     = "Last7Days"
}

variable "cost_type" {
  description = "Cost Management cost type: AmortizedCost or ActualCost."
  type        = string
  default     = "AmortizedCost"
}

variable "cost_alert_threshold" {
  description = "Per-resource cost threshold within the cost_timeframe window. Resources exceeding this value get flagged in outputs and highlighted in the Markdown report. Set to 0 to disable."
  type        = number
  default     = 0

  validation {
    condition     = var.cost_alert_threshold >= 0
    error_message = "cost_alert_threshold must be >= 0."
  }
}

variable "reports_dir" {
  description = "Root directory (relative to the Terraform root) where per-subscription reports are written."
  type        = string
  default     = "reports"
}

variable "enable_history" {
  description = "When true, each apply also copies the current reports/<sub_id>/ snapshot into reports/_history/<timestamp>/<sub_id>/ for historical archiving. Requires a Linux host with cp available."
  type        = bool
  default     = false
}

variable "history_timestamp_format" {
  description = "Go time reference-style format string used for history subdirectory names. See https://developer.hashicorp.com/terraform/language/functions/formatdate."
  type        = string
  default     = "YYYY-MM-DD'T'hhmmss'Z'"
}
