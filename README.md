# Azure Blob Storage Service

Nullplatform **dependency service** that provisions and manages an Azure
Storage Account. Each application link creates a dedicated blob container plus
a SAS token scoped to it, so apps authenticate with a standard Azure SAS and
never see the account key.

The service lives under [`azure-blob-storage/`](./azure-blob-storage) to keep
the repo open for future Azure storage services.

## What It Does

- Provisions a StorageV2 Storage Account via OpenTofu (performance tier,
  replication, access tier, blob versioning, soft-delete windows)
- Creates a blob container per link and issues a SAS scoped to that container,
  with permissions derived from the link's access level
- Exposes `{LINK}_CONTAINER_NAME` / `{LINK}_SAS_TOKEN` per link, plus
  `{LINK}_ACCOUNT_NAME` / `{LINK}_PRIMARY_BLOB_ENDPOINT` from the service
- Stores OpenTofu state in a shared container under a per-service key
  (`azure-blob-storage/<service_id>/`), authenticating with Azure AD
  (`use_azuread_auth=true`) rather than the account's shared key
- Ships as an OCI worker image: the channel routes `package-exec` to a worker
  built from this repository's [`Dockerfile`](./Dockerfile), with OpenTofu
  baked in

## Repository Layout

```
.
├── azure-blob-storage/
│   ├── specs/
│   │   ├── service-spec.json.tpl   # Service schema (attributes the user sees)
│   │   ├── links/connect.json.tpl  # Link schema (container, access level, SAS)
│   │   └── install/azure/          # OpenTofu: standalone registration module
│   ├── deployment/                 # OpenTofu module: the Storage Account
│   ├── permissions/                # OpenTofu module: container + SAS (per link)
│   ├── workflows/azure/            # Workflow YAMLs (create/update/delete/link/link-update/unlink/read)
│   ├── scripts/azure/              # credential + placement resolution, tofu execution, output writing
│   ├── entrypoint/                 # entrypoint/service/link (agent entrypoint)
│   ├── examples/                   # fixtures and the offline test harness
│   └── values.yaml                 # Static config, optional — all keys may stay empty
├── Dockerfile                      # worker image: worker-bridge + OpenTofu + this service
└── README.md
```

## Service Configuration Parameters

Exposed in the nullplatform UI when creating/updating the service:

| Parameter | Type | Default | Allowed Values | Editable After Create |
|---|---|---|---|---|
| `account_tier` | string | `Standard` | `Standard`, `Premium` | Yes |
| `replication_type` | string | `LRS` | `LRS`, `ZRS`, `GRS`, `RAGRS`, `GZRS` | Yes |
| `access_tier` | string | `Hot` | `Hot`, `Cool` | Yes |
| `blob_versioning` | bool | `false` | | Yes |
| `soft_delete_days` | number | `7` | 0–365 | Yes |
| `container_soft_delete_days` | number | `7` | 0–365 | Yes |

`min_tls_version` (`TLS1_2`) and HTTPS-only are fixed in the module and
deliberately not exposed.

**Account naming**: `<sanitized-service-name><first 8 chars of service ID>`,
capped at 24 characters. Computed once on first create, then persisted and read
back on every later action — recomputing it after a rename would force
`replace` on the account and destroy every byte in it.

## Link Parameters (`connect`)

| Parameter | Type | Default | Description |
|---|---|---|---|
| `container_name` | string | — (required) | 3–63 chars, lowercase, digits, single hyphens |
| `accessLevel` | enum | `read-write` | `read`, `write`, `read-write` |
| `sas_ttl_days` | number | `90` | 1–365 |

`accessLevel` maps onto SAS permissions exactly:

| Access level | Granted | Denied |
|---|---|---|
| `read` | read, list | write, create, add, delete |
| `write` | write, create, add | read, list, delete |
| `read-write` | all six | — |

`write` without `read` is intentional: it serves a producer that uploads and
never reads.

## Service Attributes (post-create, exported as env vars)

| Attribute | Description |
|---|---|
| `account_name` | Storage Account name |
| `primary_blob_endpoint` | Blob service endpoint URL |

`account_id` and `resource_group_name` are also stored, but not exported —
they are read back by the permissions module during link actions.

## Link Attributes (per link, exported as env vars)

Only the container and its credential are exposed at the link level; account
identity comes from the service attributes above, to avoid duplicate env vars
in linked apps.

| Attribute | Env Var Type | Description |
|---|---|---|
| `container_name` | plain | The link's blob container |
| `sas_token` | secret | SAS scoped to that container |

