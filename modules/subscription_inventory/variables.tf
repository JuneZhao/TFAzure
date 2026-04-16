variable "tenant_id" {
  type = string
}

variable "top_n_cost_resources" {
  description = "Number of highest-cost resources to include in output"
  type        = number
  default     = 10
}
