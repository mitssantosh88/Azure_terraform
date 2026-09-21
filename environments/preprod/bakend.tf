terraform {
  backend "azurerm" {
    resource_group_name  = "rg-santosh"
    storage_account_name = "amf5gpreprod"
    container_name       = "tfstate"
    key                  = "preprod.tfstate"
  }
}