Names are `{LINK_SLUG_UPPER}_{ATTRIBUTE_UPPER}` with hyphens **removed** from
the slug. A link slugged `blob-main` yields `BLOBMAIN_ACCOUNT_NAME`,
`BLOBMAIN_PRIMARY_BLOB_ENDPOINT`, `BLOBMAIN_CONTAINER_NAME` and
`BLOBMAIN_SAS_TOKEN`. With those four the container URL is
`${ENDPOINT}${CONTAINER_NAME}?${SAS_TOKEN}` — no further credentials needed.

## Workflows

| Workflow | Trigger | What It Does |
|---|---|---|
| `create` | Service created | Creates the Storage Account |
| `update` | Service updated | Re-applies tier, replication, access tier, versioning and soft-delete windows |
| `delete` | Service deleted | **Destroys the Storage Account**, every container in it and all their data |
| `link` | Application linked | Creates the link's container and issues the scoped SAS |
| `link-update` | Link updated | Reissues container and SAS after an attribute change |
| `unlink` | Application unlinked | **Deletes the link's container** |
| `read` | Read action | Reports current attributes; touches nothing in Azure |

## Requirements

### nullplatform prerequisites

- An agent with worker orchestration enabled, and this service's package slug
  listed in the agent module's `worker_orchestrated_packages`
- The agent's worker needs the Azure environment (`ARM_*`, `RESOURCE_GROUP`,
  `AZURE_TFSTATE_*`); see "How to register" below
- A Storage Account with an **existing** blob container for OpenTofu state.
  This service never creates one: it writes a per-service key into a container
  that already exists

### Azure permissions

The identity running this service — the agent's service principal or managed
identity — needs:

| On | Role | For |
|---|---|---|
| The target resource group | `Contributor` | creating Storage Accounts and containers |
| The tfstate Storage Account | `Storage Blob Data Contributor` | reading and writing state |

`Storage Blob Data Contributor` does not grant ARM `listKeys`, which is exactly
why the backend is initialized with `use_azuread_auth=true`: without that flag
the `azurerm` backend falls back to shared-key auth and resolves the account
key through `listKeys`, which that role denies.

There is no `specs/requirements/` module here, unlike the AWS services: the
AssumeRole permissions model that module implements is AWS-only. Grant the
roles above directly instead.

### Runtime dependencies

- **OpenTofu** — baked into the worker image at the version pinned by the
  Dockerfile's `TOFU_VERSION`. `do_tofu` keeps a download fallback for agents
  without it, but the packaged deployment never uses it.
- `bash`, `jq`, `np` and `curl` ship in the `worker-bridge` base image.
- **No `azure-cli`**: nothing under `scripts/azure/` shells out to `az`.

## How to register this service in nullplatform

Three pieces, in three layers.

