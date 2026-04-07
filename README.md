# Kocom Wallpad SmartThings Edge Driver

코콤 월패드 RS485 버스를 SmartThings Edge LAN 드라이버로 로컬 제어하기 위한 저장소입니다.  
SmartThings Hub가 LAN TCP-RS485 브리지(EW11 계열 포함)에 연결되고, 부모 게이트웨이 1개와 기능별 child device들을 SmartThings 앱에 노출하는 구조를 사용합니다.

## 현재 범위

- LAN TCP-RS485 브리지를 통한 코콤 월패드 제어
- 부모 gateway device + 동적 child device 구조
- 상태 프레임 기반 child 자동 생성
- command confirmation / retry / reconnect 처리
- 문서화된 `deviceCodeOverrides`, `commandOverrides` 지원
- 특수 기능 frame capture 기반 확장 포인트 제공

## 지원 장치

| 장치 | SmartThings 표현 | 상태 |
| --- | --- | --- |
| 조명 | `switch` | 기본 지원 |
| 콘센트 | `switch` | 기본 지원 |
| 난방 | `thermostatMode`, `thermostatHeatingSetpoint`, `temperatureMeasurement` | 기본 지원 |
| 환기 | `switch`, `switchLevel` | 기본 지원 |
| 가스 | `kocomcommunity.closeOnlyValve` | 닫기 전용 지원 |
| 엘리베이터 | `momentary`, `kocomcommunity.elevatorDirection`, `kocomcommunity.elevatorFloor` | 기본 지원 |
| 모션 | `motionSensor` | 기본 지원 |
| 공기질 | `carbonDioxideMeasurement`, `temperatureMeasurement`, `relativeHumidityMeasurement` | 기본 지원 |
| 공동현관문 / 현관문 | `momentary`, `contactSensor` | capture + override 기반 |
| 초인종 | `button` | capture 기반 |

참고:

- child device는 첫 유효 상태 프레임을 받은 뒤에 생성됩니다.
- `air_conditioner` 장치 코드는 예약되어 있지만 현재 v1에서는 child profile과 이벤트 매핑이 연결되어 있지 않습니다.

## 동작 방식

1. SmartThings 앱에서 `Scan Nearby`를 실행하면 설정용 부모 gateway device가 생성됩니다.
2. 부모 device preference에 브리지 `host`, `port`를 입력합니다.
3. 드라이버가 TCP 세션을 열고 코콤 프레임을 수신합니다.
4. 프레임이 장치 상태로 해석되면 필요한 child device를 생성하고 상태를 반영합니다.
5. child command는 부모 세션을 통해 raw packet으로 전송되고, 후속 confirmation frame으로 성공 여부를 확인합니다.

child key 형식은 아래와 같습니다.

```text
<deviceType>-<room>-<device>-<subType>
```

예:

```text
light-1-0-none
thermostat-2-0-none
elevator-1-0-none
```

## 빠른 시작

### 1. 준비물

- SmartThings Edge를 지원하는 허브
- 코콤 월패드와 연결된 TCP-RS485 브리지
- SmartThings CLI 로그인 환경

이 저장소에는 Windows에서 바로 사용할 수 있는 CLI가 포함되어 있습니다.

```powershell
.\.tools\smartthings-cli\smartthings.cmd --version
```

### 2. 드라이버 패키징

로컬 zip만 만들려면:

```powershell
.\.tools\smartthings-cli\smartthings.cmd edge:drivers:package --build-only .artifacts\kocom-edge-driver.zip .
```

채널 할당과 허브 설치까지 진행하려면:

```powershell
.\.tools\smartthings-cli\smartthings.cmd edge:drivers:package --install .
```

### 3. SmartThings 앱에서 추가

1. 허브가 연결된 위치(Location)에서 `Scan Nearby`를 실행합니다.
2. `Kocom Gateway N` 부모 device가 생성되면 상세 화면으로 들어갑니다.
3. preference에 브리지 `host`와 `port`를 입력합니다.
4. 월패드에서 실제 장치를 한 번 조작하거나 상태 프레임이 들어오면 child device가 생성됩니다.

## 부모 device preference

| 이름 | 설명 |
| --- | --- |
| `host` | TCP-RS485 브리지 IP 또는 호스트명 |
| `port` | 브리지 포트, 기본값 `8899` |
| `protocolPreset` | 현재는 `kocom-default` 1종 |
| `deviceCodeOverrides` | 표준 장치 코드 override JSON |
| `commandOverrides` | child key 또는 장치 타입별 raw packet override JSON |
| `debugUnknownFrames` | 미매핑 frame을 hub log에 출력 |
| `captureSpecialFrames` | 특수 기능 학습용 frame capture 활성화 |

`deviceCodeOverrides` 예:

```json
{
  "light": "0x0E",
  "ventilation": 72
}
```

`commandOverrides` 예:

```json
{
  "light": {
    "turn_on": {
      "packetHex": "AA5530BC000E01010000FF0000000000005C0D0D",
      "timeoutMs": 1000
    }
  },
  "light-1-0-none": {
    "turn_off": {
      "packetHex": "AA5530BC000E01010000000000000000005D0D0D",
      "timeoutMs": 1000
    }
  }
}
```

## 개발 메모

### 저장소 구조

```text
config.yml                 Edge 패키지 메타데이터
profiles/                  부모 및 child profile
capabilities/              custom capability 정의
src/init.lua               얇은 드라이버 엔트리 포인트
src/discovery.lua          Scan Nearby 부모 생성
src/lifecycle_handlers.lua 부모/자식 lifecycle
src/command_handlers.lua   capability command -> protocol command
src/preferences.lua        preference 검증 및 runtime config
src/child_devices.lua      child key, label, metadata
src/emitter.lua            내부 상태 -> capability event
src/kocom/                 transport, parser, protocol, registry, session
src/test/                  integration_test 스타일 테스트
```

### 테스트 포인트

현재 `src/test/`에는 아래 핵심 검증이 포함되어 있습니다.

- discovery metadata 생성
- preference 파싱과 기본값 적용
- frame split / checksum 처리
- child key 생성 규칙
- command packet 생성

## 관련 문서

- [아키텍처 개요](docs/architecture.md)
- [코드 컨벤션](docs/conventions.md)
- [프로토콜 메모](docs/protocol.md)
- [특수 기능 현황](docs/special-features.md)

## 구현 원칙

- `src/init.lua`는 얇게 유지하고 구현은 역할별 모듈로 분리합니다.
- 네트워크 소켓은 `cosock.socket`만 사용합니다.
- 부모가 offline이면 해당 부모의 child 전체를 offline으로 전파합니다.
- override나 프로토콜 해석을 바꾸면 관련 문서도 같은 범위에서 함께 갱신합니다.
