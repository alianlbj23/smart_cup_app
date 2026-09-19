import 'dart:typed_data';

import 'ble_service.dart';

/// 智慧水杯 GATT Profile(規格書 §3)。與 BLE 套件無關,任何 [BleService] 實作共用。
///
/// 以隨機產生的 128-bit UUID 為基底,第一段後 4 碼為 characteristic 編號,
/// 韌體端 `firmware/smart_cup_esp32c6/smart_cup_esp32c6.ino` 必須使用相同值。
class CupGatt {
  CupGatt._();

  static const service = '3c8b0001-efc1-4061-946c-e5916790df93';

  /// App→ESP32,Write:Unix Timestamp。
  static const timeSync = '3c8b0002-efc1-4061-946c-e5916790df93';

  /// ESP32→App,Notify:資料推送(目前為 dummy)。
  static const dataNotify = '3c8b0003-efc1-4061-946c-e5916790df93';

  /// App→ESP32,Write:確認收到資料。
  static const ack = '3c8b0004-efc1-4061-946c-e5916790df93';

  /// 雙向,Read/Notify:電量、韌體版本等。
  static const deviceStatus = '3c8b0005-efc1-4061-946c-e5916790df93';
}

/// 規格書 §4 的 payload 編解碼。所有多位元組整數皆為 little-endian。
class CupProtocol {
  CupProtocol._();

  static const int dataPacketLength = 9;
  static const int msgTypeDummy = 0x01;

  static const int ackReceivedOk = 0x01;

  static const int deviceStatusLength = 4;

  /// Time Sync:Byte 0-3 = Unix Timestamp (uint32 LE)。
  static List<int> encodeTimeSync(int unixTimestamp) {
    final bytes = ByteData(4)..setUint32(0, unixTimestamp, Endian.little);
    return bytes.buffer.asUint8List();
  }

  /// ACK:Byte 0 = ACK type。
  static List<int> encodeAck([int type = ackReceivedOk]) => [type];

  /// Data Notify:type(1) + value(4) + timestamp(4) = 9 bytes。
  /// 長度或 message type 不符時丟出 [FormatException]。
  static DummyDataPacket decodeData(List<int> raw) {
    if (raw.length != dataPacketLength) {
      throw FormatException(
        'Data Notify 長度應為 $dataPacketLength bytes,實際 ${raw.length}',
      );
    }
    final bytes = ByteData.sublistView(Uint8List.fromList(raw));
    final type = bytes.getUint8(0);
    if (type != msgTypeDummy) {
      // TODO: 真實感測器資料格式確定後新增 message type(規格書 §8)。
      throw FormatException('未知的 message type 0x${type.toRadixString(16)}');
    }
    return DummyDataPacket(
      value: bytes.getUint32(1, Endian.little),
      timestamp: bytes.getUint32(5, Endian.little),
    );
  }

  /// Device Status(規格書未定義,本階段暫定格式,韌體需同步):
  /// Byte 0 = 電量 %(uint8),Byte 1-3 = 韌體版本 major/minor/patch。
  // TODO: 正式格式確定後更新。
  static DeviceStatus decodeDeviceStatus(List<int> raw) {
    if (raw.length < deviceStatusLength) {
      throw FormatException(
        'Device Status 長度至少 $deviceStatusLength bytes,實際 ${raw.length}',
      );
    }
    return DeviceStatus(
      batteryPercent: raw[0],
      firmwareVersion: '${raw[1]}.${raw[2]}.${raw[3]}',
    );
  }
}
