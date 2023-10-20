terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      configuration_aliases = [
        azurerm.hub,
        azurerm.spoke
      ]
    }
    random = {
      source = "hashicorp/random"
    }
  }
}
