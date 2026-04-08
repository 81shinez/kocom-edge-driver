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

## 가스 프로필 결정

- 초기(v1) 기준: custom-only 가스 프로필 + `Others` 카테고리.
- custom `earthgarden50570.closeOnlyValve`만 포함한 상태에서 valve 계열 카테고리를 쓰면 패키지 업로드 실패가 발생했다.
- 현재(2026-04-08) 기준: `gas-close-only`는 표준 `valve` + custom close-only capability + `WaterValve` 카테고리를 사용하고, 런타임에서 `open`을 차단한다.

## Deployment rule

- If a future profile or preference change causes upload `422`, reproduce it with a minimal single-profile probe before changing runtime code.
- Prefer packaging-safe standard primitives over richer profile metadata when the SmartThings API behavior diverges from the general documentation.

## 2026-04-08 프로필 호환성 업데이트

- `gas-close-only`는 외부 공유 호환성을 위해 표준 `valve` + custom `earthgarden50570.closeOnlyValve` 조합, `WaterValve` 카테고리로 유지한다.
- 로컬 패키지 빌드 검증(`edge:drivers:package --build-only`)은 해당 메타데이터로 통과했다.
- 런타임 안전 정책은 유지한다: 가스 `open` 명령 경로는 비활성화 상태를 유지한다.
