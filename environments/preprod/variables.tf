variable "resource_group_name" {
  description = "Pre-Prod Resource Group name"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "vnet_name" {
  description = "Pre-Prod VNet name"
  type        = string
}

variable "address_space" {
  description = "Pre-Prod VNet address space"
  type        = list(string)
}

variable "subnet_name" {
  description = "Pre-Prod subnet name"
  type        = string
}

variable "subnet_address_prefixes" {
  description = "Pre-Prod subnet CIDR"
  type        = list(string)
}