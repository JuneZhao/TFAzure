provider "azurerm" {
  features {}

  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id

  use_msi = false
  #  client_id = var.managed_identity_client_id
}

provider "azapi" {
  #features {}
  use_msi = false
  #subscription_id = var.subscription_id
  #tenant_id       = var.tenant_id

}
