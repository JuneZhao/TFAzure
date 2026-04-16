variable "subscription_id" {
  type = string
}

variable "tenant_id" {
  type = string
}

variable "managed_identity_client_id" {
  description = "Client ID of the User-Assigned Managed Identity"
  type        = string
  default     = ""
}

variable "use_msi" {
  description = "Use Managed Identity for authentication (true on Azure, false for local CLI auth)"
  type        = bool
  default     = false
}

variable "top_n_cost_resources" {
  description = "Number of highest-cost resources to include in output"
  type        = number
  default     = 10
}
