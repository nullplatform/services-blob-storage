terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# Credentials come from the environment (ARM_SUBSCRIPTION_ID, ARM_CLIENT_ID,
# ARM_TENANT_ID, ARM_CLIENT_SECRET), exported by the
# resolve_azure_credentials workflow step. When none are set the provider
# falls back to the agent's own managed identity, or to an "az login" session
# during local testing.
provider "azurerm" {
  features {}
}
