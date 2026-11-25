import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:stut_food_intake_project/services/ble_service.dart';
import 'package:stut_food_intake_project/services/cup_protocol.dart';

/// 組出一筆 0x07 封包(韌體 README 第 5 節的 bit 配置)。
List<int> drinkEventBytes({
  required int a,
  required int b,
  int kind = 0,
  bool sawDrinking = false,
  bool tooLong = false,
  bool timeUnknown = false,
  int seq = 0,
  int timestamp = 0,
}) {
  final value = (a & 0xFF) |
      ((b & 0xFF) << 8) |
      ((kind & 0x3) << 16) |
      ((sawDrinking ? 1 : 0) << 18) |
      ((tooLong ? 1 : 0) << 19) |
      ((timeUnknown ? 1 : 0) << 20) |
      ((seq & 0x7FF) << 21);
  final bytes = ByteData(9)
    ..setUint8(0, 0x07)
    ..setUint32(1, value, Endian.little)
    ..setUint32(5, timestamp, Endian.little);
  return bytes.buffer.asUint8List();
}

void main() {
  group('DRINK_EVENT (0x07)', () {
    test('解析 A、B(單位 0.5%)、種類、旗標、seq 與時間戳', () {
      // 韌體序列埠的例子:喝水 62.0% → 55.5%,seq 12,有飲用姿態。
      final p = CupProtocol.decodeData(drinkEventBytes(
        a: 124,
        b: 111,
        kind: 0,
        sawDrinking: true,
        seq: 12,
        timestamp: 1795600000,
      )) as DrinkEventPacket;
      expect(p.beforeHalfPercent, 124);
      expect(p.afterHalfPercent, 111);
      expect(p.beforePercent, 62.0);
      expect(p.afterPercent, 55.5);
      expect(p.kind, FirmwareEventKind.drink);
      expect(p.sawDrinking, isTrue);
      expect(p.tooLong, isFalse);
      expect(p.timeUnknown, isFalse);
      expect(p.seq, 12);
      expect(p.timestamp, 1795600000);
    });

    test('每個旗標各佔一個 bit,互不影響', () {
      DrinkEventPacket d({
        bool saw = false,
        bool long = false,
        bool unknown = false,
      }) =>
          CupProtocol.decodeData(drinkEventBytes(
            a: 100,
            b: 90,
            sawDrinking: saw,
            tooLong: long,
            timeUnknown: unknown,
          )) as DrinkEventPacket;

      final saw = d(saw: true);
      expect((saw.sawDrinking, saw.tooLong, saw.timeUnknown),
          (true, false, false));
      final long = d(long: true);
      expect((long.sawDrinking, long.tooLong, long.timeUnknown),
          (false, true, false));
      final unknown = d(unknown: true);
      expect((unknown.sawDrinking, unknown.tooLong, unknown.timeUnknown),
          (false, false, true));
    });

    test('種類:0 喝水、1 加水,其他保留值為 unknown', () {
      FirmwareEventKind kind(int code) => (CupProtocol.decodeData(
              drinkEventBytes(a: 10, b: 20, kind: code)) as DrinkEventPacket)
          .kind;
      expect(kind(0), FirmwareEventKind.drink);
      expect(kind(1), FirmwareEventKind.refill);
      expect(kind(2), FirmwareEventKind.unknown);
      expect(kind(3), FirmwareEventKind.unknown);
    });

    test('seq 為 11 bits:最大值 2047,最高位不會變成負數', () {
      final p = CupProtocol.decodeData(drinkEventBytes(
        a: 200,
        b: 0,
        kind: 1,
        sawDrinking: true,
        tooLong: true,
        timeUnknown: true,
        seq: 2047,
      )) as DrinkEventPacket;
      expect(p.seq, 2047);
      expect(p.kind, FirmwareEventKind.refill);
      expect(p.beforeHalfPercent, 200);
      expect(p.afterHalfPercent, 0);
      expect(p.timeUnknown, isTrue);
      expect(p.timestamp, 0);
    });

    test('A、B 超過 200(100%)時夾在 200', () {
      final p = CupProtocol.decodeData(drinkEventBytes(a: 255, b: 201))
          as DrinkEventPacket;
      expect(p.beforeHalfPercent, 200);
      expect(p.afterHalfPercent, 200);
    });

    test('去重鍵 = seq + 時間戳 + A/B', () {
      DrinkEventPacket d({int a = 124, int b = 111, int seq = 12, int ts = 5}) =>
          CupProtocol.decodeData(
                  drinkEventBytes(a: a, b: b, seq: seq, timestamp: ts))
              as DrinkEventPacket;
      expect(d().dedupKey, d().dedupKey);
      expect(d().dedupKey, isNot(d(seq: 13).dedupKey));
      expect(d().dedupKey, isNot(d(ts: 6).dedupKey));
      expect(d().dedupKey, isNot(d(a: 125).dedupKey));
      expect(d().dedupKey, isNot(d(b: 110).dedupKey));
    });

    test('ACK 為 3 bytes:[0x07, seq 低 8 bits, seq 高 3 bits]', () {
      expect(CupProtocol.encodeDrinkEventAck(12), [0x07, 12, 0]);
      expect(CupProtocol.encodeDrinkEventAck(0x1FF), [0x07, 0xFF, 0x01]);
      expect(CupProtocol.encodeDrinkEventAck(2047), [0x07, 0xFF, 0x07]);
      // 超出 11 bits 的部分捨去。
      expect(CupProtocol.encodeDrinkEventAck(0x0FFF), [0x07, 0xFF, 0x07]);
    });
  });

  group('Device Status:韌體版本與 BLE 位址', () {
    test('4 bytes(舊韌體):解析版本,沒有 BLE 位址', () {
      final s = CupProtocol.decodeDeviceStatus([87, 0, 3, 0]);
      expect(s.batteryPercent, 87);
      expect(s.firmwareVersion, const FirmwareVersion(0, 3, 0));
      expect(s.firmwareVersion.toString(), '0.3.0');
      expect(s.bleAddress, isNull);
    });

    test('長度 ≥ 10(韌體 0.4.0):6 bytes 位址,顯示順序、大寫、冒號分隔', () {
      final s = CupProtocol.decodeDeviceStatus(
          [76, 0, 4, 0, 0x58, 0xE6, 0xC5, 0x12, 0xE0, 0xCE]);
      expect(s.firmwareVersion, const FirmwareVersion(0, 4, 0));
      expect(s.bleAddress, '58:E6:C5:12:E0:CE');
      // 之後再加長也只看前 10 bytes。
      expect(
          CupProtocol.decodeDeviceStatus(
              [76, 0, 4, 0, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x99]).bleAddress,
          '0A:0B:0C:0D:0E:0F');
    });

    test('長度 5..9:位址不完整,視為沒有', () {
      expect(
          CupProtocol.decodeDeviceStatus([76, 0, 4, 0, 0x58, 0xE6, 0xC5, 0x12, 0xE0])
              .bleAddress,
          isNull);
    });

    test('位址全 0 或全 FF 視為無效', () {
      expect(
          CupProtocol.decodeDeviceStatus([76, 0, 4, 0, 0, 0, 0, 0, 0, 0]).bleAddress,
          isNull);
      expect(
          CupProtocol.decodeDeviceStatus(
              [76, 0, 4, 0, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]).bleAddress,
          isNull);
    });

    test('韌體版本比較:≥ 0.3.0 才由韌體偵測喝水', () {
      bool detects(int a, int b, int c) =>
          CupProtocol.decodeDeviceStatus([50, a, b, c]).firmwareDetectsDrinks;
      expect(detects(0, 2, 0), isFalse);
      expect(detects(0, 2, 9), isFalse);
      expect(detects(0, 3, 0), isTrue);
      expect(detects(0, 4, 0), isTrue);
      expect(detects(1, 0, 0), isTrue);
      // 沒有版本資訊(例如測試用的假狀態)→ 不當成新韌體。
      expect(const DeviceStatus(batteryPercent: 1).firmwareDetectsDrinks, isFalse);
    });
  });
}
