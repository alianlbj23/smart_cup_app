import 'dart:async';
import 'dart:convert';
import 'dart:ui' show AppLifecycleState;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stut_food_intake_project/services/ble_service.dart';
import 'package:stut_food_intake_project/services/device_store.dart';
import 'package:stut_food_intake_project/state/cup_connection_manager.dart';
import 'package:stut_food_intake_project/state/disconnect_log.dart';

import 'fakes/fake_ble_service.dart';

const _cup = BleDeviceInfo(
  deviceId: 'AA:BB',
  deviceName: 'SmartCup',
  rssi: -50,
);
const _timeout = BleDisconnectReason(code: 8, description: 'GATT_CONN_TIMEOUT');

/// 可以讓讀取、寫入、清除失敗的假儲存。
class _FakeStorage implements DisconnectLogStorage {
  String? value;
  bool readThrows = false;
  bool writeThrows = false;
  bool clearThrows = false;

  /// 不為 null 時,read() 要等它完成才會回傳。
  Completer<void>? pendingRead;
  int writes = 0;

  @override
  Future<String?> read() async {
    final pending = pendingRead;
    if (pending != null) {
      pendingRead = null;
      await pending.future;
    }
    if (readThrows) throw StateError('讀取失敗');
    return value;
  }

  @override
  Future<void> write(String data) async {
    if (writeThrows) throw StateError('寫入失敗');
    writes++;
    value = data;
  }

  @override
  Future<void> clear() async {
    if (clearThrows) throw StateError('清除失敗');
    value = null;
  }
}

String _stored(int count) => jsonEncode([
      for (var i = 0; i < count; i++)
        {
          'at': DateTime(2026, 11, 1, 0, i).toIso8601String(),
          'device': 'old-$i',
          'code': 8,
          'desc': 'GATT_CONN_TIMEOUT',
          'bg': false,
          'doze': false,
        },
    ]);

