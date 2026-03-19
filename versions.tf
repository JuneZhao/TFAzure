terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }

    azapi = {
      source  = "azure/azapi"
      version = "~> 1.12"
    }

    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
}
