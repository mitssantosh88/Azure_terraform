# resource "azurerm_resource_group" "RGS" {
#   for_each = toset(["RG1", "RG2", "RG3"])
#   name     = each.value
#   location = "West Europe"
# }
resource "azurerm_resource_group" "RGS" {
  for_each = var.azurerm_resource_groups
  
  name     = each.value.name
  location = each.value.location
}
resource "azurerm_storage_account" "STG" {
  for_each = var.storage_accounts
  
  name                     = each.value.name
  resource_group_name      = azurerm_resource_group.RGS[each.value.resource_group_key].name
  location                 = each.value.location
  account_tier             = each.value.account_tier
  account_replication_type = each.value.replication_type
}