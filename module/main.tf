resource "random_string" "rids" {
  for_each    = toset(local.rid_keys)
  length      = 4
  special     = false
  upper       = false
  numeric     = true
  min_numeric = 2
  min_lower   = 2
}

resource "azurerm_resource_group" "rg" {
  provider = azurerm.spoke
  name     = coalesce(try(var.spoke.resource_group.legacy_name, ""), "${var.spoke.resource_group.name}-${random_string.rids[local.rg_vnet_key].result}")
  location = var.location
  tags     = var.spoke.resource_group.tags
}

resource "azurerm_virtual_network" "vnet" {
  provider            = azurerm.spoke
  name                = coalesce(try(var.spoke.legacy_name, ""), "${var.spoke.name}-${random_string.rids[local.vnet_key].result}")
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = var.spoke.address_space
  dns_servers         = concat(var.spoke.dns_servers, formatlist(var.virtual_hub_firewall_private_ip_address))
  tags                = var.spoke.tags

  dynamic "ddos_protection_plan" {
    for_each = local.ddos
    content {
      enable = true
      id     = "/subscriptions/b69669b9-6d12-4ada-b44d-5f578b85f46c/resourceGroups/rg-pub-prod-cu-vnet-3c7g/providers/Microsoft.Network/ddosProtectionPlans/ddos-pfm-prod-cu-pub-8j03"
    }
  }

}

resource "azurerm_virtual_hub_connection" "vhc" {
  count                     = var.spoke.virtual_hub_connection_enabled ? 1 : 0
  provider                  = azurerm.hub
  name                      = coalesce(try(var.spoke.legacy_virtual_hub_connection_name, ""), "${var.spoke.virtual_hub_connection_name}-${random_string.rids[local.vhc_key].result}")
  remote_virtual_network_id = trimsuffix(azurerm_virtual_network.vnet.id, "/")
  virtual_hub_id            = var.virtual_hub_id
  internet_security_enabled = var.spoke.internet_security_enabled

  routing {
    associated_route_table_id = replace(var.virtual_hub_default_route_table_id, "defaultRouteTable", var.spoke.virtual_hub_associated_route_table_name)
    propagated_route_table {
      route_table_ids = local.vhc_propagated_route_table_ids
    }
  }

  depends_on = [
    azurerm_virtual_network.vnet
  ]
}

resource "azurerm_subnet" "subnets" {
  provider             = azurerm.spoke
  for_each             = { for subnet in var.spoke.subnets : subnet.name => subnet }
  name                 = coalesce(try(each.value.legacy_name, ""), "${each.key}-${random_string.rids[each.key].result}")
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = each.value.address_prefixes
  service_endpoints    = each.value.service_endpoints

  dynamic "delegation" {
    for_each = { for delegation in each.value.delegations : delegation.name => delegation if try(each.value.delegations, null) != null }
    content {
      name = delegation.value.name

      service_delegation {
        name    = delegation.value.name
        actions = delegation.value.actions
      }
    }
  }

  depends_on = [
    azurerm_virtual_network.vnet
  ]
}

resource "azurerm_subnet_route_table_association" "route_tables_ass" {
  provider = azurerm.spoke

  for_each       = { for subnet in var.spoke.subnets : subnet.name => subnet if try(subnet.route_table_association, null) != null }
  subnet_id      = azurerm_subnet.subnets[each.key].id
  route_table_id = var.routes[each.value.route_table_association].id
}

# DO NOT USE NETWORK SECURITY RULES IN-LINE WITHIN THE FOLLOWING RESOURCE
resource "azurerm_network_security_group" "nsgs" {
  provider            = azurerm.spoke
  for_each            = { for subnet in var.spoke.subnets : subnet.nsg_name => subnet if try(subnet.nsg_name, null) != null }
  name                = "${each.key}-${random_string.rids[each.key].result}"
  location            = var.nsg_rg_location
  resource_group_name = var.nsg_rg_name

  # terraform azurerm_network_security_group ignore changes for security rules because they are managed elsewhere
  lifecycle {
    ignore_changes = [
      security_rule
    ]
  }
}

# Currently there is a bug with subnets in vnet-platform-prod-usc-01, their is is suffixed with "1" on every plan/apply
resource "azurerm_subnet_network_security_group_association" "nsg_associations" {
  provider                  = azurerm.spoke
  for_each                  = { for subnet in var.spoke.subnets : subnet.name => subnet if try(subnet.nsg_name, null) != null }
  subnet_id                 = "${azurerm_virtual_network.vnet.id}/subnets/${azurerm_subnet.subnets[each.key].name}" # Building the id because of a bug in subnet id sometimes it plan with a wrong id and ends up recreating the same association
  network_security_group_id = azurerm_network_security_group.nsgs[each.value.nsg_name].id
}


resource "azurerm_private_dns_zone_virtual_network_link" "pvt_dns_zones_links" {
  provider              = azurerm.hub
  for_each              = { for link in var.spoke.private_dns_zone_links : link => link }
  name                  = lower("vnl-${azurerm_virtual_network.vnet.name}")
  resource_group_name   = var.private_dns_zones.routes.rg_name
  private_dns_zone_name = each.key
  virtual_network_id    = azurerm_virtual_network.vnet.id
}
