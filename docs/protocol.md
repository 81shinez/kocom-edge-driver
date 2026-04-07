# 코콤 프로토콜 메모

## 기본 프레임 규칙

- Prefix: `AA55`
- Suffix: `0D0D`
- 고정 길이: `21` bytes
- Checksum: frame body의 `3번째 byte`부터 `18번째 byte`까지 합을 `256`으로 나눈 나머지

## 필드 해석

- `packet_type`: 4번째 byte 상위 nibble
- `dest`: 6~7번째 byte
- `src`: 8~9번째 byte
- `command`: 10번째 byte
- `payload`: 11~18번째 byte
- `checksum`: 19번째 byte

## peer 해석

- 목적지 장치 코드가 `0x01`이면 source 쪽 장치를 peer로 본다.
- source 장치 코드가 `0x01`이면 destination 쪽 장치를 peer로 본다.
- 둘 다 아니면 알 수 없는 장치로 처리하고 디버그 로그만 남긴다.

## 표준 장치 코드

| 장치 | 코드 |
| --- | --- |
| light | `0x0E` |
| outlet | `0x3B` |
| thermostat | `0x36` |
| air_conditioner | `0x39` |
| ventilation | `0x48` |
| gas | `0x2C` |
| elevator | `0x44` |
| motion | `0x60` |
| air_quality | `0x98` |

## 상태 해석 원칙

- 조명 / 콘센트
  - command `0x00`
  - payload 8byte를 각 회로 상태로 해석
  - `0xFF`는 on, `0x00`는 off
- 난방
  - HVAC 모드, 외출 모드, 목표 온도, 현재 온도, 보조 센서, 에러 코드를 분리
- 환기
  - on/off, preset 유사 값, 속도, CO2, 에러 코드를 분리
- 가스
  - 닫힘 위주 상태를 close-only valve로 표현
- 엘리베이터
  - 호출 가능 여부, 방향, 층수를 분리
- 모션
  - `motionSensor.motion`
- 공기질
  - CO2, 온도, 습도는 표준 capability로 우선 노출
  - PM/VOC는 v1에서 raw state와 문서 기준으로만 보존하고, 필요 시 후속 profile 확장

## 명령 생성 규칙

- 공통 기본 body
  - packet type bytes: `30 BC`
  - src device: `01`
  - src room: `00`
- 조명 / 콘센트
  - 같은 room의 8회로 payload를 한 번에 전송
  - 대상 index만 새 상태로 갱신하고 나머지는 registry 캐시를 사용
- 난방
  - `set_thermostat_mode`, `set_heating_setpoint` 지원
- 환기
  - `switch` + `switchLevel` 기반으로 on/off/속도 전송
- 가스
  - `close`만 허용
- 엘리베이터
  - 호출 command만 지원

## Confirmation / Retry

- 송신 전 idle gap을 확보한다.
- 기본 생성 명령은 전송 후 예상 상태와 일치하는 후속 프레임을 기다린다.
- `commandOverrides`로 `packetHex`를 직접 지정한 경우에는 matcher 없이 전송되며, `timeoutMs`가 없으면 확인 대기 없이 완료 처리된다.
- 기본 재시도 횟수는 3회, 재시도 간격은 150ms, 확인 타임아웃은 1초를 사용한다.
- 가스와 온도 설정은 더 긴 확인 시간을 허용한다.

## Override 형식

### `deviceCodeOverrides`

예:

```json
{
  "light": "0x0E",
  "ventilation": 72
}
```

- key는 내부 device type 이름
- value는 10진수 또는 hex 문자열

### `commandOverrides`

예:

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

- 상위 key는 device type 또는 child key
- action key는 SmartThings command에서 사용하는 내부 action 이름
- `packetHex`가 있으면 기본 생성 packet 대신 사용
- `timeoutMs`가 있으면 기본 확인 시간을 덮어쓴다.

## 특수 기능 원칙

- 공동현관문 / 현관문 / 초인종은 기본적으로 frame capture와 override 기반으로 지원한다.
- 실측 캡처가 누적되면 preset에 편입한다.
