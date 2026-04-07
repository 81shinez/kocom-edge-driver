# Kocom Edge Driver Working Guide

이 저장소는 코콤 월패드용 SmartThings Edge LAN 드라이버와 관련 문서를 함께 유지하는 작업 공간이다. 구현과 문서는 항상 같이 움직이며, 코드 구조와 결정 이유를 다른 작업자나 에이전트가 바로 이어받을 수 있도록 유지한다.

## 프로젝트 목적

- RS485 기반 코콤 월패드를 SmartThings Edge Driver로 로컬 제어한다.
- 통신 경로는 LAN TCP-RS485 브리지(EW11 계열 포함)를 기본 전제로 한다.
- SmartThings 앱에는 게이트웨이 부모 1개와 기능별 child device들을 노출한다.
- 안정성과 재시도, 상태 확인, 문서화된 override 지점을 우선한다.

## 우선 참조 소스

1. SmartThings 공식 문서
   - Edge 구조, LAN 소켓, 드라이버 패키지 구조, 테스트 문서를 우선 기준으로 본다.
2. SmartThingsCommunity/SmartThingsEdgeDrivers
   - `wemo`, `lan-thing` 등 공식 커뮤니티 드라이버의 폴더 구조, `init.lua` 패턴, `src/test` 배치를 따른다.
3. lunDreame/kocom-wallpad
   - 코콤 프레임 구조, 장치 코드, 명령/상태 의미를 해석하는 참고 자료로만 사용한다.

## 코드 컨벤션

- `src/init.lua`는 얇게 유지하고, 실제 구현은 별도 모듈로 분리한다.
- 로그는 `log` 모듈을 사용한다.
- 부모/자식 상태나 연결 정보는 `device:set_field(..., { persist = true })`와 런타임 session 객체로 분리한다.
- 장치별 반복 작업은 `device.thread:call_on_schedule(...)`를 우선 사용한다.
- 네트워크 소켓은 `cosock.socket`만 사용한다.
- profile 파일명은 사람이 읽기 쉬운 이름을 사용한다.
- 표준 Capability를 우선하고, custom capability는 최소한으로 유지한다.

## 모듈 경계

- `src/discovery.lua`
  - `Scan Nearby` 시 설정용 부모 device를 생성한다.
- `src/lifecycle_handlers.lua`
  - `added`, `init`, `infoChanged`, `removed`를 처리한다.
- `src/command_handlers.lua`
  - child capability command를 protocol command로 변환한다.
- `src/child_devices.lua`
  - child key 규칙, 생성 metadata, label 생성, child 조회를 담당한다.
- `src/preferences.lua`
  - preference 검증, JSON override 파싱, runtime config 생성.
- `src/emitter.lua`
  - 내부 상태를 SmartThings capability event로 변환한다.
- `capabilities/`
  - custom capability 정의와 presentation 원본을 저장한다.
- `src/kocom/*`
  - transport, parser, protocol, registry, session, mappings를 분리한다.

## Child Device 규칙

- child key는 `<deviceType>-<room>-<device>-<subType>` 형식으로 고정한다.
- 첫 유효 상태 프레임을 받기 전에는 child를 생성하지 않는다.
- child profile은 `profiles/` 아래의 고정 파일명을 사용한다.
- 부모가 offline이면 해당 부모의 child 전체를 offline으로 내린다.

## Preference / Override 원칙

- 부모 device의 preference만 사용한다.
- `host`, `port`, `protocolPreset`, `deviceCodeOverrides`, `commandOverrides`, `debugUnknownFrames`, `captureSpecialFrames`를 공용 인터페이스로 유지한다.
- `deviceCodeOverrides`는 표준 장치 코드를 덮어쓸 때만 사용한다.
- `commandOverrides`는 특정 child key 또는 device type의 raw packet override를 지정할 때만 사용한다.
- override를 추가하면 `docs/protocol.md`와 `docs/special-features.md`를 같이 갱신한다.
- 현재 배포 대상 계정의 custom capability namespace는 `earthgarden50570`이다. custom capability ID를 바꾸면 `src/constants.lua`, `profiles/`, `capabilities/`, `README.md`, `docs/special-features.md`를 같은 변경 단위에서 함께 수정한다.

## 테스트 / 검증 체크리스트

- `src/test` 아래에 SmartThings `integration_test` 스타일 테스트를 둔다.
- 최소 검증 항목
  - 부모 discovery metadata
  - preference 파싱과 재적용
  - frame split / checksum
  - child key 생성과 label 규칙
  - command packet 생성
  - pending confirmation / retry 로직의 핵심 분기

## 문서 갱신 규칙

- 구조 변경 시 `docs/architecture.md`를 같이 수정한다.
- 프로토콜 해석 변경 시 `docs/protocol.md`를 같이 수정한다.
- 컨벤션 변경 시 `docs/conventions.md`를 같이 수정한다.
- 특수 기능 지원 범위가 바뀌면 `docs/special-features.md`를 같이 수정한다.
- 새 작업자가 이 파일만 읽고도 어디를 먼저 봐야 하는지 알 수 있어야 한다.
