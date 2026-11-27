import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stut_food_intake_project/data/intake_repository.dart';
import 'package:stut_food_intake_project/services/ble_service.dart';
import 'package:stut_food_intake_project/services/device_store.dart';
import 'package:stut_food_intake_project/state/cup_connection_manager.dart';
import 'package:stut_food_intake_project/state/intake_recorder.dart';

import 'fakes/fake_ble_service.dart';

const _cup = BleDeviceInfo(deviceId: 'AA:BB', deviceName: 'SmartCup', rssi: -50);

/// 寫入韌體事件時一律失敗的 repository(模擬資料庫寫入錯誤)。
class _FailingRepo extends IntakeRepository {
  _FailingRepo(super.db, {super.clock});

  @override
  Future<FirmwareEventResult> addFirmwareEvent({
    required String cupId,
    required String dedupKey,
    required IntakeKind kind,
    required int ml,
    required DateTime startedAt,
    required bool timeEstimated,
    required int capacityMl,
    required double levelBeforePct,
    required double levelAfterPct,
    required bool sawDrinking,
    required bool tooLong,
    required int seq,
  }) =>
      Future.error(StateError('disk full'));
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late FakeBleService ble;
  late CupConnectionManager manager;
  late AppDatabase db;
  late IntakeRepository repo;
  late IntakeRecorder recorder;
  late DateTime now;
  final day = DateTime(2026, 11, 23);

  /// 事件時間:2026-11-23 08:30:00(當地時間)的 Unix 秒。
  final eventAt = DateTime(2026, 11, 23, 8, 30);
  final eventTs = eventAt.millisecondsSinceEpoch ~/ 1000;

  Future<void> boot({
    FirmwareVersion? firmware = const FirmwareVersion(0, 3, 0),
    String? bleAddress,
    IntakeRepository Function(AppDatabase db)? makeRepo,
    // 大部分測試模擬的是 350 mL 的水杯;null = 第一次連上、沒設定過容量的水杯。
    int? capacityMl = 350,
  }) async {
    SharedPreferences.setMockInitialValues({});
    now = DateTime(2026, 11, 23, 9);
    ble = FakeBleService()
      ..devicesInRange = [_cup]
      ..deviceStatus = DeviceStatus(
          batteryPercent: 80, firmwareVersion: firmware, bleAddress: bleAddress);
    manager = CupConnectionManager(ble: ble, store: DeviceStore());
    db = AppDatabase(NativeDatabase.memory());
    repo = makeRepo?.call(db) ?? IntakeRepository(db, clock: () => now);
    await repo.init();
    if (capacityMl != null) {
      await repo.ensureCup(_cup.deviceId, _cup.deviceName);
      await repo.setCupCapacity(_cup.deviceId, capacityMl);
    }
    recorder = IntakeRecorder(manager: manager, repo: repo, clock: () => now);
    recorder.start();
  }

  tearDown(() async {
    recorder.dispose();
    manager.dispose();
    ble.dispose();
    await db.close();
  });

  Future<void> settle() async {
    await pumpEventQueue();
    await recorder.flush();
    await pumpEventQueue();
  }

  Future<void> connect() async {
    await manager.connectTo(_cup);
    await settle();
    expect(manager.state, CupConnectionState.ready);
  }

  DrinkEventPacket event({
    int a = 124,
    int b = 111,
    FirmwareEventKind kind = FirmwareEventKind.drink,
    bool sawDrinking = true,
    bool tooLong = false,
    bool timeUnknown = false,
    int seq = 12,
    int? timestamp,
  }) =>
      DrinkEventPacket(
        beforeHalfPercent: a,
        afterHalfPercent: b,
        kind: kind,
        sawDrinking: sawDrinking,
        tooLong: tooLong,
        timeUnknown: timeUnknown,
        seq: seq,
        timestamp: timestamp ?? (timeUnknown ? 0 : eventTs),
      );

  Future<void> push(DrinkEventPacket p) async {
    ble.pushPacket(p);
    await settle();
  }

  Future<List<IntakeEvent>> events() => repo.eventsOnDay(day);

