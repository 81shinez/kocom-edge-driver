local constants = {}

constants.DRIVER_NAME = "kocom_wallpad"
constants.DEFAULT_PORT = 8899

constants.PACKET_PREFIX = string.char(0xAA, 0x55)
constants.PACKET_SUFFIX = string.char(0x0D, 0x0D)
constants.PACKET_LEN = 21

constants.CONNECT_TIMEOUT = 5
constants.READ_SIZE = 1024
constants.IDLE_GAP_SEC = 0.20
constants.RECV_TIMEOUT = 0.10
constants.SEND_RETRY_MAX = 3
constants.SEND_RETRY_GAP_SEC = 0.15
constants.CONFIRM_TIMEOUT_SEC = 1.0
constants.RECONNECT_MIN_SEC = 1.0
constants.RECONNECT_MAX_SEC = 30.0
constants.MONITOR_INTERVAL_SEC = 120

constants.PARENT_PROFILE = "gateway"

constants.CAPABILITIES = {
  elevator_direction = "kocomcommunity.elevatorDirection",
  elevator_floor = "kocomcommunity.elevatorFloor",
  close_only_valve = "kocomcommunity.closeOnlyValve",
}

constants.FIELDS = {
  parent_config = "parent_config",
  parent_key = "parent_key",
  init_started = "init_started",
  child_key = "child_key",
  child_device_type = "child_device_type",
  last_update = "last_update",
  last_packet = "last_packet",
  last_error = "last_error",
}

constants.DEVICE_TYPES = {
  light = "light",
  outlet = "outlet",
  thermostat = "thermostat",
  air_conditioner = "air_conditioner",
  ventilation = "ventilation",
  gas = "gas",
  elevator = "elevator",
  motion = "motion",
  air_quality = "air_quality",
  door = "door",
  doorbell = "doorbell",
}

constants.SUB_TYPES = {
  none = "none",
  direction = "direction",
  floor = "floor",
  errcode = "errcode",
}

constants.PROFILES = {
  gateway = "gateway",
  light = "light",
  outlet = "outlet",
  thermostat = "thermostat",
  ventilation = "ventilation",
  air_quality = "air-quality",
  motion = "motion",
  door = "door-pulse",
  doorbell = "doorbell",
  elevator = "elevator",
  gas = "gas-close-only",
}

constants.DEVICE_CODE_DEFAULTS = {
  light = 0x0E,
  outlet = 0x3B,
  thermostat = 0x36,
  air_conditioner = 0x39,
  ventilation = 0x48,
  gas = 0x2C,
  elevator = 0x44,
  motion = 0x60,
  air_quality = 0x98,
}

constants.LABELS = {
  light = "조명",
  outlet = "콘센트",
  thermostat = "난방",
  air_conditioner = "에어컨",
  ventilation = "환기",
  gas = "가스밸브",
  elevator = "엘리베이터",
  motion = "모션",
  air_quality = "공기질",
  door = "문 제어",
  doorbell = "초인종",
}

constants.VENT_LEVELS = {
  [0] = 0x00,
  [33] = 0x40,
  [66] = 0x80,
  [100] = 0xC0,
}

return constants
