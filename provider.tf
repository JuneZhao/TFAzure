locals {
  use_msi          = var.use_msi
  primary_sub_id   = var.subscription_ids[0]
  managed_identity = local.use_msi ? var.managed_identity_client_id : null
}

# azurerm is bound to a single subscription (the "primary"). Per-target subscription
# calls happen inside the module via azapi, so the primary choice only affects
# where data.azurerm_subscription lookups originate. resource_provider_registrations
# is set to "none" because this configuration is read-only and must not mutate
# the target tenant.
provider "azurerm" {
  features {}

  subscription_id                 = local.primary_sub_id
  tenant_id                       = var.tenant_id
  resource_provider_registrations = "none"

  use_msi   = local.use_msi
  client_id = local.managed_identity
}

provider "azapi" {
  subscription_id = local.primary_sub_id
  tenant_id       = var.tenant_id

  use_msi   = local.use_msi
  client_id = local.managed_identity
}
