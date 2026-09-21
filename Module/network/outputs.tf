# output "resource_group_name" {

#   value = azurerm_resource_group.rg-santosh.name

# }

output "vnet_name" {

  value = azurerm_virtual_network.vnet-santosh.name

}

output "subnet_id" {

  value = azurerm_subnet.subnet-santosh.id

}