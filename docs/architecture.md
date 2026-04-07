# 아키텍처 개요

## 목표

이 드라이버는 SmartThings Hub가 LAN TCP-RS485 브리지에 연결되고, 브리지 뒤의 코콤 월패드 버스에서 상태 프레임을 수신하거나 제어 명령을 전송하는 구조를 가진다.

## 최상위 구조

- `config.yml`
  - Edge 패키지 메타데이터와 `lan`, `discovery` 권한을 선언한다.
- `profiles/`
  - 부모 게이트웨이와 child device profile 정의를 둔다.
- `capabilities/`
  - custom capability 정의와 presentation 원본을 둔다.
- `src/init.lua`
  - Driver template 조립만 담당한다.
- `src/`
  - discovery, lifecycle, command, preference, child 관리, event emission을 담당한다.
- `src/kocom/`
  - 코콤 전용 통신/프로토콜/세션 계층을 둔다.
- `src/test/`
  - integration_test 스타일 검증 코드를 둔다.

## 런타임 흐름

1. 사용자가 `Scan Nearby`를 실행하면 `discovery.lua`가 설정용 부모 device를 만든다.
2. 사용자는 부모 device preference에서 `host`와 `port`를 입력한다.
3. `infoChanged`가 발생하면 `preferences.lua`가 설정을 검증하고 `session.lua`를 재시작한다.
4. `session.lua`는 `transport.lua`를 통해 TCP 연결을 열고 읽기 루프를 시작한다.
5. 수신 데이터는 `parser.lua`에서 프레임으로 분리된다.
6. 각 프레임은 `protocol.lua`에서 논리 장치 상태로 해석된다.
7. `registry.lua`가 상태를 저장하고 `child_devices.lua`가 필요한 child를 생성한다.
8. 기존 child가 있으면 `emitter.lua`가 capability event를 보낸다.
9. child command는 `command_handlers.lua`를 거쳐 `protocol.lua`의 명령 생성기로 전달된다.
10. `session.lua`가 raw packet을 전송하고 confirmation frame을 기다린다.

## 모듈 역할

### `src/init.lua`

- Driver 생성
- lifecycle handler 등록
- capability handler 등록
- discovery handler 연결

### `src/discovery.lua`

- 자동 네트워크 검색 대신 수동 설정용 부모만 생성
- 이미 미설정 부모가 있으면 중복 생성 방지

### `src/lifecycle_handlers.lua`

- 부모/자식 `init`, `added`, `removed`, `infoChanged`
- 부모 session 시작/중지
- child 초기 상태 재적용

### `src/preferences.lua`

- preference 값 정규화
- 기본 포트 처리
- JSON override 파싱
- 유효하지 않은 설정을 사용자 로그로 노출

### `src/child_devices.lua`

- child key 생성/파싱
- profile 선택
- label 생성
- child metadata 생성

### `src/emitter.lua`

- 내부 상태를 SmartThings 표준/custom capability event로 변환
- child가 생성된 뒤 최신 캐시 상태 재적용

### `src/kocom/transport.lua`

- TCP connect/send/receive/close
- partial write 보정

### `src/kocom/parser.lua`

- prefix/suffix/길이/checksum 기반 프레임 분리
- garbage byte 제거
- multi-frame 처리

### `src/kocom/protocol.lua`

- raw frame 해석
- logical device state 생성
- command packet 생성
- confirmation matcher 생성

### `src/kocom/registry.lua`

- child key별 최신 상태 저장
- sibling switch 상태 보관

### `src/kocom/session.lua`

- 부모별 persistent TCP session
- command queue
- confirmation pending 처리
- retry/backoff
- 부모/자식 online/offline 전파

## 부모/자식 데이터 모델

- 부모 device
  - 브리지 연결 정보와 runtime 설정을 가진다.
- child device
  - 실제 SmartThings UI 엔터티이다.
  - 상태는 parent session에서 갱신한다.

child key 형식:

```text
<deviceType>-<room>-<device>-<subType>
```

예:

```text
light-1-0-none
thermostat-2-0-none
elevator-1-0-none
```

## 문서 유지 원칙

- 프로토콜 매핑이 바뀌면 `docs/protocol.md`를 같이 수정한다.
- 부모/자식 구조가 바뀌면 이 문서를 먼저 갱신한다.
