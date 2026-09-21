module "network" {

  source = "../../modules/network"

  resource_group_name = var.resource_group_name
  location            = var.location

  vnet_name = var.vnet_name

  address_space = var.address_space

  subnet_name = var.subnet_name

  subnet_address_prefixes = var.subnet_address_prefixes

}