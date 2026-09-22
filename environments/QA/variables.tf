variable "resource_group_name" {
  description = "QA Resource Group name"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "vnet_name" {
  description = "QA VNet name"
  type        = string
}

variable "address_space" {
  description = "QA VNet address space"
  type        = list(string)
}

variable "subnet_name" {
  description = "QA subnet name"
  type        = string
}

variable "subnet_address_prefixes" {
  description = "QA subnet CIDR"
  type        = list(string)
}