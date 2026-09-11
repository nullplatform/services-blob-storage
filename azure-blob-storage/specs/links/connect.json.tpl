{
  "name": "Connect",
  "slug": "connect",
  "unique": false,
  "assignable_to": "any",
  "use_default_actions": true,
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
      "required": ["container_name"],
      "properties": {
        "container_name": {
          "type": "string",
          "title": "Container Name",
          "export": true,
          "description": "Blob container created for this link. 3-63 characters, lowercase letters, digits and single hyphens.",
          "pattern": "^[a-z0-9]([a-z0-9]|-(?!-)){1,61}[a-z0-9]$",
          "editableOn": ["create"],
          "order": 1
        },
        "accessLevel": {
          "type": "string",
          "title": "Access Level",
          "default": "read-write",
          "enum": ["read", "write", "read-write"],
          "description": "read grants read+list, write grants write+create+add, read-write grants both plus delete.",
          "editableOn": ["create", "update"],
          "order": 2
        },
        "sas_ttl_days": {
          "type": "number",
          "title": "SAS Lifetime (days)",
          "default": 90,
          "minimum": 1,
          "maximum": 365,
          "description": "How long the issued SAS token stays valid. The token is stable across updates and is only reissued when this value changes.",
          "editableOn": ["create", "update"],
          "order": 3
        },
        "sas_token": {
          "type": "string",
          "title": "SAS Token",
          "export": {"type": "environment_variable", "secret": true},
          "visibleOn": ["read"],
          "editableOn": [],
          "description": "Shared Access Signature scoped to this container (auto-populated, delivered as a secret env var)",
          "order": 4
        }
      }
    },
    "values": {}
  }
}
