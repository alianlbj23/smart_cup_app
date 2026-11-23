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
const _other =
    BleDeviceInfo(deviceId: 'CC:DD', deviceName: 'SmartCup2', rssi: -40);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late FakeBleService ble;
  late CupConnectionManager manager;
  late AppDatabase db;
  late IntakeRepository repo;
  late IntakeRecorder recorder;
  late DateTime now;
  final day = DateTime(2026, 11, 23);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    now = DateTime(2026, 11, 23, 9);
    ble = FakeBleService()..devicesInRange = [_cup, _other];
    manager = CupConnectionManager(ble: ble, store: DeviceStore());
    db = AppDatabase(NativeDatabase.memory());
    repo = IntakeRepository(db, clock: () => now);
    await repo.init();
    recorder = IntakeRecorder(manager: manager, repo: repo, clock: () => now);
    recorder.start();
  });

  tearDown(() async {
    recorder.dispose();
    manager.dispose();
    ble.dispose();
    await db.close();
  });

  Future<void> settle() async {
    await pumpEventQueue();
    await recorder.flush();
  }

  Future<void> connect(BleDeviceInfo d) async {
    await manager.connectTo(d);
    await settle();
    expect(manager.state, CupConnectionState.ready);
  }

  int fill(num ml, {int capacity = 350}) =>
      (ml / capacity * WaterPacket.fill25Max).round();

  /// 過一秒:送一筆 POSE 與(可選的)WATER。
  Future<void> tick(CupPose pose,
      {bool moving = false, num? ml, int capacity = 350}) async {
    ble.pushPacket(PosePacket(
        tiltDeciDegrees: 0, pose: pose, moving: moving, timestamp: 1));
    if (ml != null) {
      ble.pushPacket(
          WaterPacket(fill25: fill(ml, capacity: capacity), level: 0, timestamp: 1));
    }
    await settle();
    now = now.add(const Duration(seconds: 1));
  }

  Future<void> rest(num ml, {int capacity = 350}) async {
    for (var i = 0; i < 5; i++) {
      await tick(CupPose.upright, ml: ml, capacity: capacity);
    }
  }

  Future<void> sip() async {
    await tick(CupPose.tilted, moving: true, ml: 10);
    for (var i = 0; i < 3; i++) {
      await tick(CupPose.drinking, moving: true, ml: 340);
    }
    await tick(CupPose.upright, moving: true, ml: 30);
  }

  test('manager.packets:連線中的封包(含 ATTITUDE / STATE)都會送出,未連線不送', () async {
    final got = <CupDataPacket>[];
    final sub = manager.packets.listen(got.add);
    ble.pushPacket(const WaterPacket(fill25: 1, level: 0, timestamp: 1));
    await settle();
    expect(got, isEmpty);

    await connect(_cup);
    const att = AttitudePacket(
        pitchDeciDegrees: 0, rollDeciDegrees: 0, timestamp: 1);
    const state =
        StatePacket(activity: CupActivity.active, secondsInState: 0, timestamp: 1);
    ble.pushPacket(att);
    ble.pushPacket(state);
    ble.pushPacket(state); // keepalive 也會送出
    await settle();
    expect(got, [att, state, state]);
    await sub.cancel();
  });

  test('連線 → 穩定 → 喝一口 → 資料庫多一筆 appAuto 喝水,帶 cupId', () async {
    await connect(_cup);
    final cup = await repo.cup('AA:BB');
    expect(cup?.name, 'SmartCup');
    expect(recorder.cupId, 'AA:BB');

    await rest(200);
    final liftAt = now;
    await sip();
    await rest(150);

    final events = await repo.eventsOnDay(day);
    expect(events, hasLength(1));
    final e = events.single;
    expect(e.cupId, 'AA:BB');
    expect(e.kind, IntakeKind.drink);
    expect(e.source, IntakeSource.appAuto);
    expect(e.status, IntakeStatus.ok);
    expect(e.ml, 50);
    expect(e.beforeMl, 200);
    expect(e.afterMl, 150);
    expect(e.startedAt, liftAt, reason: '用封包到達手機的時間,不是韌體時間戳');
    expect(e.endedAt, isNotNull);
    expect((await repo.dailyTotals(day, day))[day], 50);
  });

  test('加水也會記錄(refill),不計入飲水量', () async {
    await connect(_cup);
    await rest(50);
    await tick(CupPose.upright, moving: true, ml: 1);
    await tick(CupPose.tilted, moving: true, ml: 1);
    await rest(300);

    final e = (await repo.eventsOnDay(day)).single;
    expect(e.kind, IntakeKind.refill);
    expect(e.ml, 250);
    expect((await repo.dailyTotals(day, day))[day], 0);
  });

  test('使用水杯設定的容量,修改容量後立即生效', () async {
    await connect(_cup);
    await repo.setCupCapacity('AA:BB', 500);
    await settle();
    expect(recorder.detector.capacityMl, 500);

    await rest(400, capacity: 500);
    await sip();
    await rest(300, capacity: 500);

    final e = (await repo.eventsOnDay(day)).single;
    expect(e.ml, 100);
    expect(e.beforeMl, 400);
  });

  test('已存在的水杯沿用資料庫裡的容量', () async {
    await repo.ensureCup('AA:BB', 'SmartCup');
    await repo.setCupCapacity('AA:BB', 700);
    await connect(_cup);
    expect(recorder.detector.capacityMl, 700);
  });

  test('喝到一半斷線 → 同一杯重連後與斷線前比較,標為 uncertain', () async {
    await connect(_cup);
    await rest(300);
    await tick(CupPose.drinking, moving: true, ml: 340);

    ble.dropLink(); // 意外斷線 → manager 自動重連
    await settle();
    expect(manager.state, CupConnectionState.ready);
    expect(recorder.cupId, 'AA:BB');

    await rest(220);
    final e = (await repo.eventsOnDay(day)).single;
    expect(e.kind, IntakeKind.drink);
    expect(e.status, IntakeStatus.uncertain);
    expect(e.ml, 80);
  });

  test('換成另一個水杯 → 完全重設,不拿前一杯的水位比較', () async {
    await connect(_cup);
    await rest(300);
    await manager.disconnect();
    await settle();
    expect(recorder.cupId, isNull);

    await connect(_other);
    expect(recorder.cupId, 'CC:DD');
    await rest(100);
    expect(await repo.eventsOnDay(day), isEmpty);

    await sip();
    await rest(60);
    final e = (await repo.eventsOnDay(day)).single;
    expect(e.cupId, 'CC:DD');
    expect(e.ml, 40);
  });

  test('dispose 後不再記錄', () async {
    await connect(_cup);
    await rest(200);
    recorder.dispose();
    await sip();
    await rest(100);
    expect(await repo.eventsOnDay(day), isEmpty);
  });
}
