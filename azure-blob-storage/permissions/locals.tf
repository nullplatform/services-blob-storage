locals {
  # access_level -> the SAS permissions block.
  #
  # read       browse and download
  # write      upload and append, but never remove
  # read-write everything above plus delete
  access_matrix = {
    "read" = {
      read   = true
      list   = true
      add    = false
      create = false
      write  = false
      delete = false
    }
    "write" = {
      read   = false
      list   = false
      add    = true
      create = true
      write  = true
      delete = false
    }
    "read-write" = {
      read   = true
      list   = true
      add    = true
      create = true
      write  = true
      delete = true
    }
  }

  perms = local.access_matrix[var.access_level]

  sas_expiry_hours = var.sas_ttl_days * 24
}
