variable "resource_group_name" {
  description = "Production Resource Group name"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "vnet_name" {
  description = "Production VNet name"
  type        = string
}

variable "address_space" {
  description = "Production VNet address space"
  type        = list(string)
}

variable "subnet_name" {
  description = "Production subnet name"
  type        = string
}

variable "subnet_address_prefixes" {
  description = "Production subnet CIDR"
  type        = list(string)
}