azurerm_resource_groups = {
    rg1 = {
        name     = "rg1"
        location = "East US"
    }
    rg2 = {
        name     = "rg2"
        location = "East US"
    }
    rg3 = {
        name     = "rg3"
        location = "East US"
    }
}
storage_accounts = {
  st1 = {
    name               = "mystorageaccount001dev"
    resource_group_key = "rg1"
    location           = "East US"
    account_tier       = "Standard"
    replication_type   = "LRS"
  }

  st2 = {
    name               = "mystorageaccount001prod"
    resource_group_key = "rg2"
    location           = "East US"
    account_tier       = "Standard"
    replication_type   = "LRS"
  }
}