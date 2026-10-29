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

    test('WATER:拆出 25-bit 水量與刻度', () {
      // fill25 = 0x0800000 (2^23,約 25 %),level 6 -> value = (6 << 25) | 0x0800000
      // = 0x0C800000 -> LE bytes 00 00 80 0C;timestamp 16
      final p = CupProtocol.decodeData(
          [0x02, 0x00, 0x00, 0x80, 0x0C, 0x10, 0x00, 0x00, 0x00]) as WaterPacket;
      expect(p.fill25, 0x0800000);
      expect(p.fillPercent, closeTo(25.0, 0.0001));
      expect(p.level, 6);
      expect(p.timestamp, 16);
    });

    test('WATER:空杯與滿杯', () {
      final empty = CupProtocol.decodeData(
          [0x02, 0x00, 0x00, 0x00, 0x00, 0, 0, 0, 0]) as WaterPacket;
      expect(empty.fill25, 0);
      expect(empty.fillPercent, 0);
      expect(empty.level, 0);
      // fill25 = 0x1FFFFFF, level 10 -> value = (10 << 25) | 0x1FFFFFF = 0x15FFFFFF
      final full = CupProtocol.decodeData(
          [0x02, 0xFF, 0xFF, 0xFF, 0x15, 0, 0, 0, 0]) as WaterPacket;
      expect(full.fill25, WaterPacket.fill25Max);
      expect(full.fillPercent, 100.0);
      expect(full.level, 10);
    });

    test('WATER:一個 fill25 單位的差異可被解析', () {
      final a = CupProtocol.decodeData(
          [0x02, 0x01, 0x00, 0x00, 0x00, 0, 0, 0, 0]) as WaterPacket;
      final b = CupProtocol.decodeData(
          [0x02, 0x02, 0x00, 0x00, 0x00, 0, 0, 0, 0]) as WaterPacket;
      expect(a.fill25, 1);
      expect(b.fill25, 2);
      expect(b.fillPercent, greaterThan(a.fillPercent));
    });

    test('WATER:level 超過 10 被夾住,保留位元不影響水量', () {
      // level bits = 0xF, reserved bits set, fill25 = 0
      final p = CupProtocol.decodeData(
          [0x02, 0x00, 0x00, 0x00, 0xFE, 0, 0, 0, 0]) as WaterPacket;
      expect(p.fill25, 0);
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

  group('掃描結果辨識', () {
    test('有 Service UUID 即為智慧水杯', () {
      expect(CupGatt.isSmartCup(hasService: true, name: ''), isTrue);
    });
    test('沒有 Service UUID 但名稱為 SmartCup- 開頭也算', () {
      expect(CupGatt.isSmartCup(hasService: false, name: 'SmartCup-5626'),
          isTrue);
    });
    test('兩者皆無則不是', () {
      expect(CupGatt.isSmartCup(hasService: false, name: 'MyPhone'), isFalse);
      expect(CupGatt.isSmartCup(hasService: false, name: ''), isFalse);
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
