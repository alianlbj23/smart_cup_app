import 'package:flutter_test/flutter_test.dart';
import 'package:stut_food_intake_project/services/cup_protocol.dart';

void main() {
  group('Data Notify', () {
    test('解析 9 bytes little-endian payload', () {
      final p = CupProtocol.decodeData([
        0x01,
        0x78, 0x56, 0x34, 0x12, // value = 0x12345678
        0x00, 0x2F, 0x6B, 0x68, // timestamp = 0x686B2F00
      ]);
      expect(p.value, 0x12345678);
      expect(p.timestamp, 0x686B2F00);
    });

    test('uint32 最大值不會變成負數', () {
      final p = CupProtocol.decodeData(
          [0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]);
      expect(p.value, 0xFFFFFFFF);
      expect(p.timestamp, 0xFFFFFFFF);
    });

    test('未知 message type 丟出 FormatException', () {
      expect(() => CupProtocol.decodeData([0x02, 0, 0, 0, 0, 0, 0, 0, 0]),
          throwsFormatException);
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
    expect(s.firmwareVersion, '0.1.2');
    expect(() => CupProtocol.decodeDeviceStatus([1, 2]),
        throwsFormatException);
  });
}