  group('韌體事件寫入 intake_events', () {
    test('喝水 62.0% → 55.5%、容量 350 → 23 mL,source = firmware、status = ok,並回 ACK',
        () async {
      await boot();
      await connect();
      await push(event());

      final e = (await events()).single;
      expect(e.cupId, 'AA:BB');
      expect(e.kind, IntakeKind.drink);
      expect(e.source, IntakeSource.firmware);
      expect(e.status, IntakeStatus.ok);
      expect(e.ml, 23, reason: '|62.0 − 55.5| / 100 × 350 = 22.75 → 四捨五入');
      expect(e.capacityMl, 350);
      expect(e.levelBeforePct, 62.0);
      expect(e.levelAfterPct, 55.5);
      expect(e.beforeMl, 217);
      expect(e.afterMl, 194);
      expect(e.startedAt, eventAt, reason: '用韌體的時間戳,不是收到的時間');
      expect(e.endedAtMs, isNull);
      expect(e.timeEstimated, isNot(true));
      expect(e.sawDrinking, isTrue);
      expect(e.tooLong, isFalse);
      expect(e.fwSeq, 12);
      expect(e.syncedAtMs, isNull);
      expect((await repo.dailyTotals(day, day))[day], 23);
      expect(ble.drinkAcks, [12]);
      expect(ble.ackCount, 0);
    });

    test('沒有飲用姿態(吸管)也算喝水:status = ok,計入飲水量', () async {
      await boot();
      await connect();
      await push(event(sawDrinking: false));

      final e = (await events()).single;
      expect(e.kind, IntakeKind.drink);
      expect(e.status, IntakeStatus.ok);
      expect(e.sawDrinking, isFalse);
      expect((await repo.dailyTotals(day, day))[day], 23);
    });

    test('too_long 的喝水事件一樣是 ok', () async {
      await boot();
      await connect();
      await push(event(tooLong: true, sawDrinking: false));

      final e = (await events()).single;
      expect(e.status, IntakeStatus.ok);
      expect(e.tooLong, isTrue);
    });

    test('kind = 1 → refill,不計入飲水量', () async {
      await boot();
      await connect();
      await push(event(a: 20, b: 180, kind: FirmwareEventKind.refill));

      final e = (await events()).single;
      expect(e.kind, IntakeKind.refill);
      expect(e.status, IntakeStatus.ok);
      expect(e.ml, 280, reason: '|10 − 90| / 100 × 350');
      expect((await repo.dailyTotals(day, day))[day], 0);
      expect(ble.drinkAcks, [12]);
    });

    test('第一次連上的水杯(沒設定過容量):用預設容量 276 mL 換算', () async {
      await boot(capacityMl: null);
      await connect();
      await push(event());

      final e = (await events()).single;
      expect(e.ml, 18, reason: '|62.0 − 55.5| / 100 × 276 = 17.94 → 四捨五入');
      expect(e.capacityMl, 276);
      expect(ble.drinkAcks, [12]);
    });

    test('使用該水杯設定的容量', () async {
      await boot();
      await connect();
      await repo.setCupCapacity('AA:BB', 500);
      await settle();
      await push(event());

      final e = (await events()).single;
      expect(e.ml, 33, reason: '6.5% × 500 = 32.5 → 33');
      expect(e.capacityMl, 500);
    });

    test('保留的種類(2、3):不寫入,但仍回 ACK,不讓韌體一直重送', () async {
      await boot();
      await connect();
      await push(event(kind: FirmwareEventKind.unknown, seq: 40));

      expect(await events(), isEmpty);
      expect(ble.drinkAcks, [40]);
    });
  });

  group('時間', () {
    test('time_unknown:用收到的時間,並記下時間為估計', () async {
      await boot();
      await connect();
      now = DateTime(2026, 11, 23, 10, 15, 7);
      await push(event(timeUnknown: true));

      final e = (await events()).single;
      expect(e.startedAt, DateTime(2026, 11, 23, 10, 15, 7));
      expect(e.timeEstimated, isTrue);
      expect(e.status, IntakeStatus.ok, reason: '合約 §1.2:一樣計入');
      expect(ble.drinkAcks, [12]);
    });

    test('時間戳不合理(0、太舊、在未來)→ 同樣用收到的時間並標成估計', () async {
      await boot();
      await connect();
      final future =
          now.add(const Duration(days: 2)).millisecondsSinceEpoch ~/ 1000;
      await push(event(seq: 1, timestamp: 0));
      now = now.add(const Duration(seconds: 5));
      await push(event(seq: 2, timestamp: 1234));
      now = now.add(const Duration(seconds: 5));
      await push(event(seq: 3, timestamp: future));

      final all = await events();
      expect(all, hasLength(3));
      expect(all.every((e) => e.timeEstimated == true), isTrue);
      expect(all.map((e) => e.startedAt), [
        DateTime(2026, 11, 23, 9),
        DateTime(2026, 11, 23, 9, 0, 5),
        DateTime(2026, 11, 23, 9, 0, 10),
      ]);
    });
  });

