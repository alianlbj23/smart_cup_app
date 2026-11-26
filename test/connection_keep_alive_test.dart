import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stut_food_intake_project/services/ble_service.dart';
import 'package:stut_food_intake_project/services/device_store.dart';
import 'package:stut_food_intake_project/state/connection_keep_alive.dart';
import 'package:stut_food_intake_project/state/cup_connection_manager.dart';

import 'fakes/fake_ble_service.dart';
import 'fakes/fake_keep_alive_service.dart';

const _cup = BleDeviceInfo(
  deviceId: 'AA:BB',
  deviceName: 'SmartCup',
  rssi: -50,
);

void main() {
  late FakeBleService ble;
  late DeviceStore store;
  late CupConnectionManager manager;
  late FakeKeepAliveService service;
  late ConnectionKeepAlive keepAlive;

  Future<void> settle() => pumpEventQueue();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ble = FakeBleService();
    store = DeviceStore();
    manager = CupConnectionManager(
      ble: ble,
      store: store,
      backgroundRetryInterval: const Duration(hours: 1),
    );
    service = FakeKeepAliveService();
    keepAlive = ConnectionKeepAlive(
      manager: manager,
      service: service,
      operationTimeout: const Duration(milliseconds: 200),
    )..start();
  });

  Future<void> connect() async {
    ble.devicesInRange = [_cup];
    await manager.init();
    await manager.connectTo(_cup);
    await settle();
  }

  tearDown(() {
    keepAlive.dispose();
    manager.dispose();
    ble.dispose();
  });

  test('沒有水杯、沒在連線 → 不開前景服務', () async {
    await manager.init();
    await settle();
    expect(service.calls, isEmpty);
  });

  test('連上水杯 → 開前景服務,通知寫水杯名稱', () async {
    ble.devicesInRange = [_cup];
    await manager.init();
    await manager.connectTo(_cup);
    await settle();

    expect(service.running, isTrue);
    expect(service.calls.first, startsWith('start:'));
    expect(service.calls.last, contains('SmartCup'));
    expect(service.calls.where((c) => c.startsWith('start:')), hasLength(1));
  });

  test('意外斷線 → 前景服務繼續開著(背景才能自動重連),通知改成重新連線中', () async {
    ble.devicesInRange = [_cup];
    await manager.init();
    await manager.connectTo(_cup);
    await settle();
    ble.devicesInRange = [];

    ble.dropLink();
    await settle();

    expect(service.calls, isNot(contains('stop')));
    expect(service.running, isTrue);
    // 假 BLE 的掃描馬上結束,所以會先「重新連線中」再變「找不到…背景重試中」
    expect(
      service.calls,
      contains(
        predicate<String>((c) => c.startsWith('update:') && c.contains('重新連線')),
      ),
    );
    expect(service.calls.last, contains('背景重試'));
  });

  test('找不到水杯、背景重試中 → 前景服務繼續開著', () async {
    await store.save(const RememberedDevice(id: 'AA:BB', name: 'SmartCup'));
    await manager.init();
    await settle();

    expect(manager.state, CupConnectionState.notFound);
    expect(service.running, isTrue);
    expect(service.calls, isNot(contains('stop')));
  });

  test('使用者按斷線 → 關掉前景服務', () async {
    ble.devicesInRange = [_cup];
    await manager.init();
    await manager.connectTo(_cup);
    await settle();

    await manager.disconnect();
    await settle();

    expect(service.calls.last, 'stop');
    expect(service.running, isFalse);
  });

  test('啟動失敗(背景不准開)→ App 回到前景時再試一次', () async {
    service.startSucceeds = false;
    ble.devicesInRange = [_cup];
    await manager.init();
    await manager.connectTo(_cup);
    await settle();
    expect(service.running, isFalse);

    service.startSucceeds = true;
    keepAlive.onAppResumed();
    await settle();

    expect(service.running, isTrue);
    expect(service.calls.where((c) => c.startsWith('start:')), hasLength(2));
  });

  test('通知內容沒變就不重複更新', () async {
    ble.devicesInRange = [_cup];
    await manager.init();
    await manager.connectTo(_cup);
    await settle();
    final before = service.calls.length;

    ble.pushStatus(
      const DeviceStatus(batteryPercent: 70),
    ); // 會 notifyListeners,但狀態沒變
    await settle();

    expect(service.calls.length, before);
  });

  group('錯誤之後服務一定關得掉', () {
    test('更新通知失敗 → 之後按斷線仍然會關服務', () async {
      await connect();
      service.updateThrows = true;
      ble.devicesInRange = [];
      ble.dropLink(); // 通知要改成「重新連線中」,update 丟例外
      await settle();
      expect(service.running, isTrue);

      await manager.disconnect();
      await settle();

      expect(service.calls.last, 'stop');
      expect(service.running, isFalse);
    });

    test('啟動逾時但服務其實已經起來 → 按斷線仍然會關服務', () async {
      service.startThrowsAfterStarting = true;
      await connect();
      expect(service.running, isTrue);

      await manager.disconnect();
      await settle();

      expect(service.calls.last, 'stop');
      expect(service.running, isFalse);
    });

    test('啟動還沒回來就按斷線 → 啟動完成後關服務', () async {
      final pending = Completer<void>();
      service.pendingStart = pending;
      await connect();
      expect(service.startCalls, 1);

      await manager.disconnect();
      await settle();
      expect(service.calls, isNot(contains('stop')));

      pending.complete();
      await settle();

      expect(service.calls.last, 'stop');
      expect(service.running, isFalse);
    });

    test('啟動一直沒有回應 → 逾時後不卡住,按斷線仍然會關服務', () async {
      service.pendingStart = Completer<void>(); // 永遠不完成
      await connect();

      await manager.disconnect();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await settle();

      expect(service.calls.last, 'stop');
    });

    test('啟動失敗(回傳 false)→ 按斷線時也會確認服務關了', () async {
      service.startSucceeds = false;
      await connect();

      await manager.disconnect();
      await settle();

      expect(service.calls.last, 'stop');
    });

    test('關服務失敗(回傳 false)→ App 回到前景時再關一次', () async {
      await connect();
      service.stopFails = true;
      await manager.disconnect();
      await settle();
      expect(service.running, isTrue);
      expect(service.stopCalls, 1);

      service.stopFails = false;
      keepAlive.onAppResumed();
      await settle();

      expect(service.stopCalls, 2);
      expect(service.running, isFalse);
    });

    test('關服務丟例外 → 重新連線再斷線時仍然會關', () async {
      await connect();
      service.stopThrows = true;
      await manager.disconnect();
      await settle();
      expect(service.running, isTrue);

      service.stopThrows = false;
      await manager.connectTo(_cup);
      await settle();
      await manager.disconnect();
      await settle();

      expect(service.calls.last, 'stop');
      expect(service.running, isFalse);
    });

    test('服務關掉之後回到前景 → 不會多關一次', () async {
      await connect();
      await manager.disconnect();
      await settle();
      expect(service.stopCalls, 1);

      keepAlive.onAppResumed();
      await settle();

      expect(service.stopCalls, 1);
    });

    test('dispose 時關服務沒有回應 → 逾時後 dispose 仍然會結束', () async {
      await connect();
      service.pendingStop = Completer<void>(); // 永遠不完成

      await keepAlive.dispose().timeout(const Duration(seconds: 2));

      expect(service.calls.last, 'stop');
    });
  });

  group('配對', () {
    test('首次配對掃描 → 不開前景服務', () async {
      ble.devicesInRange = [_cup];
      await manager.init();
      await manager.startPairingScan();
      await settle();

      expect(service.calls, isEmpty);
    });

    test('已有水杯時配對另一個:掃描期間不顯示「重新連線中」,連上才開服務', () async {
      await connect();
      const other = BleDeviceInfo(
        deviceId: 'CC:DD',
        deviceName: 'SmartCup-2',
        rssi: -40,
      );
      ble.devicesInRange = [_cup, other];
      service.calls.clear();

      // 配對流程:先斷開目前的水杯,再掃描
      await manager.disconnect();
      await manager.startPairingScan();
      await settle();

      expect(service.calls, ['stop']);

      await manager.connectTo(other);
      await settle();

      expect(service.calls, ['stop', 'start:已連線 · SmartCup-2']);
    });
  });

  group('狀態沒變就不重複操作', () {
    test('啟動失敗後,資料一直進來也不會一直重試;回到前景才重試', () async {
      service.startSucceeds = false;
      await connect();
      expect(service.startCalls, 1);

      for (var i = 0; i < 5; i++) {
        ble.pushStatus(DeviceStatus(batteryPercent: 70 - i));
        await settle();
      }
      expect(service.startCalls, 1);

      service.startSucceeds = true;
      keepAlive.onAppResumed();
      await settle();
      expect(service.startCalls, 2);
      expect(service.running, isTrue);
    });
  });

  group('回到前景', () {
    test('維持中 → 讓服務補做只能在前景做的事(請求通知權限)', () async {
      await connect();

      keepAlive.onAppResumed();
      await settle();

      expect(service.foregroundCalls, 1);
      expect(service.startCalls, 1);
    });

    test('這次才拿到通知權限 → 重送一次通知內容', () async {
      await connect();
      service.foregroundGrantsNotification = true;
      final before = service.calls.length;

      keepAlive.onAppResumed();
      await settle();

      expect(service.calls.length, before + 1);
      expect(service.calls.last, 'update:已連線 · SmartCup');
    });

    test('沒有在維持(idle)→ 不打擾服務', () async {
      await manager.init();
      await settle();

      keepAlive.onAppResumed();
      await settle();

      expect(service.foregroundCalls, 0);
      expect(service.calls, isEmpty);
    });
  });

  test('通知標題', () {
    expect(ConnectionKeepAlive.notificationTitle, '智慧水杯');
  });

  test('dispose → 關掉前景服務', () async {
    ble.devicesInRange = [_cup];
    await manager.init();
    await manager.connectTo(_cup);
    await settle();

    await keepAlive.dispose();

    expect(service.calls.last, 'stop');
  });
}
