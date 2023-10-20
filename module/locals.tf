locals {
  rg_vnet_key                    = "rg_vnet"
  vnet_key                       = "vnet"
  vhc_key                        = "vhc"
  rg_nsg_key                     = "rg_nsg"
  snet_keys                      = var.spoke.subnets[*].name
  nsg_keys                       = compact(var.spoke.subnets[*].nsg_name)
  rid_keys                       = concat([local.rg_vnet_key, local.vnet_key, local.vhc_key, local.rg_nsg_key], local.snet_keys, local.nsg_keys)
  vnet_function                  = var.spoke.function == null ? "legacy" : var.spoke.function
  vhc_propagated_route_table_ids = var.propagate_not_secure_vitual_hub_connection ? [var.virtual_hub_default_route_table_id, replace(var.virtual_hub_default_route_table_id, "defaultRouteTable", "not-secure-Default")] : distinct([var.virtual_hub_default_route_table_id, replace(var.virtual_hub_default_route_table_id, "defaultRouteTable", var.spoke.virtual_hub_associated_route_table_name)])

  ddos = var.spoke.name == "vnet-pub-prod-cu" ? [1] : []
}
