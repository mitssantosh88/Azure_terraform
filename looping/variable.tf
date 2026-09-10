variable "azurerm_resource_groups" {
  type = map(object({
    name     = string
    location = string
  }))
}
variable "storage_accounts" {
  type = map(object({
    name               = string
    resource_group_key = string
    location           = string
    account_tier       = string
    replication_type   = string
  }))
}
