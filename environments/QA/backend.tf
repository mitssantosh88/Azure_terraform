terraform {
  backend "azurerm" {
    resource_group_name  = "rg-santosh"
    storage_account_name = "amf5gprod"
    container_name       = "tfstate"
    key                  = "prod.tfstate"
  }
}