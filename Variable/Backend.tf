# terraform {
#   backend "azurerm" {
#     resource_group_name = "rg-5g-prod"
#     storage_account_name = "st5gprod"
#     container_name       = "tfstate"
#     key                  = "devops/terraform.tfstate"
#   }
# }