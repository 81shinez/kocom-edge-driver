# 코드 컨벤션

## SmartThingsCommunity 스타일

- 패키지 루트는 `config.yml`, `profiles/`, `src/`로 단순하게 유지한다.
- `src/init.lua`는 Driver template을 조립하는 얇은 엔트리 포인트로 둔다.
- 큰 로직은 `command_handlers.lua`, `discovery.lua`, `lifecycle_handlers.lua`처럼 역할별 파일로 나눈다.
- 테스트는 `src/test/` 아래에 둔다.

## Lua 스타일

- `local module = {}` 패턴을 사용한다.
- 공개 함수는 파일 마지막 `return module`로 내보낸다.
- 상수성 값은 `constants.lua` 또는 모듈 상단 `local` 값으로 유지한다.
- 불필요한 전역 사용을 금지한다.
- 코드가 자명하지 않은 곳에만 짧은 주석을 둔다.

## 로깅

- 사용자에게 중요한 연결 변화는 `info_with({ hub_logs = true }, ...)`
- noisy packet dump는 `debug`
- 무효 설정이나 알 수 없는 frame은 `warn`
- session 중단이나 예외는 `error`

## 장치 상태 저장

- SmartThings `device:set_field(..., { persist = true })`는 부모의 연결 설정, child key 메타, 디버그 플래그 같은 값에 사용한다.
- 빈번히 바뀌는 runtime 상태는 session/registry 메모리에서 관리한다.

## 네트워크 / 동시성

- `cosock.socket`만 사용한다.
- 부모별 session이 연결과 command queue를 독립적으로 관리한다.
- child command는 직접 소켓을 열지 않고 항상 부모 session에 위임한다.

## 프로필 규칙

- profile 파일명은 사람이 읽기 쉬운 이름을 사용한다.
- custom capability는 최소한으로 유지한다.
- 배포 전에는 custom capability namespace가 현재 SmartThings 계정 namespace와 일치하는지 확인한다.
- profile이 바뀌면 관련 문서와 테스트를 같이 수정한다.

## 문서화 원칙

- 이 저장소는 living docs 저장소다.
- 코드 구조가 바뀌면 같은 커밋 범위 안에서 문서도 같이 바뀌어야 한다.
- 구현이 아직 불완전한 기능은 숨기지 말고 문서에 현재 상태를 명시한다.
