locals {
  use_msi = var.use_msi
}

provider "azurerm" {
  features {}

  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id

  use_msi   = local.use_msi
  client_id = local.use_msi ? var.managed_identity_client_id : null
}

provider "azapi" {
  use_msi         = local.use_msi
  client_id       = local.use_msi ? var.managed_identity_client_id : null
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}