void main() {
  late FakeBleService ble;
  late CupConnectionManager manager;

  Future<void> settle() => pumpEventQueue();

  Future<void> connect() async {
    ble.devicesInRange = [_cup];
    await manager.init();
    await manager.connectTo(_cup);
    await settle();
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ble = FakeBleService();
    manager = CupConnectionManager(
      ble: ble,
      store: DeviceStore(),
      backgroundRetryInterval: const Duration(hours: 1),
    );
  });

  tearDown(() {
    manager.dispose();
    ble.dispose();
  });

  group('CupConnectionManager.unexpectedDisconnects', () {
    test('意外斷線 → 發出事件,帶平台斷線原因與水杯名稱', () async {
      await connect();
      final events = <CupDisconnect>[];
      manager.unexpectedDisconnects.listen(events.add);

      ble.dropLink(reason: _timeout);
      await settle();

      expect(events, hasLength(1));
      expect(events.single.deviceId, 'AA:BB');
      expect(events.single.deviceName, 'SmartCup');
      expect(events.single.reason?.code, 8);
      expect(events.single.reason?.description, 'GATT_CONN_TIMEOUT');
      expect(events.single.wasDozing, isFalse);
    });

    test('休眠中斷線 → wasDozing 為 true', () async {
      await connect();
      final events = <CupDisconnect>[];
      manager.unexpectedDisconnects.listen(events.add);
      ble.pushPacket(
        const StatePacket(
          activity: CupActivity.dozing,
          secondsInState: 40,
          timestamp: 1000,
        ),
      );
      await settle();

      ble.dropLink(reason: _timeout);
      await settle();

      expect(events.single.wasDozing, isTrue);
    });

    test('使用者按斷線 → 不算意外斷線', () async {
      await connect();
      final events = <CupDisconnect>[];
      manager.unexpectedDisconnects.listen(events.add);

      await manager.disconnect();
      await settle();

      expect(events, isEmpty);
    });
  });

  group('App 在前景或背景', () {
    test('只有 paused、detached 算背景', () {
      expect(isAppInBackground(AppLifecycleState.paused), isTrue);
      expect(isAppInBackground(AppLifecycleState.detached), isTrue);
      expect(isAppInBackground(AppLifecycleState.resumed), isFalse);
      // 下拉通知列、系統對話框(例如權限視窗)蓋在上面:App 還在畫面上
      expect(isAppInBackground(AppLifecycleState.inactive), isFalse);
      expect(isAppInBackground(AppLifecycleState.hidden), isFalse);
      // 第一個 frame 之前還不知道:App 剛被使用者打開
      expect(isAppInBackground(null), isFalse);
    });
  });

  group('DisconnectLog 的儲存出錯', () {
    late _FakeStorage storage;

    DisconnectLog newLog() => DisconnectLog(
          manager: manager,
          isInBackground: () => false,
          storage: storage,
        );

    setUp(() => storage = _FakeStorage());

    test('清除失敗 → 之後的紀錄仍然會寫入', () async {
      await connect();
      final log = newLog();
      await log.load();
      log.start();
      storage.clearThrows = true;

      await log.clear();
      expect(log.records, isEmpty);

      storage.clearThrows = false;
      ble.dropLink(reason: _timeout);
      await settle();

      expect(log.records, hasLength(1));
      expect(storage.value, isNotNull);
      expect((jsonDecode(storage.value!) as List), hasLength(1));
      log.dispose();
    });

    test('寫入失敗 → 下一筆仍然會寫入', () async {
      await connect();
      final log = newLog();
      await log.load();
      log.start();
      storage.writeThrows = true;
      ble.dropLink(reason: _timeout);
      await settle();
      expect(storage.value, isNull);

      storage.writeThrows = false;
      await manager.connectTo(_cup);
      await settle();
      ble.dropLink(reason: _timeout);
      await settle();

      expect((jsonDecode(storage.value!) as List), hasLength(2));
      log.dispose();
    });

    test('存的紀錄超過 30 筆 → 讀出來只留最新的 30 筆', () async {
      storage.value = _stored(45);
      final log = newLog();

      await log.load();

      expect(log.records, hasLength(DisconnectLog.maxRecords));
      expect(log.records.first.deviceName, 'old-0');
      log.dispose();
    });

    test('讀取完成前就進來的紀錄不會被清掉,舊紀錄也還在', () async {
      await connect();
      storage
        ..value = _stored(2)
        ..pendingRead = Completer<void>();
      final pending = storage.pendingRead!;
      final log = newLog()..start();
      final loading = log.load();

      ble.dropLink(reason: _timeout);
      await settle();
      expect(log.records, hasLength(1));

      pending.complete();
      await loading;
      await settle();

      expect(log.records.map((r) => r.deviceName),
          ['SmartCup', 'old-0', 'old-1']);
      // 存回去的也是合併後的內容,舊紀錄沒有被蓋掉
      expect((jsonDecode(storage.value!) as List), hasLength(3));
      log.dispose();
    });

    test('還沒呼叫 load 就有斷線 → 存檔前先讀舊紀錄,不會蓋掉', () async {
      await connect();
      storage.value = _stored(2);
      final log = newLog()..start();

      ble.dropLink(reason: _timeout);
      await settle();

      expect((jsonDecode(storage.value!) as List), hasLength(3));
      expect(log.records, hasLength(3));
      log.dispose();
    });

    test('讀取失敗 → load 往上丟;之後不會用空的內容蓋掉存檔', () async {
      await connect();
      storage
        ..value = _stored(2)
        ..readThrows = true;
      final log = newLog()..start();

      await expectLater(log.load(), throwsStateError);

      ble.dropLink(reason: _timeout);
      await settle();

      expect(log.records, hasLength(1));
      expect(storage.writes, 0);
      expect((jsonDecode(storage.value!) as List), hasLength(2));
      log.dispose();
    });

    test('重複呼叫 load 不會出現重複的紀錄', () async {
      storage.value = _stored(2);
      final log = newLog();

      await log.load();
      await log.load();

      expect(log.records, hasLength(2));
      log.dispose();
    });
  });

  group('DisconnectLog', () {
    test('記下斷線原因、當時 App 在前景或背景,最新的在前面', () async {
      var background = true;
      await connect();
      final log = DisconnectLog(
        manager: manager,
        isInBackground: () => background,
      );
      await log.load();
      log.start();

      ble.dropLink(reason: _timeout);
      await settle();
      background = false;
      await manager.connectTo(_cup);
      await settle();
      ble.dropLink(
        reason: const BleDisconnectReason(
          code: 19,
          description: 'GATT_CONN_TERMINATE_PEER_USER',
        ),
      );
      await settle();

      expect(log.records.map((r) => r.code), [19, 8]);
      expect(log.records.map((r) => r.inBackground), [false, true]);
      expect(log.records.first.deviceName, 'SmartCup');
      log.dispose();
    });

    test('存在手機上,重開 App 還看得到', () async {
      await connect();
      final log = DisconnectLog(manager: manager, isInBackground: () => true);
      await log.load();
      log.start();
      ble.dropLink(reason: _timeout);
      await settle();
      log.dispose();

      final reopened = DisconnectLog(
        manager: manager,
        isInBackground: () => false,
      );
      await reopened.load();

      expect(reopened.records, hasLength(1));
      expect(reopened.records.single.code, 8);
      expect(reopened.records.single.description, 'GATT_CONN_TIMEOUT');
      expect(reopened.records.single.inBackground, isTrue);
      reopened.dispose();
    });

    test('最多留 30 筆', () async {
      await connect();
      final log = DisconnectLog(manager: manager, isInBackground: () => false);
      await log.load();
      log.start();
      for (var i = 0; i < 35; i++) {
        await manager.connectTo(_cup);
        await settle();
        ble.dropLink(
          reason: BleDisconnectReason(code: i, description: 'x'),
        );
        await settle();
      }

      expect(log.records, hasLength(DisconnectLog.maxRecords));
      expect(log.records.first.code, 34);
      log.dispose();
    });

    test('平台沒給原因 → 記成未知', () async {
      await connect();
      final log = DisconnectLog(manager: manager, isInBackground: () => false);
      await log.load();
      log.start();

      ble.dropLink();
      await settle();

      expect(log.records.single.code, isNull);
      expect(log.records.single.description, isNull);
      log.dispose();
    });

    test('存的資料壞掉 → 略過壞的那筆,其他照常讀', () async {
      SharedPreferences.setMockInitialValues({
        DisconnectLog.prefsKey: jsonEncode([
          {
            'at': '2026-11-26T10:00:00.000',
            'device': 'SmartCup',
            'code': 8,
            'desc': 'T',
            'bg': true,
            'doze': false,
          },
          {'at': 'not-a-date'},
          'garbage',
        ]),
      });
      final log = DisconnectLog(manager: manager, isInBackground: () => false);
      await log.load();

      expect(log.records, hasLength(1));
      expect(log.records.single.code, 8);
      log.dispose();
    });

    test('清除紀錄', () async {
      await connect();
      final log = DisconnectLog(manager: manager, isInBackground: () => false);
      await log.load();
      log.start();
      ble.dropLink(reason: _timeout);
      await settle();

      await log.clear();
      final reopened = DisconnectLog(
        manager: manager,
        isInBackground: () => false,
      );
      await reopened.load();

      expect(log.records, isEmpty);
      expect(reopened.records, isEmpty);
      log.dispose();
      reopened.dispose();
    });
  });
}
