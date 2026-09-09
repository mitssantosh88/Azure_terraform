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