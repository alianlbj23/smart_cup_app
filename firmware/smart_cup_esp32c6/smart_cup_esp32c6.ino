/*
 * 智慧水杯 ESP32-C6 BLE Peripheral — 連線骨架(規格書 v1.0)
 *
 * 建置環境(Arduino IDE / arduino-cli):
 *   - Board package:esp32 by Espressif Systems >= 3.0(支援 ESP32-C6)
 *   - Board:ESP32C6 Dev Module
 *   - Library:NimBLE-Arduino by h2zero >= 2.1
 *
 * 本階段功能:
 *   - 廣播 Service UUID,供 App 過濾掃描
 *   - Time Sync / ACK 寫入處理
 *   - 每 5 秒推送遞增的 dummy Data Notify
 *   - Device Status 可 Read/Notify(暫定格式)
 *   - 斷線後自動重新廣播
 *
 * UUID 必須與 App 端 lib/ble/ble_uuids.dart 一致。
 */

#include <NimBLEDevice.h>
#include <sys/time.h>
#include <time.h>

// ---------------------------------------------------------------- GATT Profile
#define SERVICE_UUID        "3c8b0001-efc1-4061-946c-e5916790df93"
#define TIME_SYNC_UUID      "3c8b0002-efc1-4061-946c-e5916790df93"
#define DATA_NOTIFY_UUID    "3c8b0003-efc1-4061-946c-e5916790df93"
#define ACK_UUID            "3c8b0004-efc1-4061-946c-e5916790df93"
#define DEVICE_STATUS_UUID  "3c8b0005-efc1-4061-946c-e5916790df93"

// 廣播封包:flags(3) + 128-bit UUID(18) = 21 bytes,名稱放 scan response。
static const char *DEVICE_NAME = "SmartCup";

// ---------------------------------------------------------------- Payload
static const uint8_t MSG_TYPE_DUMMY = 0x01;
static const uint8_t ACK_RECEIVED_OK = 0x01;
static const size_t DATA_PACKET_LEN = 9;

// Device Status 暫定格式:Byte 0 電量 %,Byte 1-3 韌體版本 major/minor/patch。
static const uint8_t FW_MAJOR = 0;
static const uint8_t FW_MINOR = 1;
static const uint8_t FW_PATCH = 0;

static const uint32_t DATA_INTERVAL_MS = 5000;

// ---------------------------------------------------------------- State
static NimBLEServer *server = nullptr;
static NimBLECharacteristic *dataChar = nullptr;
static NimBLECharacteristic *statusChar = nullptr;

static uint32_t dummyValue = 0;
static uint32_t lastSendMs = 0;
static bool timeSynced = false;

static void putU32LE(uint8_t *p, uint32_t v) {
  p[0] = v & 0xFF;
  p[1] = (v >> 8) & 0xFF;
  p[2] = (v >> 16) & 0xFF;
  p[3] = (v >> 24) & 0xFF;
}

static uint32_t getU32LE(const uint8_t *p) {
  return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) |
         ((uint32_t)p[3] << 24);
}

static uint8_t readBatteryPercent() {
  // TODO: 接上實際電量量測。
  return 100;
}

static void updateDeviceStatus(bool notify) {
  uint8_t buf[4] = {readBatteryPercent(), FW_MAJOR, FW_MINOR, FW_PATCH};
  statusChar->setValue(buf, sizeof(buf));
  if (notify) statusChar->notify();
}

// ---------------------------------------------------------------- Callbacks
class ServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer *s, NimBLEConnInfo &info) override {
    Serial.printf("[BLE] connected: %s\n", info.getAddress().toString().c_str());
  }

  void onDisconnect(NimBLEServer *s, NimBLEConnInfo &info, int reason) override {
    // advertiseOnDisconnect(true) 會自動重新廣播。
    Serial.printf("[BLE] disconnected, reason=0x%X\n", reason);
  }

  void onMTUChange(uint16_t mtu, NimBLEConnInfo &info) override {
    Serial.printf("[BLE] MTU=%u\n", mtu);
  }
};

class TimeSyncCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic *c, NimBLEConnInfo &info) override {
    NimBLEAttValue v = c->getValue();
    if (v.length() != 4) {
      Serial.printf("[TimeSync] invalid length %u\n", v.length());
      return;
    }
    uint32_t ts = getU32LE(v.data());
    timeval tv = {.tv_sec = (time_t)ts, .tv_usec = 0};
    settimeofday(&tv, nullptr);
    timeSynced = true;
    Serial.printf("[TimeSync] unix=%lu\n", (unsigned long)ts);
  }
};

class AckCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic *c, NimBLEConnInfo &info) override {
    NimBLEAttValue v = c->getValue();
    if (v.length() < 1) return;
    if (v.data()[0] == ACK_RECEIVED_OK) {
      Serial.println("[ACK] data received OK");
    } else {
      Serial.printf("[ACK] unknown type 0x%02X\n", v.data()[0]);
    }
    // TODO: 傳輸失敗重傳/離線緩衝機制(依 ACK 決定是否重送)。
  }
};

class SubscribeLogger : public NimBLECharacteristicCallbacks {
  void onSubscribe(NimBLECharacteristic *c, NimBLEConnInfo &info,
                   uint16_t subValue) override {
    Serial.printf("[BLE] %s subscribe=%u\n", c->getUUID().toString().c_str(),
                  subValue);
  }
};

static ServerCallbacks serverCallbacks;
static TimeSyncCallbacks timeSyncCallbacks;
static AckCallbacks ackCallbacks;
static SubscribeLogger subscribeLogger;

// ---------------------------------------------------------------- Setup
static void setupBle() {
  NimBLEDevice::init(DEVICE_NAME);

  server = NimBLEDevice::createServer();
  server->setCallbacks(&serverCallbacks);
  server->advertiseOnDisconnect(true);

  NimBLEService *service = server->createService(SERVICE_UUID);

  service->createCharacteristic(TIME_SYNC_UUID, NIMBLE_PROPERTY::WRITE)
      ->setCallbacks(&timeSyncCallbacks);

  dataChar = service->createCharacteristic(DATA_NOTIFY_UUID, NIMBLE_PROPERTY::NOTIFY);
  dataChar->setCallbacks(&subscribeLogger);

  service->createCharacteristic(ACK_UUID, NIMBLE_PROPERTY::WRITE)
      ->setCallbacks(&ackCallbacks);

  statusChar = service->createCharacteristic(
      DEVICE_STATUS_UUID, NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);
  statusChar->setCallbacks(&subscribeLogger);
  updateDeviceStatus(false);

  service->start();

  NimBLEAdvertisementData advData;
  advData.setFlags(BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP);
  advData.addServiceUUID(NimBLEUUID(SERVICE_UUID));

  NimBLEAdvertisementData scanData;
  scanData.setName(DEVICE_NAME);

  NimBLEAdvertising *adv = NimBLEDevice::getAdvertising();
  adv->setAdvertisementData(advData);
  adv->setScanResponseData(scanData);
  adv->start();

  Serial.printf("[BLE] advertising as %s (%s)\n", DEVICE_NAME,
                NimBLEDevice::getAddress().toString().c_str());
}

void setup() {
  Serial.begin(115200);
  delay(200);
  Serial.println("SmartCup firmware v0.1.0 (BLE connection skeleton)");

  // TODO: wake-up logic
  //   本階段不進入 Light/Deep Sleep,保持開機以利連線測試。
  //   後續在此判斷喚醒來源(esp_sleep_get_wakeup_cause)並決定是否廣播/推送。

  setupBle();
}

// ---------------------------------------------------------------- Loop
static void sendDummyData() {
  // TODO: 以真實感測器(重量/IMU)資料取代 dummy value,並定義新的 message type。
  uint8_t buf[DATA_PACKET_LEN];
  buf[0] = MSG_TYPE_DUMMY;
  putU32LE(&buf[1], ++dummyValue);
  // TimeSync 前 time() 為開機後秒數。
  putU32LE(&buf[5], (uint32_t)time(nullptr));

  dataChar->setValue(buf, sizeof(buf));
  dataChar->notify();
  Serial.printf("[Data] value=%lu ts=%lu synced=%d\n", (unsigned long)dummyValue,
                (unsigned long)time(nullptr), timeSynced);
}

void loop() {
  uint32_t now = millis();
  if (now - lastSendMs >= DATA_INTERVAL_MS) {
    lastSendMs = now;
    if (server->getConnectedCount() > 0) {
      sendDummyData();
    }
  }

  // TODO: wake-up logic
  //   資料送完且收到 ACK 後,於此決定是否進入 Light/Deep Sleep。

  delay(10);
}
