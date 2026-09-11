output "account_name" {
  description = "Storage Account name"
  value       = azurerm_storage_account.storage.name
}

output "primary_blob_endpoint" {
  description = "Blob service endpoint URL"
  value       = azurerm_storage_account.storage.primary_blob_endpoint
}

output "account_id" {
  description = "ARM resource ID of the Storage Account"
  value       = azurerm_storage_account.storage.id
}

output "resource_group_name" {
  description = "Azure resource group holding the Storage Account"
  value       = azurerm_storage_account.storage.resource_group_name
}
