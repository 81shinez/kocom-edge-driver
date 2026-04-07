# SmartThings Packaging Constraints

## Purpose

This note captures SmartThings packaging constraints that were confirmed while validating and deploying the driver package.
It complements the official SmartThings device profile documentation and the SmartThingsCommunity Edge driver examples with repo-specific decisions.

## References

- Official docs: `Device Profiles`, `Device Preferences`, `Display Types`
- Community reference repo: `SmartThingsCommunity/SmartThingsEdgeDrivers`
- Empirical validation: package upload probes against the SmartThings API on 2026-04-07

## Confirmed Constraints

### Gateway profile

- The parent `gateway` profile packages successfully with:
  - `refresh` capability only
  - `Others` category
  - embedded preferences using `string`, `integer`, and `boolean`
- The package upload rejected earlier variants that used:
  - `enumeration` for `protocolPreset`
  - long JSON text preferences using large `maxLength` values

## Preference decisions

- `protocolPreset` stays a plain `string` preference in v1.
  - Current supported preset is still `kocom-default`, so an enum picker is not required yet.
- `deviceCodeOverrides` and `commandOverrides` stay `stringType: text`.
- Both override preferences use `maxLength: 255` and default to `{}`.
  - This is a conservative packaging-safe limit confirmed by upload probes.

## Gas profile decision

- The `gas-close-only` child profile uses category `Others`.
- Using valve-like categories with only the custom `earthgarden50570.closeOnlyValve` capability caused package upload failures.
- `Others` avoids implying an unsafe standard open/close valve UI while keeping the close-only custom capability intact.

## Deployment rule

- If a future profile or preference change causes upload `422`, reproduce it with a minimal single-profile probe before changing runtime code.
- Prefer packaging-safe standard primitives over richer profile metadata when the SmartThings API behavior diverges from the general documentation.
