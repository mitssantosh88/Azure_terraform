terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=5.0.0"
    }
  }
}
# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {}
}
# Resource Group Child Module
module "resource_group" {
  source = "../../Module/resource-group"
  resource_group_name = var.resource_group_name
  location            = var.location
}
module "network" {

  source = "../../modules/network"

  resource_group_name = var.resource_group_name
  location            = var.location

  vnet_name = var.vnet_name

  address_space = var.address_space

  subnet_name = var.subnet_name

  subnet_address_prefixes = var.subnet_address_prefixes

}