**1 — The agent** must be able to run the worker and give it the Azure
environment. In the [`nullplatform/agent`](https://github.com/nullplatform/tofu-modules/tree/main/nullplatform/agent)
module:

```hcl
  worker_orchestrated_packages = ["azure-blob-storage"]

  worker = {
    patches = [{
      target = { package = "azure-blob-storage" }
      merge = {
        spec = {
          containers = [{
            name    = "worker"
            envFrom = [{ secretRef = { name = "<agent-secret>" } }]
          }]
        }
      }
    }]
  }

  extra_envs = {
    RESOURCE_GROUP                = "<target resource group>"
    AZURE_TFSTATE_STORAGE_ACCOUNT = "<tfstate account>"
    AZURE_TFSTATE_CONTAINER       = "<tfstate container>"
    AZURE_TFSTATE_RESOURCE_GROUP  = "<tfstate resource group>"
    ARM_CLIENT_ID                 = var.azure_client_id
    ARM_CLIENT_SECRET             = var.azure_client_secret
    ARM_TENANT_ID                 = var.azure_tenant_id
    ARM_SUBSCRIPTION_ID           = var.azure_subscription_id
  }
```

The `envFrom` is required. Since tofu-modules v7.3.0 the module injects the
Azure environment only into the `containers` package's worker, so any other
package's worker starts with none of it.

**2 — The service specification**, with the worker image pinned by digest:

```hcl
module "service_definition_azure_blob_storage" {
  source              = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/service_definition?ref=v7.3.0"
  nrn                 = var.nrn
  service_path        = "azure-blob-storage"
  service_name        = "Azure Blob Storage"
  repository_name     = "services-blob-storage"
  repository_branch   = "<tag>"
  repository_ref_type = "tags"
  available_links     = ["connect"]

  package = {
    version = "<semver>"
    slug    = "azure-blob-storage"
    artifacts = [{
      name = "AzureBlobStorage"
      type = "oci_image"
      meta = {
        registry   = "public.ecr.aws"
        repository = "nullplatform/services/azure-blob-storage"
        digest     = "sha256:..."
      }
    }]
  }
}
```

The digest comes from the GitHub release the pipeline finalizes. Bump
`package.version` on every release: a revision published with
`default = false` is never promoted, and service instances stay on the
revision they were created with.

**3 — The channel association**, routing the action to the worker:

```hcl
module "service_agent_association_azure_blob_storage" {
  source                     = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/service_definition_agent_association?ref=v7.3.0"
  nrn                        = var.nrn
  api_key                    = var.np_api_key
  service_path               = "azure-blob-storage"
  service_specification_slug = module.service_definition_azure_blob_storage.service_specification_slug
  tags_selectors             = var.tags_selectors

  worker_orchestrator = true
  package_slug        = module.service_definition_azure_blob_storage.service_specification_slug
}
```

A ready-made version of pieces 2 and 3 lives in
[`azure-blob-storage/specs/install/azure/`](azure-blob-storage/specs/install/azure)
for a standalone install.

## Important considerations

### Unlink deletes data

`unlink` deletes the link's container and everything in it. This differs from
the database services, which preserve data and only revoke grants. Azure offers
no equivalent to `REVOKE`: a SAS cannot be revoked individually — only rotating
the account key invalidates one, which would break every other link at once —
so deleting the container is what makes revocation real.

`container_soft_delete_days` (default 7) is the recovery window for an
accidental unlink. Do not set it to 0 unless you accept that an unlink is
immediately unrecoverable.

### Delete destroys everything

`delete` destroys the Storage Account, which deletes every container created by
every link, and all their data. There is no final snapshot.

### An expired SAS is not renewed by re-running `link-update`

The SAS start time is anchored in state (`time_static`) so the token stays
stable across applies — otherwise every service `update` would reissue it and
rewrite the linked app's environment for no reason. The consequence is that
once `sas_ttl_days` has elapsed, `link-update` regenerates the same
start/expiry pair and the app keeps a dead credential. The only renewal path
today is changing `sas_ttl_days` to a different value.

### The account is reachable from the public internet

The account is created with `public_network_access_enabled = true` and a
network rule of `default_action = "Allow"`, bypassing only `AzureServices`.
Access still requires a valid SAS, and public blob access is disabled
(`allow_nested_items_to_be_public = false`), but the endpoint itself is
internet-facing. Private endpoints and network ACLs are not implemented.

### Storage Account name global uniqueness

Azure requires 3–24 lowercase alphanumeric characters, unique across all of
Azure. A collision surfaces as an Azure error at `create` time.

### The tfstate is a credential store

The permissions module's state holds the account's connection string (that is,
its access key) and every SAS it issued. That is unavoidable with Terraform,
but it means **anyone with read access to the tfstate Storage Account holds
every access key and every SAS this service has issued.** Treat that account
with the same care as a vault.

## Testing

The offline suite needs no Azure session, no agent and no platform: it stubs
`np`, `az` and `tofu` on `PATH`.

```bash
bash azure-blob-storage/examples/run-all-tests.sh
```

A dry run parses a notification fixture, prints the derived variables and
validates the Terraform module:

```bash
bash azure-blob-storage/examples/dry-run.sh
bash azure-blob-storage/examples/dry-run.sh azure-blob-storage/examples/link.json
```

`full-test.sh` applies the modules against a real Azure subscription, outside
the platform. It creates real resources.

## CI

| Workflow | On | Checks |
|---|---|---|
| `specs.yml` | PR | service and link specs, plus the offline suite |
| `terraform.yml` | PR | `tofu fmt`, `init` and `validate` on both modules |
| `shellcheck.yml` | PR | every shell script |
| `trivy.yml` | PR | Terraform and Dockerfile misconfiguration scan |
| `conventional-commit.yml`, `branch-validation.yml` | PR | commit and branch naming |
| `release.yml` | push to `main` | release-please, image build and push to ECR Public, artifact registration |

Releases are cut by release-please from conventional commits. Each one builds
the worker image, pushes it to
`public.ecr.aws/nullplatform/services/azure-blob-storage`, registers it as a
nullplatform `oci_image` artifact and records the digest on the GitHub release.
