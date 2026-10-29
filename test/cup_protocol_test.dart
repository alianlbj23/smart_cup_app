import 'package:flutter_test/flutter_test.dart';
import 'package:stut_food_intake_project/services/ble_service.dart';
import 'package:stut_food_intake_project/services/cup_protocol.dart';

void main() {
  group('Data Notify', () {
    test('解析 9 bytes little-endian payload', () {
      final p = CupProtocol.decodeData([
        0x01,
        0x78, 0x56, 0x34, 0x12, // value = 0x12345678
        0x00, 0x2F, 0x6B, 0x68, // timestamp = 0x686B2F00
      ]) as DummyDataPacket;
      expect(p.value, 0x12345678);
      expect(p.timestamp, 0x686B2F00);
    });

    test('uint32 最大值不會變成負數', () {
      final p = CupProtocol.decodeData(
          [0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
          as DummyDataPacket;
      expect(p.value, 0xFFFFFFFF);
      expect(p.timestamp, 0xFFFFFFFF);
    });

    test('WATER:拆出水量與刻度', () {
      // value = 0x000609C4:fill 2500 (25.00 %),level 6;timestamp 16
      final p = CupProtocol.decodeData(
          [0x02, 0xC4, 0x09, 0x06, 0x00, 0x10, 0x00, 0x00, 0x00]) as WaterPacket;
      expect(p.fillPermyriad, 2500);
      expect(p.fillPercent, 25.0);
      expect(p.level, 6);
      expect(p.timestamp, 16);
    });

    test('WATER:空杯與滿杯', () {
      final empty = CupProtocol.decodeData(
          [0x02, 0x00, 0x00, 0x00, 0x00, 0, 0, 0, 0]) as WaterPacket;
      expect(empty.fillPermyriad, 0);
      expect(empty.level, 0);
      final full = CupProtocol.decodeData(
          [0x02, 0x10, 0x27, 0x0A, 0x00, 0, 0, 0, 0]) as WaterPacket;
      expect(full.fillPermyriad, 10000);
      expect(full.level, 10);
    });

    test('WATER:超出範圍的值被夾住', () {
      final p = CupProtocol.decodeData(
          [0x02, 0xFF, 0xFF, 0xFF, 0x00, 0, 0, 0, 0]) as WaterPacket;
      expect(p.fillPermyriad, 10000);
      expect(p.level, 10);
    });

    test('RAW:原始計數', () {
      final p = CupProtocol.decodeData(
          [0x03, 0x36, 0x7A, 0x04, 0x00, 0, 0, 0, 0]) as RawPacket;
      expect(p.count, 0x047A36);
    });

    test('POSE:傾斜角、姿態與移動旗標', () {
      // tilt 0x01F4 = 500 (50.0°),pose 3 drinking,moving 1
      final p = CupProtocol.decodeData(
          [0x04, 0xF4, 0x01, 0x03, 0x01, 0, 0, 0, 0]) as PosePacket;
      expect(p.tiltDeciDegrees, 500);
      expect(p.tiltDegrees, 50.0);
      expect(p.pose, CupPose.drinking);
      expect(p.moving, isTrue);
    });

    test('POSE:未定義的姿態代碼視為 unknown', () {
      final p = CupProtocol.decodeData(
          [0x04, 0x00, 0x00, 0x09, 0x00, 0, 0, 0, 0]) as PosePacket;
      expect(p.pose, CupPose.unknown);
      expect(p.moving, isFalse);
    });

    test('未知 message type 回傳 UnknownPacket 而不丟例外', () {
      final p = CupProtocol.decodeData(
          [0x7E, 0x01, 0x00, 0x00, 0x00, 0x05, 0, 0, 0]) as UnknownPacket;
      expect(p.type, 0x7E);
      expect(p.value, 1);
      expect(p.timestamp, 5);
    });

    test('長度錯誤丟出 FormatException', () {
      expect(() => CupProtocol.decodeData([0x01, 0x00]),
          throwsFormatException);
      expect(() => CupProtocol.decodeData(List.filled(10, 0)),
          throwsFormatException);
    });
  });

  test('Time Sync 編碼為 4 bytes little-endian Unix 秒數', () {
    expect(CupProtocol.encodeTimeSync(0x686B2F00), [0x00, 0x2F, 0x6B, 0x68]);
  });

  test('ACK 編碼', () {
    expect(CupProtocol.encodeAck(), [0x01]);
  });

  test('Device Status 解析', () {
    final s = CupProtocol.decodeDeviceStatus([87, 0, 1, 2]);
    expect(s.batteryPercent, 87);
    expect(() => CupProtocol.decodeDeviceStatus([1, 2]),
        throwsFormatException);
  });
}
