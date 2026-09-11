# =============================================================================
# Azure Storage Account (Blob Storage)
# =============================================================================
#
# Provisions one StorageV2 (general purpose v2) Storage Account per
# nullplatform service instance. Blob containers are NOT created here — each
# link creates its own container through the permissions/ module.

# Resolves var.location when it is empty. Reading the resource group also
# fails early, and with a clear Azure error, when the group does not exist —
# better than the storage account create failing on a stale location.
data "azurerm_resource_group" "target" {
  name = var.resource_group_name
}

locals {
  location = var.location != "" ? var.location : data.azurerm_resource_group.target.location
}

resource "azurerm_storage_account" "storage" {
  name                = var.storage_account_name
  resource_group_name = var.resource_group_name
  location            = local.location

  account_kind             = "StorageV2"
  account_tier             = var.account_tier
  account_replication_type = var.replication_type
  access_tier              = var.access_tier

  # Security. Fixed, deliberately not exposed in the service schema: there is
  # no legitimate reason to let a user weaken these from the UI.
  min_tls_version            = "TLS1_2"
  https_traffic_only_enabled = true

  # Network
  public_network_access_enabled   = true
  allow_nested_items_to_be_public = false

  network_rules {
    default_action = "Allow"
    bypass         = ["AzureServices"]
  }

  # Data protection. container_delete_retention_policy is the recovery window
  # after an unlink, which deletes the link's container.
  blob_properties {
    versioning_enabled = var.blob_versioning

    dynamic "delete_retention_policy" {
      for_each = var.soft_delete_days > 0 ? [1] : []
      content {
        days = var.soft_delete_days
      }
    }

    dynamic "container_delete_retention_policy" {
      for_each = var.container_soft_delete_days > 0 ? [1] : []
      content {
        days = var.container_soft_delete_days
      }
    }
  }

  tags = merge(var.tags, {
    "Name"       = var.storage_account_name
    "managed-by" = "nullplatform"
    "service-id" = var.service_id
  })
}
