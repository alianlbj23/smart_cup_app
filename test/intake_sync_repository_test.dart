import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stut_food_intake_project/data/intake_repository.dart';
import 'package:stut_food_intake_project/services/backup_service.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late IntakeRepository repo;
  late DateTime now;
  final t0 = DateTime(2026, 11, 23, 9);

  setUp(() async {
    now = t0;
    db = AppDatabase(NativeDatabase.memory());
    repo = IntakeRepository(db, clock: () => now);
    await repo.init();
  });

  tearDown(() => db.close());

  Future<IntakeEvent> add({String? cupId, int ml = 100, DateTime? at}) =>
      repo.addEvent(
        kind: IntakeKind.drink,
        ml: ml,
        startedAt: at ?? now,
        cupId: cupId,
        source: cupId == null ? IntakeSource.manual : IntakeSource.appAuto,
      );

  Future<List<String>> pending({String cup = 'AA', int limit = 200}) async => [
        for (final e in await repo.pendingSyncEvents(cupId: cup, limit: limit))
          e.id,
      ];

  group('每日目標', () {
    test('未連結:目標是本機設定,可以修改', () async {
      expect(repo.goalFromServer, isFalse);
      expect(repo.goalMl, 1500);
      await repo.setDailyGoal(1800);
      expect(repo.goalMl, 1800);
    });

    test('已連結:以 Server 的值更新 drinkers.daily_goal_ml', () async {
      var notified = 0;
      repo.addListener(() => notified++);
      await repo.applyServerGoal(2100);

      expect(repo.goalFromServer, isTrue);
      expect(repo.goalMl, 2100);
      expect(repo.dailyGoalMl, 2100);
      expect(notified, 1);
      // 重新開啟(另一個 repository 讀同一個資料庫)仍然記得。
      final again = IntakeRepository(db);
      await again.init();
      expect((again.goalFromServer, again.goalMl), (true, 2100));
      // 值沒變就不通知。
      await repo.applyServerGoal(2100);
      expect(notified, 1);
    });

    test('已連結但 Server 回 null:沒有目標,不套用預設值也不沿用本機的值', () async {
      await repo.setDailyGoal(1800);
      await repo.applyServerGoal(null);

      expect(repo.goalFromServer, isTrue);
      expect(repo.goalMl, isNull);
      // Server 先有目標、後來變成 null 也一樣。
      await repo.applyServerGoal(2000);
      await repo.applyServerGoal(null);
      expect(repo.goalMl, isNull);
    });

    test('已連結時不能在 App 修改目標', () async {
      await repo.applyServerGoal(2000);
      await expectLater(repo.setDailyGoal(900), throwsStateError);
      expect(repo.goalMl, 2000);
    });

    test('Server 的目標不是正整數 → 拒絕', () async {
      await expectLater(repo.applyServerGoal(0), throwsArgumentError);
      await expectLater(repo.applyServerGoal(-5), throwsArgumentError);
      expect(repo.goalFromServer, isFalse);
    });

    test('解除連結:回到單機行為,目標可以再修改', () async {
      await repo.setDailyGoal(1800);
      await repo.applyServerGoal(null);
      await repo.clearServerGoal();
      expect(repo.goalFromServer, isFalse);
      expect(repo.goalMl, 1800, reason: 'Server 沒設定過目標 → 本機原本的值');

      await repo.applyServerGoal(2200);
      await repo.clearServerGoal();
      expect(repo.goalMl, 2200, reason: 'Server 設定過 → 留著最後的值');
      await repo.setDailyGoal(1600);
      expect(repo.goalMl, 1600);
    });

    test('已連結時匯入備份檔:不改每日目標', () async {
      await repo.applyServerGoal(2000);
      final json = buildBackupJson(
          dailyGoalMl: 900, cups: const [], events: const [], exportedAt: now);
      final r = await importBackup(repo, json);
      expect(r.goalChanged, isFalse);
      expect(repo.goalMl, 2000);
    });
  });

  group('同步狀態', () {
    test('新事件待同步;標成已同步後不再出現', () async {
      final a = await add(cupId: 'AA');
      now = now.add(const Duration(seconds: 1));
      final b = await add();
      expect(await pending(), [a.id, b.id], reason: '依 updatedAtMs 由舊到新');
      expect(await repo.pendingSyncCount(cupId: 'AA'), 2);

      now = now.add(const Duration(seconds: 5));
      final n = await repo.markSynced(
          [(id: a.id, updatedAtMs: a.updatedAtMs)]);
      expect(n, 1);
      expect(await pending(), [b.id]);
      expect((await repo.event(a.id))!.syncedAtMs, now.millisecondsSinceEpoch);
    });

    test('修改、刪除已同步的事件 → 再次待同步,updatedAtMs 一定變大', () async {
      final a = await add(cupId: 'AA');
      await repo.markSynced([(id: a.id, updatedAtMs: a.updatedAtMs)]);
      expect(await pending(), isEmpty);

      // 同一毫秒內修改:updatedAtMs 仍然要比上一版大,Server 才會更新。
      await repo.updateEvent(a.id, ml: 150);
      final edited = (await repo.event(a.id))!;
      expect(edited.updatedAtMs, greaterThan(a.updatedAtMs));
      expect(edited.syncedAtMs, isNull);
      expect(await pending(), [a.id]);

      await repo.markSynced([(id: a.id, updatedAtMs: edited.updatedAtMs)]);
      await repo.deleteEvent(a.id);
      final deleted = (await repo.event(a.id))!;
      expect(deleted.status, IntakeStatus.deleted);
      expect(deleted.updatedAtMs, greaterThan(edited.updatedAtMs));
      expect(await pending(), [a.id], reason: '軟刪除也要上傳');
    });

    test('上傳途中事件又被修改:舊版本的「已同步」不算數', () async {
      final a = await add(cupId: 'AA');
      await repo.updateEvent(a.id, ml: 999);
      final n = await repo.markSynced(
          [(id: a.id, updatedAtMs: a.updatedAtMs)]);
      expect(n, 0);
      expect(await pending(), [a.id]);
    });

    test('其他水杯的紀錄不上傳;手動紀錄會上傳', () async {
      final mine = await add(cupId: 'AA');
      now = now.add(const Duration(minutes: 1));
      final other = await add(cupId: 'CC');
      now = now.add(const Duration(minutes: 1));
      final manual = await add();

      expect(await pending(), [mine.id, manual.id]);
      expect(await repo.pendingSyncCount(cupId: 'AA'), 2);
      expect(await pending(cup: 'CC'), [other.id, manual.id]);
    });

    test('excludeAllFromSync:現有的紀錄(已同步、未同步、被拒收)全部標成不需同步,'
        '之後修改也不會重新排入;新的紀錄不受影響', () async {
      final synced = await add(cupId: 'AA');
      await repo.markSynced([(id: synced.id, updatedAtMs: synced.updatedAtMs)]);
      now = now.add(const Duration(seconds: 1));
      final unsynced = await add();
      final rejected = await add(cupId: 'AA');
      await repo.markSyncRejected(rejected.id, rejected.updatedAtMs, 'INVALID_EVENT');
      var notified = 0;
      repo.addListener(() => notified++);

      expect(await repo.excludeAllFromSync(), 3);
      expect(notified, 0);
      expect(await pending(), isEmpty);
      expect(await repo.pendingSyncCount(cupId: 'AA'), 0);
      for (final id in [synced.id, unsynced.id, rejected.id]) {
        expect((await repo.event(id))!.syncExcluded, isTrue);
      }
      // 再標一次:沒有新的要標。
      expect(await repo.excludeAllFromSync(), 0);

      now = now.add(const Duration(seconds: 1));
      await repo.updateEvent(synced.id, ml: 1);
      await repo.deleteEvent(unsynced.id);
      await repo.updateEvent(rejected.id, ml: 2);
      expect(await pending(), isEmpty);

      final fresh = await add(cupId: 'AA');
      expect(await pending(), [fresh.id]);
    });

    test('limit:一次最多取指定筆數', () async {
      for (var i = 0; i < 5; i++) {
        now = now.add(const Duration(seconds: 1));
        await add();
      }
      expect(await pending(limit: 3), hasLength(3));
      expect(await pending(), hasLength(5));
    });

    test('被 Server 拒收的事件移出佇列;再修改後重新排入', () async {
      final a = await add(cupId: 'AA');
      final b = await add();
      await repo.markSyncRejected(a.id, a.updatedAtMs, 'INVALID_EVENT:ml 超出範圍');
      expect(await pending(), [b.id]);
      expect((await repo.event(a.id))!.syncError, 'INVALID_EVENT:ml 超出範圍');

      await repo.updateEvent(a.id, ml: 50);
      expect((await repo.event(a.id))!.syncError, isNull);
      expect(await pending(), containsAll([a.id, b.id]));
    });

    test('標記同步狀態不會通知 UI 重新整理(避免同步 → 通知 → 再同步的迴圈)', () async {
      final a = await add(cupId: 'AA');
      var notified = 0;
      repo.addListener(() => notified++);
      await repo.markSynced([(id: a.id, updatedAtMs: a.updatedAtMs)]);
      await repo.markSyncRejected(a.id, a.updatedAtMs, 'x');
      expect(notified, 0);
    });

    test('匯入備份檔:匯入的紀錄不上傳(不知道是誰的、也可能早就由另一台上傳過)', () async {
      final a = await add(cupId: 'AA');
      await repo.markSynced([(id: a.id, updatedAtMs: a.updatedAtMs)]);
      final synced = (await repo.event(a.id))!;
      final fromOtherPhone = synced.copyWith(
          id: 'imported', startedAtMs: synced.startedAtMs + 1000);
      expect(await repo.importEvents([fromOtherPhone]), 1);
      final imported = (await repo.event('imported'))!;
      expect(imported.syncedAtMs, isNull, reason: '別台裝置的同步狀態不沿用');
      expect(imported.syncExcluded, isTrue);
      expect(await pending(), isEmpty);
    });

    test('匯入備份檔:本機已有的紀錄被較新的版本取代 → 維持原本要不要上傳的設定', () async {
      final a = await add(cupId: 'AA');
      await repo.markSynced([(id: a.id, updatedAtMs: a.updatedAtMs)]);
      final newer = (await repo.event(a.id))!
          .copyWith(ml: 300, updatedAtMs: a.updatedAtMs + 5);
      expect(await repo.importEvents([newer]), 1);
      expect(await pending(), [a.id], reason: '這台上傳過的紀錄有新版本 → 重新上傳');

      await repo.excludeAllFromSync();
      final newest = newer.copyWith(ml: 400, updatedAtMs: a.updatedAtMs + 9);
      expect(await repo.importEvents([newest]), 1);
      expect(await pending(), isEmpty);
    });

    test('schema 1 的備份檔(沒有新欄位)仍可匯入', () async {
      const v1 = '{"format":"smart_cup_backup","version":1,"dailyGoalMl":1500,'
          '"cups":[{"id":"AA","name":"SmartCup","capacityMl":350,'
          '"createdAtMs":1,"updatedAtMs":1}],'
          '"events":[{"id":"old-1","drinkerId":"me","cupId":"AA","kind":"drink",'
          '"ml":120,"startedAtMs":1795000000000,"endedAtMs":null,"tzOffsetMin":480,'
          '"localDay":"2026-11-18","beforeMl":300,"afterMl":180,"source":"appAuto",'
          '"status":"ok","updatedAtMs":1795000001000}]}';
      final r = await importBackup(repo, v1);
      expect(r.eventsChanged, 1);
      final e = (await repo.event('old-1'))!;
      expect((e.ml, e.timeEstimated, e.fwKey, e.syncedAtMs), (120, null, null, null));
      expect((await repo.cup('AA'))!.bleAddress, isNull);
    });
  });

  group('水杯的 BLE 位址', () {
    test('setCupBleAddress', () async {
      await repo.ensureCup('AA', 'SmartCup');
      await repo.setCupBleAddress('AA', '58:E6:C5:12:E0:CE');
      expect((await repo.cup('AA'))!.bleAddress, '58:E6:C5:12:E0:CE');
    });
  });
}
