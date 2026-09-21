module "resource_group" {
  source = "../../Module/resource-group"

  resource_group_name = var.resource_group_name
  location            = var.location
}
module "network" {

  source = "../../Module/network"

  resource_group_name = var.resource_group_name
  location            = var.location

  vnet_name = var.vnet_name

  address_space = var.address_space

  subnet_name = var.subnet_name

  subnet_address_prefixes = var.subnet_address_prefixes

}