resource "azurerm_resource_group" "RG1" {
  name     = "santosh-rg"
  location = "East US"
}
# resource "azurerm_storage_account" "storageAccount" {
#   name                     = "santoshtfstorage"
#   resource_group_name      = azurerm_resource_group.RG1.name
#   location                 = azurerm_resource_group.RG1.location
#   account_tier             = "Standard"
#   account_replication_type = "LRS"
# }