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

    test('找不到記憶裝置(水杯休眠)→ 背景定期重試,醒來後自動連上', () async {
      manager.dispose();
      manager = CupConnectionManager(
        ble: ble,
        store: store,
        backgroundRetryInterval: const Duration(milliseconds: 50),
      );
      await remember(_cup);
      await manager.init();
      await settle();
      expect(manager.state, CupConnectionState.notFound);
      expect(manager.message, contains('休眠'));

      // 還在睡:再試一次仍然找不到,維持 notFound 並繼續排下一次
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await settle();
      expect(manager.state, CupConnectionState.notFound);

      // 水杯醒來開始廣播 → 下一次背景重試自動連上
      ble.devicesInRange = [_cup];
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await settle();
      expect(manager.state, CupConnectionState.ready);
      expect(ble.connectCalls.single, 'AA:BB');
    });

    group('找不到水杯時的重試節奏', () {
      /// 快:每 20 ms、最多 3 次;之後放慢(1 小時,等於測試期間不會再試)。
      CupConnectionManager newManager() => CupConnectionManager(
            ble: ble,
            store: store,
            fastRetryInterval: const Duration(milliseconds: 20),
            fastRetryCount: 3,
            backgroundRetryInterval: const Duration(hours: 1),
          );

      Future<void> wait(int ms) async {
        await Future<void>.delayed(Duration(milliseconds: ms));
        await settle();
      }

      test('剛找不到時密集重試;連續好幾次都找不到才放慢', () async {
        manager.dispose();
        manager = newManager();
        await remember(_cup);
        await manager.init();
        await settle();
        expect(manager.state, CupConnectionState.notFound);
        expect(ble.scanCalls, hasLength(1));
        expect(manager.autoRetryPending, isTrue);

        await wait(300);

        // 第一次 + 3 次密集重試,之後要等很久才會再試
        expect(ble.scanCalls, hasLength(4));
        expect(manager.state, CupConnectionState.notFound);
        expect(manager.autoRetryPending, isTrue);
      });

      test('密集重試期間水杯出現 → 很快自動連上', () async {
        manager.dispose();
        manager = newManager();
        await remember(_cup);
        await manager.init();
        await settle();

        ble.devicesInRange = [_cup];
        await wait(100);

        expect(manager.state, CupConnectionState.ready);
        expect(manager.autoRetryPending, isFalse);
      });

      test('放慢之後使用者按「重試」→ 重新開始密集重試', () async {
        manager.dispose();
        manager = newManager();
        await remember(_cup);
        await manager.init();
        await wait(300);
        expect(ble.scanCalls, hasLength(4));

        await manager.startAutoReconnect();
        await wait(300);

        expect(ble.scanCalls, hasLength(8));
      });

      test('連上之後又斷線找不到 → 重新開始密集重試', () async {
        manager.dispose();
        manager = newManager();
        await remember(_cup);
        await manager.init();
        await wait(300);
        expect(ble.scanCalls, hasLength(4));

        ble.devicesInRange = [_cup];
        await manager.startAutoReconnect();
        await settle();
        expect(manager.state, CupConnectionState.ready);
        final before = ble.scanCalls.length;

        ble.devicesInRange = [];
        ble.dropLink();
        await wait(300);

        // 斷線後馬上找一次 + 3 次密集重試
        expect(ble.scanCalls, hasLength(before + 4));
      });

      test('App 回到前景:正在等下一次重試 → 立刻再找一次', () async {
        manager.dispose();
        manager = newManager();
        await remember(_cup);
        await manager.init();
        await wait(300);
        expect(ble.scanCalls, hasLength(4));
        ble.devicesInRange = [_cup];

        manager.onAppResumed();
        await settle();

        expect(manager.state, CupConnectionState.ready);
      });

      test('App 回到前景:已連線、未配對、使用者已中斷時什麼都不做', () async {
        await manager.init();
        manager.onAppResumed();
        await settle();
        expect(ble.scanCalls, isEmpty);

        ble.devicesInRange = [_cup];
        await manager.connectTo(_cup);
        await settle();
        final scans = ble.scanCalls.length;
        manager.onAppResumed();
        await settle();
        expect(ble.scanCalls, hasLength(scans));

        await manager.disconnect();
        manager.onAppResumed();
        await settle();
        expect(ble.scanCalls, hasLength(scans));
        expect(manager.state, CupConnectionState.idle);
      });
    });

    test('使用者主動中斷 → 不再背景重試', () async {
      manager.dispose();
      manager = CupConnectionManager(
        ble: ble,
        store: store,
        backgroundRetryInterval: const Duration(milliseconds: 50),
      );
      await remember(_cup);
      await manager.init();
      await settle();
      expect(manager.state, CupConnectionState.notFound);

      await manager.disconnect();
      ble.devicesInRange = [_cup];
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await settle();
      expect(manager.state, CupConnectionState.idle);
      expect(ble.connectCalls, isEmpty);
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

  group('休眠狀態(STATE)', () {
    const dozing = StatePacket(
        activity: CupActivity.dozing, secondsInState: 30, timestamp: 1);
    const awake = StatePacket(
        activity: CupActivity.active, secondsInState: 0, timestamp: 2);

    Future<void> connect() async {
      await remember(_cup);
      ble.devicesInRange = [_cup];
      await manager.init();
      await settle();
      expect(manager.state, CupConnectionState.ready);
    }

    test('STATE → 回 ACK、進接收紀錄、計數並更新 latestState', () async {
      await connect();
      expect(manager.latestState, isNull);
      expect(manager.isDozing(DateTime.now()), isFalse);

      ble.pushPacket(dozing);
      await settle();

      expect(manager.receivedCount, 1);
      expect(manager.log.single.packet, same(dozing));
      expect(manager.log.single.acked, isTrue);
      expect(ble.ackCount, 1);
      expect(manager.latestState, same(dozing));
      expect(manager.latestStateAt, isNotNull);
      expect(manager.isDozing(DateTime.now()), isTrue);

      ble.pushPacket(awake);
      await settle();
      expect(manager.receivedCount, 2);
      expect(ble.ackCount, 2);
      expect(manager.latestState, same(awake));
      expect(manager.isDozing(DateTime.now()), isFalse);
      expect(manager.dozingFor(DateTime.now()), isNull);
    });

    test('isDozing 在收到後 25 秒內有效,之後失效;dozingFor 加上經過時間',
        () async {
      await connect();
      ble.pushPacket(dozing);
      await settle();
      final at = manager.latestStateAt!;

      expect(manager.isDozing(at.add(const Duration(seconds: 25))), isTrue);
      expect(manager.isDozing(at.add(const Duration(seconds: 26))), isFalse);
      expect(manager.dozingFor(at), const Duration(seconds: 30));
      expect(manager.dozingFor(at.add(const Duration(seconds: 12))),
          const Duration(seconds: 42));
      expect(manager.dozingFor(at.add(const Duration(seconds: 26))), isNull);
    });

    test('休眠中水位不算過期;keepalive 中斷後回到一般過期判斷', () async {
      await connect();
      ble.pushPacket(const WaterPacket(fill25: 1000, level: 1, timestamp: 1));
      ble.pushPacket(dozing);
      await settle();
      final at = manager.latestStateAt!;

      // WATER 30 秒才一筆:休眠中不算過期。
      final later = at.add(const Duration(seconds: 20));
      expect(manager.isWaterStale(later), isFalse);
      // 休眠中不送姿態,姿態本身仍是過期的(由 UI 改顯示休眠)。
      expect(manager.isPoseStale(later), isTrue);
      // 25 秒沒收到 keepalive → 不再當休眠,水位照一般規則過期。
      expect(manager.isWaterStale(at.add(const Duration(seconds: 26))),
          isTrue);
    });

    test('喚醒當下不會閃「資料過期」:從喚醒時刻起算過期', () async {
      await connect();
      ble.pushPacket(const WaterPacket(fill25: 1000, level: 1, timestamp: 1));
      await settle();
      final waterAt = manager.latestWaterAt!;
      expect(manager.isWaterStale(waterAt.add(const Duration(seconds: 6))),
          isTrue);

      ble.pushPacket(awake);
      await settle();
      final wokeAt = manager.latestStateAt!;
      expect(manager.isWaterStale(wokeAt.add(const Duration(seconds: 2))),
          isFalse);
      expect(manager.isWaterStale(wokeAt.add(const Duration(seconds: 6))),
          isTrue);
      // 從沒收過的資料仍視為沒有資料。
      expect(manager.isPoseStale(wokeAt), isTrue);
    });

    test('主動斷線、意外斷線、換杯、忘記水杯 → latestState 清除', () async {
      await connect();
      ble.pushPacket(dozing);
      await settle();
      expect(manager.latestState, isNotNull);

      await manager.disconnect();
      await settle();
      expect(manager.latestState, isNull);
      expect(manager.latestStateAt, isNull);
      expect(manager.isDozing(DateTime.now()), isFalse);

      await manager.startAutoReconnect();
      await settle();
      ble.pushPacket(dozing);
      await settle();
      expect(manager.isDozing(DateTime.now()), isTrue);

      // 意外斷線後自動重連回 Ready,休眠狀態不沿用(等韌體重送)。
      ble.dropLink();
      await settle();
      expect(manager.state, CupConnectionState.ready);
      expect(manager.latestState, isNull);
      expect(manager.isDozing(DateTime.now()), isFalse);

      ble.pushPacket(dozing);
      await settle();
      ble.devicesInRange = [_cup, _other];
      await manager.reconnectTo(
          RememberedDevice(id: _other.deviceId, name: _other.deviceName));
      await settle();
      expect(manager.activeDeviceId, 'CC:DD');
      expect(manager.latestState, isNull);

      ble.pushPacket(dozing);
      await settle();
      await manager.forgetDevice();
      await settle();
      expect(manager.latestState, isNull);
    });
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
