# 특수 기능 현황

## 기본 원칙

- 특수 기능은 표준 장치보다 실측 의존도가 높다.
- v1에서는 문서화된 capture 경로와 override 지점을 먼저 제공한다.
- 실측이 축적되면 preset으로 승격한다.

## 공동현관문 / 현관문

- 기본 표현
  - `momentary`
  - 상태 프레임이 확인되면 `contactSensor`를 같이 사용할 수 있다.
- 현재 상태
  - capture 기반 지원
  - 내장 preset은 아직 없음
- 구현 방법
  - `captureSpecialFrames` 활성화
  - 버튼 동작 시 프레임을 수집
  - `commandOverrides`에 raw packet을 우선 등록

## 초인종

- 기본 표현
  - `button`
- 현재 상태
  - capture 기반 지원
  - 내장 preset은 아직 없음
- 구현 방법
  - 벨 이벤트 발생 시 반복 패턴을 수집
  - bell frame이 확인되면 child 생성 또는 event emission 활성화

## 엘리베이터

- 기본 표현
  - `momentary`
  - custom capability `kocomcommunity.elevatorDirection`
  - custom capability `kocomcommunity.elevatorFloor`
- 현재 상태
  - Home Assistant 레퍼런스 기반 기본 해석 포함
- 주의점
  - 호출 스위치가 있는 세대만 안정적으로 학습될 수 있다.

## 가스

- 기본 표현
  - custom capability `kocomcommunity.closeOnlyValve`
- 현재 상태
  - close-only 동작이 기본
- 주의점
  - 실질적으로 닫힘 명령만 제공한다.
  - 앱 UI에서 open 동작을 노출하지 않도록 custom capability를 유지한다.

## 캡처 절차

1. 부모 device에서 `captureSpecialFrames`를 켠다.
2. 실제 월패드에서 대상 기능을 조작한다.
3. hub logs에서 raw frame과 child key 후보를 확인한다.
4. `docs/protocol.md`와 이 문서에 결과를 기록한다.
5. 필요 시 `commandOverrides` 또는 preset을 추가한다.
