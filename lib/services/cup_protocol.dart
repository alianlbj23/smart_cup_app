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

  static const int ackReceivedOk = 0x01;

  static const int deviceStatusLength = 4;

  /// Device Status Byte 0 的特殊值:電量未知(例如沒接電池)。
  static const int batteryUnknown = 0xFF;

  /// Time Sync:Byte 0-3 = Unix Timestamp (uint32 LE)。
  static List<int> encodeTimeSync(int unixTimestamp) {
    final bytes = ByteData(4)..setUint32(0, unixTimestamp, Endian.little);
    return bytes.buffer.asUint8List();
  }

  /// ACK:Byte 0 = ACK type。
  static List<int> encodeAck([int type = ackReceivedOk]) => [type];

  /// Data Notify:type(1) + value(4) + timestamp(4) = 9 bytes。
  ///
  /// value 的位元配置依 message type 而異(韌體 smart_cup_firmware 的
  /// `main/ble_gatt_svr.h`):
  /// - 0x02 WATER   :bits 24..0 水量 25-bit 分數(0..2^25-1),bits 28..25 level 0..10
  /// - 0x03 RAW     :濾波後電容計數
  /// - 0x04 POSE    :bits 15..0 傾斜角 0.1 度,bits 23..16 姿態,bits 31..24 移動
  /// - 0x05 ATTITUDE:bits 15..0 pitch、bits 31..16 roll,皆為 int16、0.1 度
  /// - 0x06 STATE   :bits 7..0 狀態(0 活動中 / 1 休眠中),bits 31..8 進入該狀態秒數(uint24)
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
      default:
        return UnknownPacket(type: type, value: value, timestamp: timestamp);
    }
  }

  /// 16-bit 欄位轉為有號角度(0.1 度),做 int16 符號延伸並夾在 ±1800。
  static int _attitudeAngle(int bits16) => bits16
      .toSigned(16)
      .clamp(-AttitudePacket.maxDeciDegrees, AttitudePacket.maxDeciDegrees);

  /// Device Status(規格書未定義,本階段暫定格式,韌體需同步):
  /// Byte 0 = 電量 %(uint8,[batteryUnknown] 代表未知),
  /// Byte 1-3 = 裝置端版本號(App 不使用)。
  ///
  /// 0..100 以外的電量值(含 0xFF)都視為未知,不會顯示成 255% 之類的數字。
  // TODO: 正式格式確定後更新。
  static DeviceStatus decodeDeviceStatus(List<int> raw) {
    if (raw.length < deviceStatusLength) {
      throw FormatException(
        'Device Status 長度至少 $deviceStatusLength bytes,實際 ${raw.length}',
      );
    }
    final battery = raw[0] & 0xFF;
    return DeviceStatus(batteryPercent: battery <= 100 ? battery : null);
  }
}
