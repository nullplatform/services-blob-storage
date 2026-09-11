variable "link_id" {
  type        = string
  description = "Nullplatform link ID, used for tagging and traceability"

  validation {
    condition     = length(var.link_id) > 0
    error_message = "link_id must not be empty. build_permissions_context refuses to run without it, and this mirrors that rule."
  }
}

variable "storage_account_name" {
  type        = string
  description = "Existing Storage Account created by the deployment module"

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "storage_account_name must be 3-24 lowercase alphanumeric characters."
  }
}

variable "resource_group_name" {
  type        = string
  description = "Resource group holding the Storage Account"

  validation {
    condition     = length(var.resource_group_name) > 0
    error_message = "resource_group_name must not be empty. It comes from the service attributes, falling back to values.yaml."
  }
}

variable "container_name" {
  type        = string
  description = "Blob container to create for this link"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9]|-[a-z0-9])*$", var.container_name)) && length(var.container_name) >= 3 && length(var.container_name) <= 63
    error_message = "container_name must be 3-63 characters of lowercase letters, digits and single hyphens, starting and ending with a letter or digit."
  }
}

variable "access_level" {
  type        = string
  default     = "read-write"
  description = "Permission level granted by the issued SAS token"

  validation {
    condition     = contains(["read", "write", "read-write"], var.access_level)
    error_message = "access_level must be read, write or read-write."
  }
}

variable "sas_ttl_days" {
  type        = number
  default     = 90
  description = "Validity window of the issued SAS token, in days"

  validation {
    condition     = var.sas_ttl_days >= 1 && var.sas_ttl_days <= 365
    error_message = "sas_ttl_days must be between 1 and 365."
  }
}
