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

    group('ATTITUDE', () {
      // value = (roll << 16) | (pitch & 0xFFFF),皆為 int16 little-endian。
      List<int> attitude(int pitch, int roll, [int ts = 7]) => [
            0x05,
            pitch & 0xFF, (pitch >> 8) & 0xFF,
            roll & 0xFF, (roll >> 8) & 0xFF,
            ts, 0, 0, 0,
          ];

      test('正值 pitch / roll 與時間戳', () {
        final p = CupProtocol.decodeData(attitude(123, 456)) as AttitudePacket;
        expect(p.pitchDeciDegrees, 123);
        expect(p.rollDeciDegrees, 456);
        expect(p.pitchDegrees, closeTo(12.3, 1e-9));
        expect(p.rollDegrees, closeTo(45.6, 1e-9));
        expect(p.timestamp, 7);
      });

      test('負值做 int16 符號延伸', () {
        // pitch -15 = 0xFFF1,roll -300 = 0xFED4
        final p = CupProtocol.decodeData(
            [0x05, 0xF1, 0xFF, 0xD4, 0xFE, 0, 0, 0, 0]) as AttitudePacket;
        expect(p.pitchDeciDegrees, -15);
        expect(p.rollDeciDegrees, -300);
        expect(p.rollDegrees, closeTo(-30.0, 1e-9));
      });

      test('邊界 ±1800,超出範圍被夾住', () {
        final edge =
            CupProtocol.decodeData(attitude(1800, -1800)) as AttitudePacket;
        expect(edge.pitchDeciDegrees, 1800);
        expect(edge.rollDeciDegrees, -1800);
        final over =
            CupProtocol.decodeData(attitude(0x7FFF, -0x8000)) as AttitudePacket;
        expect(over.pitchDeciDegrees, 1800);
        expect(over.rollDeciDegrees, -1800);
      });

      test('pitch 與 roll 互不干擾(-1 / 0)', () {
        final p = CupProtocol.decodeData(attitude(-1, 0)) as AttitudePacket;
        expect(p.pitchDeciDegrees, -1);
        expect(p.rollDeciDegrees, 0);
        final q = CupProtocol.decodeData(attitude(0, -1)) as AttitudePacket;
        expect(q.pitchDeciDegrees, 0);
        expect(q.rollDeciDegrees, -1);
      });

      test('總傾斜角 tilt = acos(cos(pitch)·cos(roll))', () {
        AttitudePacket a(int pitch, int roll) => AttitudePacket(
            pitchDeciDegrees: pitch, rollDeciDegrees: roll, timestamp: 0);
        expect(a(0, 0).tiltDegrees, closeTo(0, 1e-9));
        expect(a(0, -300).tiltDegrees, closeTo(30, 1e-9));
        expect(a(450, 0).tiltDegrees, closeTo(45, 1e-9));
        // cos60·cos60 = 0.25 -> acos(0.25) ≈ 75.52°
        expect(a(600, 600).tiltDegrees, closeTo(75.5225, 1e-3));
        expect(a(1800, 0).tiltDegrees, closeTo(180, 1e-9));
        expect(a(1800, 1800).tiltDegrees, closeTo(0, 1e-6));
        expect(a(-900, 0).tiltDegrees, closeTo(90, 1e-9));
      });
    });

    group('STATE', () {
      // value = (secondsInState << 8) | state,uint32 little-endian。
      List<int> state(int code, int seconds, [int ts = 9]) {
        final v = ((seconds & 0xFFFFFF) << 8) | (code & 0xFF);
        return [
          0x06,
          v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF,
          ts, 0, 0, 0,
        ];
      }

      test('0 = 活動中、1 = 休眠中,並帶秒數與時間戳', () {
        final active = CupProtocol.decodeData(state(0, 0)) as StatePacket;
        expect(active.activity, CupActivity.active);
        expect(active.secondsInState, 0);
        expect(active.timestamp, 9);

        final dozing = CupProtocol.decodeData(state(1, 75)) as StatePacket;
        expect(dozing.activity, CupActivity.dozing);
        expect(dozing.secondsInState, 75);
      });

      test('其他狀態值視為未知,秒數照樣解出', () {
        for (final code in [2, 0x7F, 0xFF]) {
          final p = CupProtocol.decodeData(state(code, 10)) as StatePacket;
          expect(p.activity, CupActivity.unknown, reason: 'code $code');
          expect(p.secondsInState, 10);
        }
      });

      test('秒數 24-bit 邊界:最大值不溢位、不影響狀態位元', () {
        final max = CupProtocol.decodeData(
            [0x06, 0x01, 0xFF, 0xFF, 0xFF, 0, 0, 0, 0]) as StatePacket;
        expect(max.activity, CupActivity.dozing);
        expect(max.secondsInState, StatePacket.maxSecondsInState);
        expect(max.secondsInState, 0xFFFFFF);

        // 只有 bit 8 = 1 秒;bits 7..0 = 0 仍是活動中。
        final one = CupProtocol.decodeData(
            [0x06, 0x00, 0x01, 0x00, 0x00, 0, 0, 0, 0]) as StatePacket;
        expect(one.activity, CupActivity.active);
        expect(one.secondsInState, 1);

        // 只有最高位元(bit 31)= 2^23 秒。
        final top = CupProtocol.decodeData(
            [0x06, 0x00, 0x00, 0x00, 0x80, 0, 0, 0, 0]) as StatePacket;
        expect(top.secondsInState, 0x800000);
        expect(top.activity, CupActivity.active);
      });

      test('中文標籤', () {
        expect(CupActivity.active.label, '活動中');
        expect(CupActivity.dozing.label, '休眠中');
        expect(CupActivity.unknown.label, '未知');
      });
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
    expect(s.batteryKnown, isTrue);
    expect(CupProtocol.decodeDeviceStatus([0, 0, 0, 0]).batteryPercent, 0);
    expect(CupProtocol.decodeDeviceStatus([100, 0, 0, 0]).batteryPercent, 100);
    expect(() => CupProtocol.decodeDeviceStatus([1, 2]),
        throwsFormatException);
  });

  test('Device Status:電量 0xFF 代表未知', () {
    final s = CupProtocol.decodeDeviceStatus([0xFF, 0, 1, 2]);
    expect(s.batteryPercent, isNull);
    expect(s.batteryKnown, isFalse);
    // 其他超出 0..100 的值同樣視為未知。
    expect(
        CupProtocol.decodeDeviceStatus([200, 0, 0, 0]).batteryKnown, isFalse);
  });
}
