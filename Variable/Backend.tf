terraform {
  backend "azurerm" {
    resource_group_name = "rg-prod"
    storage_account_name = "paartst"
    container_name       = "tfstate"
    key                  = "devops/terraform.tfstate"
  }
}