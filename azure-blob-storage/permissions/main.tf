# =============================================================================
# Per-link blob container and scoped SAS token
# =============================================================================
#
# One container per link, plus a Shared Access Signature scoped to that
# container with permissions derived from the link's access_level.
#
# The account's connection string is read from Azure here rather than being
# passed in as a variable, so no credential is stored in nullplatform
# attributes or in the deployment module's outputs.

data "azurerm_storage_account" "target" {
  name                = var.storage_account_name
  resource_group_name = var.resource_group_name
}

resource "azurerm_storage_container" "link" {
  name               = var.container_name
  storage_account_id = data.azurerm_storage_account.target.id

  metadata = {
    managed_by = "nullplatform"
    link_id    = var.link_id
  }
}

# Anchor the SAS start time in state.
#
# Using timestamp() here would recompute the signature on every apply, so
# every service update would reissue the token and rewrite the link's
# attributes — churning the app's environment for no reason. time_static is
# recorded in state, so the token is stable until sas_ttl_days changes.
resource "time_static" "sas_start" {
  triggers = {
    container = azurerm_storage_container.link.name
    ttl_days  = tostring(var.sas_ttl_days)
  }
}

data "azurerm_storage_account_blob_container_sas" "link" {
  connection_string = data.azurerm_storage_account.target.primary_connection_string
  container_name    = azurerm_storage_container.link.name
  https_only        = true

  start  = time_static.sas_start.rfc3339
  expiry = timeadd(time_static.sas_start.rfc3339, "${local.sas_expiry_hours}h")

  permissions {
    read   = local.perms.read
    add    = local.perms.add
    create = local.perms.create
    write  = local.perms.write
    delete = local.perms.delete
    list   = local.perms.list
  }
}
