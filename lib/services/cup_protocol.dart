import 'dart:typed_data';

import 'ble_service.dart';

/// 智慧水杯 GATT Profile(規格書 §3)。與 BLE 套件無關,任何 [BleService] 實作共用。
///
/// 以隨機產生的 128-bit UUID 為基底,第一段後 4 碼為 characteristic 編號,
/// 韌體端(https://github.com/alianlbj23/smart_cup_firmware ,ESP-IDF,
/// `main/ble_gatt_svr.c` / `main/ble_gatt_svr.h`)必須使用相同值。
class CupGatt {
  CupGatt._();

  static const service = '3c8b0001-efc1-4061-946c-e5916790df93';

  /// 韌體廣播名稱前綴("SmartCup-" + MAC 末兩個 byte,例如 SmartCup-5626)。
  /// 部分平台(Windows、某些 Android)掃描結果裡的 Service UUID 會缺漏,
  /// 名稱是第二個辨識依據。
  static const namePrefix = 'SmartCup-';

  /// 掃描結果是否為智慧水杯:廣播了本 Service,或名稱符合 [namePrefix]。
  static bool isSmartCup({required bool hasService, required String name}) =>
      hasService || name.startsWith(namePrefix);

  /// App→ESP32,Write:Unix Timestamp。
  static const timeSync = '3c8b0002-efc1-4061-946c-e5916790df93';

  /// ESP32→App,Notify:資料推送(水量 / 原始值 / 姿態 / 即時姿態角 / 活動狀態)。
  static const dataNotify = '3c8b0003-efc1-4061-946c-e5916790df93';

  /// App→ESP32,Write:確認收到資料。
  static const ack = '3c8b0004-efc1-4061-946c-e5916790df93';

  /// 雙向,Read/Notify:電量等裝置狀態。
  static const deviceStatus = '3c8b0005-efc1-4061-946c-e5916790df93';
}

/// 規格書 §4 的 payload 編解碼。所有多位元組整數皆為 little-endian。
class CupProtocol {
  CupProtocol._();

  static const int dataPacketLength = 9;
  static const int msgTypeDummy = 0x01;
  static const int msgTypeWater = 0x02;
  static const int msgTypeRaw = 0x03;
  static const int msgTypePose = 0x04;
  static const int msgTypeAttitude = 0x05;
  static const int msgTypeState = 0x06;
  static const int msgTypeDrinkEvent = 0x07;

  static const int ackReceivedOk = 0x01;

  static const int deviceStatusLength = 4;

  /// Device Status 帶 BLE 位址時的最小長度(韌體 0.4.0:4 + 6 bytes)。
  static const int deviceStatusWithAddressLength = 10;

  /// Device Status Byte 0 的特殊值:電量未知(例如沒接電池)。
  static const int batteryUnknown = 0xFF;

  /// Time Sync:Byte 0-3 = Unix Timestamp (uint32 LE)。
  static List<int> encodeTimeSync(int unixTimestamp) {
    final bytes = ByteData(4)..setUint32(0, unixTimestamp, Endian.little);
    return bytes.buffer.asUint8List();
  }

  /// ACK:Byte 0 = ACK type。
  static List<int> encodeAck([int type = ackReceivedOk]) => [type];

  /// DRINK_EVENT 的 ACK(3 bytes):`[0x07, seq 低 8 bits, seq 高 3 bits]`。
  /// 韌體收到 seq 相符的 ACK 才把事件從 flash 刪除。
  static List<int> encodeDrinkEventAck(int seq) =>
      [msgTypeDrinkEvent, seq & 0xFF, (seq >> 8) & 0x07];

