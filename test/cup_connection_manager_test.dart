import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stut_food_intake_project/services/ble_service.dart';
import 'package:stut_food_intake_project/services/device_store.dart';
import 'package:stut_food_intake_project/state/cup_connection_manager.dart';

import 'fakes/fake_ble_service.dart';

const _cup = BleDeviceInfo(deviceId: 'AA:BB', deviceName: 'SmartCup', rssi: -50);
const _other =
    BleDeviceInfo(deviceId: 'CC:DD', deviceName: 'SmartCup2', rssi: -40);

void main() {
  late FakeBleService ble;
  late DeviceStore store;
  late CupConnectionManager manager;

  Future<void> settle() => pumpEventQueue();

  Future<void> remember(BleDeviceInfo d) =>
      store.save(RememberedDevice(id: d.deviceId, name: d.deviceName));

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ble = FakeBleService();
    store = DeviceStore();
    manager = CupConnectionManager(ble: ble, store: store);
  });

  tearDown(() {
    manager.dispose();
    ble.dispose();
  });

  group('首次配對', () {
    test('無記憶裝置 → 啟動時不掃描,維持 Idle', () async {
      await manager.init();
      await settle();

      expect(ble.scanCalls, isEmpty);
      expect(manager.state, CupConnectionState.idle);
    });

    test('開始配對 → 中斷目前水杯,掃描並列出清單(依 RSSI 排序)', () async {
      ble.devicesInRange = [_cup, _other];
      await manager.init();
      await manager.beginPairing();
      await settle();

      expect(ble.scanCalls, [null], reason: '非定向掃描');
      expect(manager.flow, CupFlow.pairing);
      expect(manager.state, CupConnectionState.idle);
      expect(manager.scanResults.map((d) => d.deviceId), ['CC:DD', 'AA:BB']);
    });

    test('選擇裝置 → Ready,寫入 TimeSync 並記憶裝置', () async {
      ble.devicesInRange = [_cup];
      await manager.init();
      await manager.connectTo(_cup);
      await settle();

      expect(manager.state, CupConnectionState.ready);
      expect(ble.timeSyncs, hasLength(1));
      expect(manager.deviceStatus?.batteryPercent, 80);
      final saved = await store.load();
      expect(saved?.id, 'AA:BB');
      expect(saved?.name, 'SmartCup');
    });

    test('連線失敗 → 回到 Idle 並顯示錯誤,不記憶裝置', () async {
      ble.devicesInRange = [_cup];
      ble.connectError =
          const BleException(BleErrorCode.connectionFailed, 'boom');
      await manager.init();
      await manager.connectTo(_cup);
      await settle();

      expect(manager.state, CupConnectionState.idle);
      expect(manager.message, contains('boom'));
      expect(await store.load(), isNull);
      expect(ble.connectCalls, hasLength(1));
    });
  });

  group('自動重連', () {
    test('有記憶裝置 → 定向掃描並自動連線到 Ready', () async {
      await remember(_cup);
      ble.devicesInRange = [_cup];
      await manager.init();
      await settle();

      expect(ble.scanCalls, ['AA:BB']);
      expect(manager.flow, CupFlow.reconnect);
      expect(manager.state, CupConnectionState.ready);
      expect(ble.timeSyncs, hasLength(1));
    });

    test('找不到記憶裝置 → notFound,可切換回手動配對', () async {
      await remember(_cup);
      await manager.init();
      await settle();

      expect(manager.state, CupConnectionState.notFound);
      expect(ble.connectCalls, isEmpty);

      ble.devicesInRange = [_other];
      await manager.startPairingScan();
      expect(manager.flow, CupFlow.pairing);
      expect(manager.scanResults.single.deviceId, 'CC:DD');
    });

    test('記憶裝置連線失敗 → 重試 3 次後 notFound', () async {
      await remember(_cup);
      ble.devicesInRange = [_cup];
      ble.connectError =
          const BleException(BleErrorCode.serviceNotFound, 'no service');
      await manager.init();
      await settle();

      expect(ble.connectCalls,
          hasLength(CupConnectionManager.maxReconnectAttempts));
      expect(manager.state, CupConnectionState.notFound);
    });

    test('Ready 後意外斷線 → 自動重連回 Ready', () async {
      await remember(_cup);
      ble.devicesInRange = [_cup];
      await manager.init();
      await settle();
      expect(manager.state, CupConnectionState.ready);

      ble.dropLink();
      await settle();

      expect(ble.connectCalls, ['AA:BB', 'AA:BB']);
      expect(manager.state, CupConnectionState.ready);
    });
  });

  test('使用者主動斷線 → Idle,不自動重連', () async {
    await remember(_cup);
    ble.devicesInRange = [_cup];
    await manager.init();
    await settle();

    await manager.disconnect();
    await settle();

    expect(manager.state, CupConnectionState.idle);
    expect(ble.connectCalls, hasLength(1));
    expect(ble.isConnected, isFalse);
  });

  test('Ready 時收到資料 → 記錄並寫入 ACK', () async {
    ble.devicesInRange = [_cup];
    await manager.init();
    await manager.connectTo(_cup);
    await settle();

    ble.pushData(42, 1700000000);
    await settle();

    expect(manager.receivedCount, 1);
    expect((manager.log.single.packet as DummyDataPacket).value, 42);
    expect(manager.log.single.acked, isTrue);
    expect(ble.ackCount, 1);
  });

  test('Ready 時收到 WATER → latestWater 更新,RAW 不影響水量', () async {
    ble.devicesInRange = [_cup];
    await manager.init();
    await manager.connectTo(_cup);
    await settle();

    expect(manager.latestWater, isNull);
    expect(manager.isWaterStale(DateTime.now()), isTrue);

    ble.pushPacket(const WaterPacket(
        fill25: WaterPacket.fill25Max ~/ 2, level: 5, timestamp: 100));
    ble.pushPacket(const RawPacket(count: 292000, timestamp: 100));
    await settle();

    expect(manager.receivedCount, 2);
    expect(manager.latestWater?.fillPercent, closeTo(50.0, 0.001));
    expect(manager.latestWater?.level, 5);
    expect(manager.isWaterStale(DateTime.now()), isFalse);
    expect(
        manager.isWaterStale(
            DateTime.now().add(CupConnectionManager.waterStaleAfter * 2)),
        isTrue);
    expect(manager.latestPose, isNull);
    expect(ble.ackCount, 2);
  });

  test('Ready 時收到 ATTITUDE → 更新 latestAttitude,不 ACK、不進 log、不計數',
      () async {
    ble.devicesInRange = [_cup];
    await manager.init();
    await manager.connectTo(_cup);
    await settle();

    expect(manager.latestAttitude, isNull);
    expect(manager.isAttitudeStale(DateTime.now()), isTrue);

    var notified = 0;
    manager.addListener(() => notified++);
    ble.pushPacket(const AttitudePacket(
        pitchDeciDegrees: -120, rollDeciDegrees: 300, timestamp: 5));
    ble.pushPacket(const AttitudePacket(
        pitchDeciDegrees: 10, rollDeciDegrees: -20, timestamp: 6));
    await settle();

    expect(notified, 2);
    expect(manager.latestAttitude?.pitchDeciDegrees, 10);
    expect(manager.latestAttitude?.rollDeciDegrees, -20);
    expect(manager.latestAttitudeAt, isNotNull);
    expect(manager.isAttitudeStale(DateTime.now()), isFalse);
    expect(
        manager.isAttitudeStale(DateTime.now()
            .add(CupConnectionManager.attitudeStaleAfter * 2)),
        isTrue);
    expect(manager.receivedCount, 0);
    expect(manager.log, isEmpty);
    expect(ble.ackCount, 0);

    // 其他封包照常計數與 ACK。
    ble.pushPacket(const PosePacket(
        tiltDeciDegrees: 300,
        pose: CupPose.tilted,
        moving: false,
        timestamp: 7));
    await settle();
    expect(manager.receivedCount, 1);
    expect(manager.log.single.packet, isA<PosePacket>());
    expect(ble.ackCount, 1);
    expect(manager.isPoseStale(DateTime.now()), isFalse);
  });

  test('斷線或忘記裝置 → latestAttitude 清除', () async {
    await remember(_cup);
    ble.devicesInRange = [_cup];
    await manager.init();
    await settle();
    ble.pushPacket(const AttitudePacket(
        pitchDeciDegrees: 0, rollDeciDegrees: 100, timestamp: 1));
    await settle();
    expect(manager.latestAttitude, isNotNull);

    await manager.disconnect();
    await settle();
    expect(manager.latestAttitude, isNull);
    expect(manager.latestAttitudeAt, isNull);

    await manager.startAutoReconnect();
    await settle();
    ble.pushPacket(const AttitudePacket(
        pitchDeciDegrees: 0, rollDeciDegrees: 100, timestamp: 2));
    await settle();
    expect(manager.latestAttitude, isNotNull);

    await manager.forgetDevice();
    await settle();
    expect(manager.latestAttitude, isNull);
  });

  test('未連線時收到 ATTITUDE → 忽略', () async {
    ble.pushPacket(const AttitudePacket(
        pitchDeciDegrees: 0, rollDeciDegrees: 100, timestamp: 1));
    await settle();
    expect(manager.latestAttitude, isNull);
  });

  test('忘記此裝置 → latestWater 清除', () async {
    ble.devicesInRange = [_cup];
    await manager.init();
    await manager.connectTo(_cup);
    await settle();
    ble.pushPacket(const WaterPacket(fill25: 1000, level: 1, timestamp: 1));
    await settle();
    expect(manager.latestWater, isNotNull);

    await manager.forgetDevice();
    await settle();

    expect(manager.latestWater, isNull);
    expect(manager.latestWaterAt, isNull);
  });

  test('忘記此裝置 → 斷線、清除記憶、回到 Idle', () async {
    await remember(_cup);
    ble.devicesInRange = [_cup];
    await manager.init();
    await settle();

    await manager.forgetDevice();
    await settle();

    expect(await store.load(), isNull);
    expect(manager.rememberedDevice, isNull);
    expect(ble.isConnected, isFalse);
    expect(manager.state, CupConnectionState.idle);
    expect(ble.scanCalls, ['AA:BB'], reason: '不再自動掃描');
  });

  test('切換到另一個已配對水杯 → 中斷目前水杯並連線新水杯', () async {
    await remember(_cup);
    ble.devicesInRange = [_cup, _other];
    await manager.init();
    await settle();

    await manager.reconnectTo(
        RememberedDevice(id: _other.deviceId, name: _other.deviceName));
    await settle();

    expect(manager.state, CupConnectionState.ready);
    expect(manager.activeDeviceId, 'CC:DD');
    expect((await store.load())?.id, 'CC:DD');
  });

  test('取消配對 → 回頭連線先前記憶的水杯', () async {
    await remember(_cup);
    ble.devicesInRange = [_cup];
    await manager.init();
    await settle();

    await manager.beginPairing();
    expect(ble.isConnected, isFalse);
    await manager.cancelPairing();
    await settle();

    expect(manager.state, CupConnectionState.ready);
    expect(manager.activeDeviceId, 'AA:BB');
  });

  test('連線中取消 → Idle,完成的連線結果被捨棄', () async {
    ble.devicesInRange = [_cup];
    await manager.init();
    final pending = manager.connectTo(_cup);
    unawaited(manager.disconnect());
    await pending;
    await settle();

    expect(manager.state, CupConnectionState.idle);
    expect(await store.load(), isNull);
  });
}
