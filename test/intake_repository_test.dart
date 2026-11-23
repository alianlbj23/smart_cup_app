import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stut_food_intake_project/data/intake_repository.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late IntakeRepository repo;
  var now = DateTime(2026, 11, 23, 15);

  setUp(() async {
    now = DateTime(2026, 11, 23, 15);
    db = AppDatabase(NativeDatabase.memory());
    repo = IntakeRepository(db, clock: () => now);
    await repo.init();
  });

  tearDown(() => db.close());

  test('init 建立預設飲用者,目標 1500 mL,可修改', () async {
    expect(repo.dailyGoalMl, 1500);
    await repo.setDailyGoal(1800);
    expect(repo.dailyGoalMl, 1800);
    await repo.init(); // 重複 init 不覆蓋
    expect(repo.dailyGoalMl, 1800);
  });

  test('ensureCup 第一次建立預設容量,之後只更新名稱', () async {
    final c = await repo.ensureCup('AA', 'SmartCup-1');
    expect(c.capacityMl, 350);
    await repo.setCupCapacity('AA', 500);
    final c2 = await repo.ensureCup('AA', 'SmartCup-2');
    expect(c2.capacityMl, 500);
    expect(c2.name, 'SmartCup-2');
  });

  test('dailyTotals 只算正常的喝水,空白日為 0', () async {
    await repo.addEvent(
        kind: IntakeKind.drink, ml: 200, startedAt: DateTime(2026, 11, 21, 9));
    await repo.addEvent(
        kind: IntakeKind.drink, ml: 150, startedAt: DateTime(2026, 11, 23, 8));
    await repo.addEvent(
        kind: IntakeKind.drink, ml: 100, startedAt: DateTime(2026, 11, 23, 23, 59));
    await repo.addEvent(
        kind: IntakeKind.refill, ml: 300, startedAt: DateTime(2026, 11, 23, 10));
    await repo.addEvent(
        kind: IntakeKind.drink,
        ml: 80,
        startedAt: DateTime(2026, 11, 23, 11),
        status: IntakeStatus.uncertain);
    final deleted = await repo.addEvent(
        kind: IntakeKind.drink, ml: 999, startedAt: DateTime(2026, 11, 23, 12));
    await repo.deleteEvent(deleted.id);

    final totals =
        await repo.dailyTotals(DateTime(2026, 11, 20), DateTime(2026, 11, 23));
    expect(totals, {
      DateTime(2026, 11, 20): 0,
      DateTime(2026, 11, 21): 200,
      DateTime(2026, 11, 22): 0,
      DateTime(2026, 11, 23): 250,
    });

    final today = await repo.eventsOnDay(DateTime(2026, 11, 23));
    expect(today.map((e) => e.ml), [150, 300, 80, 100]); // 依時間、不含已刪除
  });

  test('updateEvent 改時間會換日期', () async {
    final e = await repo.addEvent(
        kind: IntakeKind.drink, ml: 200, startedAt: DateTime(2026, 11, 23, 9));
    await repo.updateEvent(e.id, startedAt: DateTime(2026, 11, 22, 21), ml: 250);
    final moved = (await repo.event(e.id))!;
    expect(moved.localDay, '2026-11-22');
    expect(moved.ml, 250);
    expect(moved.startedAt, DateTime(2026, 11, 22, 21));
  });

  test('importEvents 依 id 合併,較新的 updatedAt 為準,同杯同時間去重', () async {
    final e = await repo.addEvent(
        kind: IntakeKind.drink,
        ml: 200,
        startedAt: DateTime(2026, 11, 23, 9),
        cupId: 'AA',
        source: IntakeSource.appAuto);
    final older = e.copyWith(ml: 1, updatedAtMs: e.updatedAtMs - 1);
    final newer = e.copyWith(ml: 300, updatedAtMs: e.updatedAtMs + 1);
    final dupSameCupTime = e.copyWith(id: 'other-id');
    final fresh = e.copyWith(
        id: 'new-id', startedAtMs: e.startedAtMs + 60000, ml: 50);

    expect(await repo.importEvents([older]), 0);
    expect(await repo.importEvents([newer, dupSameCupTime, fresh]), 2);
    final all = await repo.allEvents();
    expect(all.map((x) => (x.id, x.ml)), [(e.id, 300), ('new-id', 50)]);
  });
}
