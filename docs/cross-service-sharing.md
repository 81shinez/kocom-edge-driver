# 외부 서비스 공유 (Apple Home 등)

이 문서는 코콤 월패드 Edge 드라이버에서 SmartThings 등록 디바이스를 외부 서비스와 최대한 공유하기 위한 현재 구현과 제약을 정리한다.

## 현재 드라이버 반영 사항

- `elevator` child profile에 표준 `switch`를 추가했다.
  - `switch.on`은 엘리베이터 호출(`push`)로 매핑된다.
  - `switch.off`는 추가 호출을 보내지 않고 상태만 재조회한다.
- `gas-close-only` child profile에 표준 `valve`를 추가했다.
  - `close`는 정상 지원한다.
  - `open`은 안전 정책상 거부하고 상태만 재조회한다.
  - 코콤 프레임에서 `closed`가 아닌 상태(`unknown`)는 외부 연동용으로 `valve.open`에 미러링한다.

## 플랫폼 제약

- SmartThings 공식 안내의 외부 서비스 공유는 Matter Multi-Admin 기준(온보딩된 Matter 디바이스)으로 설명된다.
- Apple Home은 Matter 페어링 키를 iCloud Keychain에 저장하고, 지원되는 Matter 액세서리 타입 중심으로 노출된다.
- SmartThings custom capability는 외부 생태계에서 직접 소비되지 않으므로, 외부 공유는 표준 capability 기준으로 동작한다.

## 코콤 기능 공유 관점 매핑

- 공유 호환성이 높은 항목
  - 조명, 콘센트, 온도조절, 모션, 접점성 상태, 온습도/CO2
- 부분 호환 항목
  - 환기(표준 `switch`/`switchLevel`), 가스(close-only 안전 제약), 엘리베이터 호출(`switch` 펄스 모델)
- SmartThings 전용 상세 항목
  - 엘리베이터 방향/층(custom capability), 가스 close-only custom 의미

## 참고 자료

### SmartThings 공식 문서

- SmartThings x Matter Integration (Multi-Admin 공유 절차):  
  <https://support.smartthings.com/hc/en-us/articles/11219700390804-SmartThings-x-Matter-Integration>
- SmartThings Custom Capabilities 문서:  
  <https://developer.smartthings.com/docs/devices/capabilities/custom-capabilities/>
- SmartThings Matter 지원 디바이스 타입:  
  <https://partners.smartthings.com/matter>

### Apple 공식 문서

- Apple Home에서 Matter 액세서리 추가 (iCloud Keychain 요구사항 포함):  
  <https://support.apple.com/en-us/HT213441>

### 공개 Edge Driver 소스

- `matter-switch` 프로필 예시 (`switch`, `water-valve`, `fan`):  
  <https://raw.githubusercontent.com/SmartThingsCommunity/SmartThingsEdgeDrivers/main/drivers/SmartThings/matter-switch/profiles/switch-binary.yml>  
  <https://raw.githubusercontent.com/SmartThingsCommunity/SmartThingsEdgeDrivers/main/drivers/SmartThings/matter-switch/profiles/water-valve.yml>  
  <https://raw.githubusercontent.com/SmartThingsCommunity/SmartThingsEdgeDrivers/main/drivers/SmartThings/matter-switch/profiles/fan-modular.yml>
- `matter-thermostat` 난방 전용 프로필 예시:  
  <https://raw.githubusercontent.com/SmartThingsCommunity/SmartThingsEdgeDrivers/main/drivers/SmartThings/matter-thermostat/profiles/thermostat-heating-only-nostate-nobattery.yml>
- `matter-sensor` 접점/모션 프로필 예시:  
  <https://raw.githubusercontent.com/SmartThingsCommunity/SmartThingsEdgeDrivers/main/drivers/SmartThings/matter-sensor/profiles/contact.yml>  
  <https://raw.githubusercontent.com/SmartThingsCommunity/SmartThingsEdgeDrivers/main/drivers/SmartThings/matter-sensor/profiles/motion.yml>
