{
  "name": "Azure Blob Storage",
  "slug": "azure-blob-storage",
  "type": "dependency",
  "unique": false,
  "assignable_to": "any",
  "use_default_actions": true,
  "available_links": ["connect"],
  "selectors": {
    "category": "Storage",
    "imported": false,
    "provider": "Azure",
    "sub_category": "Object Storage"
  },
  "attributes": {
    "schema": {
      "type": "object",
      "$schema": "http://json-schema.org/draft-07/schema#",
      "required": ["account_tier", "replication_type"],
      "uiSchema": {
        "type": "VerticalLayout",
        "elements": [
          {
            "type": "Control",
            "label": "Performance Tier",
            "scope": "#/properties/account_tier",
            "options": { "format": "radio" }
          },
          {
            "type": "Control",
            "label": "Replication",
            "scope": "#/properties/replication_type"
          },
          {
            "type": "Control",
            "label": "Access Tier",
            "scope": "#/properties/access_tier",
            "options": { "format": "radio" }
          },
          {
            "type": "Categorization",
            "options": {
              "collapsable": { "label": "ADVANCED", "collapsed": true }
            },
            "elements": [
              {
                "type": "Category",
                "label": "Data protection",
                "elements": [
                  {
                    "type": "Control",
                    "label": "Blob Versioning",
                    "scope": "#/properties/blob_versioning"
                  },
                  {
                    "type": "Control",
                    "label": "Blob Soft Delete (days)",
                    "scope": "#/properties/soft_delete_days"
                  },
                  {
                    "type": "Control",
                    "label": "Container Soft Delete (days)",
                    "scope": "#/properties/container_soft_delete_days"
                  }
                ]
              }
            ]
          },
          {
            "type": "Control",
            "label": "Storage Account Name",
            "scope": "#/properties/account_name"
          },
          {
            "type": "Control",
            "label": "Blob Endpoint",
            "scope": "#/properties/primary_blob_endpoint"
          }
        ]
      },
      "properties": {
        "account_tier": {
          "type": "string",
          "title": "Performance Tier",
          "default": "Standard",
          "enum": ["Standard", "Premium"],
          "description": "Standard uses magnetic storage and is the right default. Premium uses SSDs for low-latency workloads and costs significantly more.",
          "editableOn": ["create", "update"],
          "order": 1
        },
        "replication_type": {
          "type": "string",
          "title": "Replication",
          "default": "LRS",
          "enum": ["LRS", "ZRS", "GRS", "RAGRS", "GZRS"],
          "description": "How many copies Azure keeps and where. LRS is single-datacenter, ZRS spreads across availability zones, GRS/GZRS also replicate to a paired region.",
          "editableOn": ["create", "update"],
          "order": 2
        },
        "access_tier": {
          "type": "string",
          "title": "Access Tier",
          "default": "Hot",
          "enum": ["Hot", "Cool"],
          "description": "Hot costs more to store and less to read. Cool is the reverse — use it for data read rarely.",
          "editableOn": ["create", "update"],
          "order": 3
        },
        "blob_versioning": {
          "type": "boolean",
          "title": "Blob Versioning",
          "default": false,
          "description": "Keep a previous version of every blob on overwrite. Increases storage cost.",
          "editableOn": ["create", "update"],
          "order": 4
        },
        "soft_delete_days": {
          "type": "number",
          "title": "Blob Soft Delete (days)",
          "default": 7,
          "minimum": 0,
          "maximum": 365,
          "description": "Days a deleted blob stays recoverable. 0 disables blob soft delete.",
          "editableOn": ["create", "update"],
          "order": 5
        },
        "container_soft_delete_days": {
          "type": "number",
          "title": "Container Soft Delete (days)",
          "default": 7,
          "minimum": 0,
          "maximum": 365,
          "description": "Days a deleted container stays recoverable. This is the recovery window after an accidental unlink, which deletes the container. 0 disables it.",
          "editableOn": ["create", "update"],
          "order": 6
        },
        "account_name": {
          "type": "string",
          "title": "Storage Account Name",
          "export": true,
          "visibleOn": ["read"],
          "editableOn": [],
          "description": "Azure Storage Account name (auto-populated after creation)",
          "order": 7
        },
        "primary_blob_endpoint": {
          "type": "string",
          "title": "Blob Endpoint",
          "export": true,
          "visibleOn": ["read"],
          "editableOn": [],
          "description": "Blob service endpoint URL (auto-populated after creation)",
          "order": 8
        },
        "account_id": {
          "type": "string",
          "export": false,
          "visibleOn": [],
          "editableOn": [],
          "description": "Internal: ARM resource ID of the Storage Account"
        },
        "resource_group_name": {
          "type": "string",
          "export": false,
          "visibleOn": [],
          "editableOn": [],
          "description": "Internal: Azure resource group holding the account. Read by the permissions module during link actions."
        }
      }
    },
    "values": {}
  }
}
