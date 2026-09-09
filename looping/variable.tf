variable "azurerm_resource_groups" {
  type = map(object({
    name     = string
    location = string
  }))
}
# variable "resource_groups_locations" {
#   type = string
# }

# variable "storage_accounts" {
#   type = set(string)

# }