  /// Data Notify:type(1) + value(4) + timestamp(4) = 9 bytes。
  ///
  /// value 的位元配置依 message type 而異(韌體 smart_cup_firmware 的
  /// `main/ble_gatt_svr.h`):
  /// - 0x02 WATER   :bits 24..0 水量 25-bit 分數(0..2^25-1),bits 28..25 level 0..10
  /// - 0x03 RAW     :濾波後電容計數
  /// - 0x04 POSE    :bits 15..0 傾斜角 0.1 度,bits 23..16 姿態,bits 31..24 移動
  /// - 0x05 ATTITUDE:bits 15..0 pitch、bits 31..16 roll,皆為 int16、0.1 度
  /// - 0x06 STATE   :bits 7..0 狀態(0 活動中 / 1 休眠中),bits 31..8 進入該狀態秒數(uint24)
  /// - 0x07 DRINK_EVENT:bits 7..0 水位 A、bits 15..8 水位 B(單位 0.5%,0..200),
  ///   bits 17..16 種類(0 喝水 / 1 加水),bit 18 saw_drinking,bit 19 too_long,
  ///   bit 20 time_unknown,bits 31..21 seq(11 bits)。timestamp = 事件開始時間
  ///
  /// 長度不符時丟出 [FormatException];未知 type 回傳 [UnknownPacket]。
  static CupDataPacket decodeData(List<int> raw) {
    if (raw.length != dataPacketLength) {
      throw FormatException(
        'Data Notify 長度應為 $dataPacketLength bytes,實際 ${raw.length}',
      );
    }
    final bytes = ByteData.sublistView(Uint8List.fromList(raw));
    final type = bytes.getUint8(0);
    final value = bytes.getUint32(1, Endian.little);
    final timestamp = bytes.getUint32(5, Endian.little);
    switch (type) {
      case msgTypeDummy:
        return DummyDataPacket(value: value, timestamp: timestamp);
      case msgTypeWater:
        return WaterPacket(
          fill25: value & WaterPacket.fill25Max,
          level: ((value >> WaterPacket.fill25Bits) & 0x0F)
              .clamp(0, WaterPacket.maxLevel),
          timestamp: timestamp,
        );
      case msgTypeRaw:
        return RawPacket(count: value, timestamp: timestamp);
      case msgTypePose:
        return PosePacket(
          tiltDeciDegrees: (value & 0xFFFF).clamp(0, 1800),
          pose: CupPose.fromCode((value >> 16) & 0xFF),
          moving: ((value >> 24) & 0xFF) != 0,
          timestamp: timestamp,
        );
      case msgTypeAttitude:
        return AttitudePacket(
          pitchDeciDegrees: _attitudeAngle(value & 0xFFFF),
          rollDeciDegrees: _attitudeAngle((value >> 16) & 0xFFFF),
          timestamp: timestamp,
        );
      case msgTypeState:
        return StatePacket(
          activity: CupActivity.fromCode(value & 0xFF),
          secondsInState: (value >> 8) & StatePacket.maxSecondsInState,
          timestamp: timestamp,
        );
      case msgTypeDrinkEvent:
        return DrinkEventPacket(
          beforeHalfPercent:
              (value & 0xFF).clamp(0, DrinkEventPacket.maxHalfPercent),
          afterHalfPercent:
              ((value >> 8) & 0xFF).clamp(0, DrinkEventPacket.maxHalfPercent),
          kind: FirmwareEventKind.fromCode((value >> 16) & 0x03),
          sawDrinking: (value >> 18) & 1 == 1,
          tooLong: (value >> 19) & 1 == 1,
          timeUnknown: (value >> 20) & 1 == 1,
          seq: (value >> 21) & DrinkEventPacket.maxSeq,
          timestamp: timestamp,
        );
      default:
        return UnknownPacket(type: type, value: value, timestamp: timestamp);
    }
  }

  /// 16-bit 欄位轉為有號角度(0.1 度),做 int16 符號延伸並夾在 ±1800。
  static int _attitudeAngle(int bits16) => bits16
      .toSigned(16)
      .clamp(-AttitudePacket.maxDeciDegrees, AttitudePacket.maxDeciDegrees);

  /// Device Status(韌體 README 第 5 節、合約 §1.1):
  /// Byte 0 = 電量 %(uint8,[batteryUnknown] 代表未知),
  /// Byte 1-3 = 韌體版本 major、minor、patch,
  /// Byte 4-9 = 水杯的 BLE 位址(韌體 0.4.0 起;顯示順序,最高位元組在前)。
  ///
  /// 0..100 以外的電量值(含 0xFF)都視為未知,不會顯示成 255% 之類的數字。
  /// 長度不到 [deviceStatusWithAddressLength](舊韌體)時沒有 BLE 位址。
  static DeviceStatus decodeDeviceStatus(List<int> raw) {
    if (raw.length < deviceStatusLength) {
      throw FormatException(
        'Device Status 長度至少 $deviceStatusLength bytes,實際 ${raw.length}',
      );
    }
    final battery = raw[0] & 0xFF;
    return DeviceStatus(
      batteryPercent: battery <= 100 ? battery : null,
      firmwareVersion:
          FirmwareVersion(raw[1] & 0xFF, raw[2] & 0xFF, raw[3] & 0xFF),
      bleAddress: raw.length >= deviceStatusWithAddressLength
          ? _bleAddress(raw.sublist(deviceStatusLength,
              deviceStatusWithAddressLength))
          : null,
    );
  }

  /// 6 bytes → `58:E6:C5:12:E0:CE`。全 0 或全 FF(韌體沒填)視為沒有位址。
  static String? _bleAddress(List<int> bytes) {
    final b = [for (final v in bytes) v & 0xFF];
    if (b.every((v) => v == 0x00) || b.every((v) => v == 0xFF)) return null;
    return b
        .map((v) => v.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(':');
  }
}
