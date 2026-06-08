# Compass Schemas

Schemas are versioned by transport and major wire contract. A `schema_version`
field is required in every daemon request, response, and server event.

Compatibility rules:

- Additive fields keep the same schema version when clients can safely ignore them.
- Required field changes, renamed methods, or changed enum meanings require a new
  versioned directory.
- Swift and Rust types should be updated in the same commit as schema changes.
