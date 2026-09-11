# Backend configuration is supplied at "tofu init" time by
# build_permissions_context. Each link gets its own state key inside the
# service's tfstate container, so destroying a link's state on unlink cannot
# touch the Storage Account's own state.
terraform {
  backend "azurerm" {}
}
