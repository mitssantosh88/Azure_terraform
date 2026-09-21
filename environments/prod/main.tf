terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Resource Group Child Module
module "resource_group" {
  source = "./Module/resource_group"

  resource_group_name = var.resource_group_name
  location            = var.location
}

# Network Child Module
module "network" {
  source = "./Module/network"

  resource_group_name = module.resource_group.resource_group_name
  location            = var.location

  vnet_name = var.vnet_name

  address_space = var.address_space

  subnet_name = var.subnet_name

  subnet_address_prefixes = var.subnet_address_prefixes
}