  group('去重與 ACK', () {
    test('同一筆重送:只有一筆紀錄,但每次都回 ACK', () async {
      await boot();
      await connect();
      await push(event());
      now = now.add(const Duration(seconds: 2));
      await push(event());

      expect(await events(), hasLength(1));
      expect(ble.drinkAcks, [12, 12]);
    });

    test('time_unknown 的事件重送(每次收到的時間不同)也只有一筆', () async {
      await boot();
      await connect();
      await push(event(timeUnknown: true));
      now = now.add(const Duration(seconds: 6));
      await push(event(timeUnknown: true));
      now = now.add(const Duration(minutes: 30));
      await push(event(timeUnknown: true));

      final e = (await events()).single;
      expect(e.startedAt, DateTime(2026, 11, 23, 9), reason: '保留第一次收到的時間');
      expect(ble.drinkAcks, [12, 12, 12]);
    });

    test('使用者刪除後韌體又重送:不會復活', () async {
      await boot();
      await connect();
      await push(event());
      await repo.deleteEvent((await events()).single.id);
      await push(event());

      expect(await events(), isEmpty);
      expect(await repo.allEvents(), hasLength(1));
      expect(ble.drinkAcks, [12, 12]);
    });

    test('seq 相同但時間戳或 A/B 不同 → 不同的事件(清空 flash 後 seq 會重來)', () async {
      await boot();
      await connect();
      await push(event(seq: 0));
      await push(event(seq: 0, timestamp: eventTs + 600));
      await push(event(seq: 0, timestamp: eventTs + 600, a: 111, b: 100));

      expect(await events(), hasLength(3));
      expect(ble.drinkAcks, [0, 0, 0]);
    });

    test('前後相接的喝水事件(上一筆的 B = 下一筆的 A)每一筆都計入', () async {
      await boot(firmware: const FirmwareVersion(0, 4, 0));
      await connect();
      // 吸管小口喝:62% → 55.5% → 50% → 45%,saw_drinking 都是 0。
      await push(event(seq: 12, a: 124, b: 111, sawDrinking: false));
      await push(event(
          seq: 13, a: 111, b: 100, sawDrinking: false, timestamp: eventTs + 40));
      await push(event(
          seq: 14, a: 100, b: 90, sawDrinking: false, timestamp: eventTs + 90));
      // 中間那一筆重送。
      await push(event(
          seq: 13, a: 111, b: 100, sawDrinking: false, timestamp: eventTs + 40));

      final all = await events();
      expect(all.map((e) => e.fwSeq), [12, 13, 14]);
      expect(all.map((e) => e.ml), [23, 19, 18]);
      expect(all.every((e) => e.status == IntakeStatus.ok), isTrue);
      expect((await repo.dailyTotals(day, day))[day], 60);
      expect(ble.drinkAcks, [12, 13, 14, 13]);
    });

    test('休眠中收到新的事件:照樣寫入並回 ACK,休眠狀態不受影響', () async {
      await boot(firmware: const FirmwareVersion(0, 4, 0));
      await connect();
      ble.pushPacket(const StatePacket(
          activity: CupActivity.dozing, secondsInState: 0, timestamp: 1));
      await settle();
      expect(manager.isDozing(DateTime.now()), isTrue);

      await push(event(sawDrinking: false));
      final e = (await events()).single;
      expect((e.kind, e.status, e.ml), (IntakeKind.drink, IntakeStatus.ok, 23));
      expect(ble.drinkAcks, [12]);
      expect(manager.isDozing(DateTime.now()), isTrue);
    });

    test('同一秒的兩筆不同事件都會存下來(不被 cupId + startedAtMs 唯一鍵擋掉)', () async {
      await boot();
      await connect();
      await push(event(seq: 5));
      await push(event(seq: 6, a: 111, b: 100));

      final all = await events();
      expect(all.map((e) => e.fwSeq), [5, 6]);
      expect(all.map((e) => e.startedAtMs).toSet(), hasLength(2));
      expect(ble.drinkAcks, [5, 6]);
    });

    test('連線還在初始化(尚未 Ready)時收到:不寫入也不回 ACK,等韌體重送', () async {
      await boot();
      ble.statusGate = Completer<void>();
      unawaited(manager.connectTo(_cup));
      await pumpEventQueue();
      expect(manager.state, CupConnectionState.serviceDiscovered);

      await push(event());
      expect(await events(), isEmpty);
      expect(ble.drinkAcks, isEmpty);

      ble.statusGate!.complete();
      await settle();
      expect(manager.state, CupConnectionState.ready);
      await push(event()); // 韌體 2 秒後重送
      expect(await events(), hasLength(1));
      expect(ble.drinkAcks, [12]);
    });

    test('寫入資料庫失敗:不回 ACK(事件留在水杯的 flash,之後會重送)', () async {
      await boot(makeRepo: (db) => _FailingRepo(db, clock: () => now));
      await connect();
      await push(event());

      expect(await events(), isEmpty);
      expect(ble.drinkAcks, isEmpty);
    });
  });

