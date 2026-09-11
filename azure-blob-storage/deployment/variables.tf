variable "service_id" {
  type        = string
  description = "Nullplatform service instance ID, tagged onto every resource"

  validation {
    condition     = length(var.service_id) > 0
    error_message = "service_id must not be empty. build_context rejects an empty or null .service.id, and this mirrors that rule so a hand-run tofu plan catches it too."
  }
}

variable "storage_account_name" {
  type        = string
  description = "Storage Account name, precomputed by scripts/azure/storage_account_name"

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "storage_account_name must be 3-24 lowercase alphanumeric characters (Azure allows no hyphens)."
  }
}

variable "resource_group_name" {
  type        = string
  description = "Azure resource group that will hold the Storage Account"

  validation {
    condition     = length(var.resource_group_name) > 0
    error_message = "resource_group_name must not be empty. Set it in values.yaml or expose it through the cloud-providers provider."
  }
}

variable "location" {
  type        = string
  default     = ""
  description = <<-EOT
    Azure region for the Storage Account. Empty (the default) means "use the
    target resource group's own location", read through a data source.

    Optional on purpose: nullplatform has no account.location equivalent for
    Azure the way it has account.region for AWS, and the agent module injects
    RESOURCE_GROUP but no region. Deriving it from the resource group is what
    lets the common single-region install configure no location at all.
  EOT
}

variable "account_tier" {
  type        = string
  default     = "Standard"
  description = "Performance tier of the Storage Account"

  validation {
    condition     = contains(["Standard", "Premium"], var.account_tier)
    error_message = "account_tier must be Standard or Premium."
  }
}

variable "replication_type" {
  type        = string
  default     = "LRS"
  description = "Replication strategy for the Storage Account"

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "RAGRS", "GZRS"], var.replication_type)
    error_message = "replication_type must be one of LRS, ZRS, GRS, RAGRS, GZRS."
  }
}

variable "access_tier" {
  type        = string
  default     = "Hot"
  description = "Default blob access tier"

  validation {
    condition     = contains(["Hot", "Cool"], var.access_tier)
    error_message = "access_tier must be Hot or Cool."
  }
}

variable "blob_versioning" {
  type        = bool
  default     = false
  description = "Keep a previous version of every blob on overwrite"
}

variable "soft_delete_days" {
  type        = number
  default     = 7
  description = "Days a deleted blob remains recoverable. 0 disables blob soft delete."

  validation {
    condition     = var.soft_delete_days >= 0 && var.soft_delete_days <= 365
    error_message = "soft_delete_days must be between 0 and 365."
  }
}

variable "container_soft_delete_days" {
  type        = number
  default     = 7
  description = "Days a deleted container remains recoverable. This is the recovery window after an unlink, which deletes the container. 0 disables it."

  validation {
    condition     = var.container_soft_delete_days >= 0 && var.container_soft_delete_days <= 365
    error_message = "container_soft_delete_days must be between 0 and 365."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags propagated from the nullplatform notification context"
}
