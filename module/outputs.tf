output "vnet_spoke" {
  value = {
    rids             = random_string.rids
    vnet             = azurerm_virtual_network.vnet
    subnets          = azurerm_subnet.subnets
    vhub_connection  = azurerm_virtual_hub_connection.vhc
    nsgs             = azurerm_network_security_group.nsgs
    nsg_associations = azurerm_subnet_network_security_group_association.nsg_associations
  }
}

output "nsg_nsr_map" {
  value = {
    "${var.sb_function}" = {
      "vnet-${local.vnet_function}" = { for subnet in var.spoke.subnets :
        "${subnet.workload_tier}" => {
          "enable_nsr"  = "${var.spoke.function != null}"
          "nsg_name"    = "${try(subnet.nsg_name, "") != null ? azurerm_network_security_group.nsgs[subnet.nsg_name].name : null}"
          "nsg_rg_name" = "${var.nsg_rg_name}"
        }... if subnet.workload_tier != null
      }
    }
  }
}