  group('DrinkDetector 開關', () {
    int fill(num ml) => (ml / 350 * WaterPacket.fill25Max).round();

    Future<void> tick(CupPose pose, {bool moving = false, num? ml}) async {
      ble.pushPacket(PosePacket(
          tiltDeciDegrees: 0, pose: pose, moving: moving, timestamp: 1));
      if (ml != null) {
        ble.pushPacket(WaterPacket(fill25: fill(ml), level: 0, timestamp: 1));
      }
      await settle();
      now = now.add(const Duration(seconds: 1));
    }

    Future<void> rest(num ml) async {
      for (var i = 0; i < 5; i++) {
        await tick(CupPose.upright, ml: ml);
      }
    }

    /// 穩定在 200 mL → 拿起來喝 → 放回剩 150 mL。
    Future<void> drinkSequence() async {
      await rest(200);
      await tick(CupPose.tilted, moving: true, ml: 10);
      for (var i = 0; i < 3; i++) {
        await tick(CupPose.drinking, moving: true, ml: 340);
      }
      await tick(CupPose.upright, moving: true, ml: 30);
      await rest(150);
    }

    test('韌體 ≥ 0.3.0:App 不自己偵測,只記韌體送來的事件', () async {
      await boot(firmware: const FirmwareVersion(0, 4, 0));
      await connect();
      expect(recorder.firmwareDetects, isTrue);
      await drinkSequence();
      expect(await events(), isEmpty, reason: 'DrinkDetector 已關閉');

      await push(event());
      final e = (await events()).single;
      expect(e.source, IntakeSource.firmware);
    });

    test('韌體 0.3.0 剛好在門檻上:關閉 App 偵測', () async {
      await boot(firmware: const FirmwareVersion(0, 3, 0));
      await connect();
      await drinkSequence();
      expect(await events(), isEmpty);
    });

    test('韌體 < 0.3.0:維持原行為,由 App 偵測', () async {
      await boot(firmware: const FirmwareVersion(0, 2, 0));
      await connect();
      expect(recorder.firmwareDetects, isFalse);
      await drinkSequence();

      final e = (await events()).single;
      expect(e.source, IntakeSource.appAuto);
      expect(e.ml, 50);
      expect(e.capacityMl, 350);
    });

    test('版本未知但收到 0x07:之後也關閉 App 偵測,避免重複計算', () async {
      await boot(firmware: null);
      await connect();
      expect(recorder.firmwareDetects, isFalse);
      await push(event());
      expect(recorder.firmwareDetects, isTrue);
      await drinkSequence();

      final all = await events();
      expect(all.map((e) => e.source), [IntakeSource.firmware]);
    });

    test('連線後才收到版本(Device Status Notify)→ 立即關閉 App 偵測', () async {
      await boot(firmware: null);
      await connect();
      ble.pushStatus(const DeviceStatus(
          batteryPercent: 70, firmwareVersion: FirmwareVersion(0, 4, 0)));
      await settle();
      expect(recorder.firmwareDetects, isTrue);
      await drinkSequence();
      expect(await events(), isEmpty);
    });
  });

  group('BLE 位址', () {
    test('Device Status 帶 BLE 位址 → 記在 cups.bleAddress', () async {
      await boot(
          firmware: const FirmwareVersion(0, 4, 0),
          bleAddress: '58:E6:C5:12:E0:CE');
      await connect();
      expect((await repo.cup('AA:BB'))?.bleAddress, '58:E6:C5:12:E0:CE');
    });

    test('連上時位址還沒準備好(4 bytes),之後 Notify 才帶位址 → 補記', () async {
      await boot(firmware: const FirmwareVersion(0, 4, 0));
      await connect();
      expect((await repo.cup('AA:BB'))?.bleAddress, isNull);

      ble.pushStatus(const DeviceStatus(
          batteryPercent: 80,
          firmwareVersion: FirmwareVersion(0, 4, 0),
          bleAddress: '58:E6:C5:12:E0:CE'));
      await settle();
      expect((await repo.cup('AA:BB'))?.bleAddress, '58:E6:C5:12:E0:CE');
    });

    test('舊韌體沒有位址 → 維持 null', () async {
      await boot();
      await connect();
      expect((await repo.cup('AA:BB'))?.bleAddress, isNull);
    });
  });
}
