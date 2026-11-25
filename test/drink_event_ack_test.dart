import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stut_food_intake_project/services/ble_service.dart';
import 'package:stut_food_intake_project/services/device_store.dart';
import 'package:stut_food_intake_project/state/cup_connection_manager.dart';

import 'fakes/fake_ble_service.dart';

const _cup = BleDeviceInfo(deviceId: 'AA:BB', deviceName: 'SmartCup', rssi: -50);

const _event = DrinkEventPacket(
  beforeHalfPercent: 124,
  afterHalfPercent: 111,
  kind: FirmwareEventKind.drink,
  sawDrinking: true,
  tooLong: false,
  timeUnknown: false,
  seq: 300,
  timestamp: 1795600000,
);

void main() {
  late FakeBleService ble;
  late CupConnectionManager manager;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ble = FakeBleService()..devicesInRange = [_cup];
    manager = CupConnectionManager(ble: ble, store: DeviceStore());
    await manager.connectTo(_cup);
    await pumpEventQueue();
    expect(manager.state, CupConnectionState.ready);
  });

  tearDown(() {
    manager.dispose();
    ble.dispose();
  });

  test('收到 DRINK_EVENT:計數、進接收紀錄、送給訂閱者,不回 1-byte ACK', () async {
    final got = <CupDataPacket>[];
    final sub = manager.packets.listen(got.add);
    ble.pushPacket(_event);
    await pumpEventQueue();

    expect(got, [_event]);
    expect(manager.receivedCount, 1);
    expect(manager.log.single.packet, same(_event));
    expect(manager.log.single.acked, isFalse);
    expect(ble.ackCount, 0, reason: '0x07 用 3-byte ACK,不是 [0x01]');
    expect(ble.drinkAcks, isEmpty, reason: '存進資料庫後才由 ackDrinkEvent 回覆');
    await sub.cancel();
  });

  test('ackDrinkEvent:寫入 3-byte ACK(帶 seq),接收紀錄標為已確認', () async {
    ble.pushPacket(_event);
    await pumpEventQueue();
    expect(await manager.ackDrinkEvent(_event), isTrue);

    expect(ble.drinkAcks, [300]);
    expect(ble.ackCount, 0);
    expect(manager.log.single.acked, isTrue);
  });

  test('同一筆重複收到:每次都能再回 ACK', () async {
    ble.pushPacket(_event);
    ble.pushPacket(_event);
    await pumpEventQueue();
    await manager.ackDrinkEvent(_event);
    await manager.ackDrinkEvent(_event);
    expect(ble.drinkAcks, [300, 300]);
  });

  test('ackDrinkEvent:已斷線 → 不寫入、回傳 false、不丟例外', () async {
    await manager.disconnect();
    await pumpEventQueue();
    expect(await manager.ackDrinkEvent(_event), isFalse);
    expect(ble.drinkAcks, isEmpty);
  });

  test('ackDrinkEvent:寫入失敗 → 回傳 false(韌體會重送)', () async {
    ble.drinkAckError =
        const BleException(BleErrorCode.operationFailed, 'write failed');
    ble.pushPacket(_event);
    await pumpEventQueue();
    expect(await manager.ackDrinkEvent(_event), isFalse);
    expect(manager.log.single.acked, isFalse);
  });

  test('其他封包的 ACK 行為不變:WATER 仍回 1-byte ACK', () async {
    ble.pushPacket(const WaterPacket(fill25: 1, level: 0, timestamp: 1));
    await pumpEventQueue();
    expect(ble.ackCount, 1);
    expect(ble.drinkAcks, isEmpty);
  });
}
