# resource "azurerm_resource_group" "RG1" {
#   name     = var.resource_group_name
#   location = var.location
# }
# resource "azurerm_resource_group" "RG2" {
#   name     = var.resource_group_name_2
#   location = var.location
# }
# resource "azurerm_resource_group" "RG3" {
#   name     = var.resource_group_name_3
#   location = var.location
# }
resource "azurerm_virtual_network" "VNET1"{
    name = "vnet-5g-prod"
    location = azurerm_resource_group.RG1.location
    resource_group_name = azurerm_resource_group.RG1.name
    address_space = ["10.0.0.0/16"]
}
resource "azurerm_storage_account" "ST1" {
  name                     = "${var.storage_account_name}"
  resource_group_name      = azurerm_resource_group.RG1.name
  location                 = azurerm_resource_group.RG1.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}
