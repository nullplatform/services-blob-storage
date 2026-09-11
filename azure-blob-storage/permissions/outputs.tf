output "container_name" {
  description = "Blob container created for this link"
  value       = azurerm_storage_container.link.name
}

output "sas_token" {
  description = "SAS token scoped to this container, with the link's access level"
  value       = data.azurerm_storage_account_blob_container_sas.link.sas
  sensitive   = true
}

# Emitted for debugging only. The service spec already exports the endpoint,
# so write_link_outputs must not patch it onto the link as well: service and
# link attributes share one env-var namespace per link, and both exporting it
# would collide on a single {LINK_SLUG}_..._ENDPOINT variable.
output "blob_endpoint" {
  description = "Blob service endpoint of the target Storage Account"
  value       = data.azurerm_storage_account.target.primary_blob_endpoint
}
