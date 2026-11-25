import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stut_food_intake_project/data/intake_repository.dart';

/// schema 1(App 1.0.0)建立的資料表,從 1.0.0 的 sqlite_master 照抄。
const _schemaV1 = [
  'CREATE TABLE "cups" ("id" TEXT NOT NULL, "name" TEXT NOT NULL, '
      '"capacity_ml" INTEGER NOT NULL DEFAULT 350, "created_at_ms" INTEGER NOT NULL, '
      '"updated_at_ms" INTEGER NOT NULL, PRIMARY KEY ("id"))',
  'CREATE TABLE "drinkers" ("id" TEXT NOT NULL, "name" TEXT NOT NULL, '
      '"daily_goal_ml" INTEGER NOT NULL DEFAULT 1500, "updated_at_ms" INTEGER NOT NULL, '
      'PRIMARY KEY ("id"))',
  'CREATE TABLE "intake_events" ("id" TEXT NOT NULL, '
      '"drinker_id" TEXT NOT NULL REFERENCES drinkers (id), "cup_id" TEXT NULL, '
      '"kind" TEXT NOT NULL, "ml" INTEGER NOT NULL, "started_at_ms" INTEGER NOT NULL, '
      '"ended_at_ms" INTEGER NULL, "tz_offset_min" INTEGER NOT NULL, '
      '"local_day" TEXT NOT NULL, "before_ml" INTEGER NULL, "after_ml" INTEGER NULL, '
      '"source" TEXT NOT NULL, "status" TEXT NOT NULL DEFAULT \'ok\', '
      '"updated_at_ms" INTEGER NOT NULL, PRIMARY KEY ("id"), '
      'UNIQUE ("cup_id", "started_at_ms"))',
  'CREATE INDEX idx_intake_day ON intake_events (drinker_id, local_day)',
  'CREATE INDEX idx_intake_time ON intake_events (drinker_id, started_at_ms)',
];

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('schema 1 → 2:舊資料保留,新欄位為預設值,去重索引可用', () async {
    final startedAtMs = DateTime(2026, 11, 20, 8).millisecondsSinceEpoch;
    final db = AppDatabase(NativeDatabase.memory(setup: (raw) {
      for (final sql in _schemaV1) {
        raw.execute(sql);
      }
      raw.execute("INSERT INTO cups VALUES ('AA:BB', 'SmartCup-E0CE', 420, 1, 2)");
      raw.execute("INSERT INTO drinkers VALUES ('me', '我', 1800, 3)");
      raw.execute(
        'INSERT INTO intake_events (id, drinker_id, cup_id, kind, ml, started_at_ms, '
        'tz_offset_min, local_day, before_ml, after_ml, source, status, updated_at_ms) '
        "VALUES ('e1', 'me', 'AA:BB', 'drink', 120, $startedAtMs, 480, '2026-11-20', "
        "300, 180, 'appAuto', 'uncertain', 9)",
      );
      raw.execute('PRAGMA user_version = 1');
    }));
    addTearDown(db.close);
    final repo = IntakeRepository(db);
    await repo.init();

    expect(db.schemaVersion, 2);
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data.values.single, 2);

    // 舊資料原封不動。
    final cup = (await repo.cup('AA:BB'))!;
    expect((cup.name, cup.capacityMl, cup.bleAddress),
        ('SmartCup-E0CE', 420, null));
    expect(repo.dailyGoalMl, 1800);
    expect(repo.goalFromServer, isFalse);
    expect(repo.goalMl, 1800, reason: '未連結:維持單機版的目標');
    final e = (await repo.allEvents()).single;
    expect((e.id, e.ml, e.kind, e.source, e.status, e.beforeMl, e.afterMl),
        ('e1', 120, IntakeKind.drink, IntakeSource.appAuto, IntakeStatus.uncertain, 300, 180));
    // 新欄位。
    expect(
      [
        e.capacityMl, e.levelBeforePct, e.levelAfterPct, e.timeEstimated,
        e.sawDrinking, e.tooLong, e.fwSeq, e.fwKey, e.syncedAtMs, e.syncError,
        e.syncExcluded,
      ],
      everyElement(isNull),
    );

    // 新的去重索引存在,而且真的擋得住重複。
    final first = await repo.addFirmwareEvent(
      cupId: 'AA:BB',
      dedupKey: '1:100:124:111',
      kind: IntakeKind.drink,
      ml: 27,
      startedAt: DateTime(2026, 11, 21, 8),
      timeEstimated: false,
      capacityMl: 420,
      levelBeforePct: 62,
      levelAfterPct: 55.5,
      sawDrinking: true,
      tooLong: false,
      seq: 1,
    );
    expect(first.created, isTrue);
    await expectLater(
      db.customStatement(
        'INSERT INTO intake_events (id, drinker_id, cup_id, kind, ml, started_at_ms, '
        'tz_offset_min, local_day, source, updated_at_ms, fw_key) '
        "VALUES ('dup', 'me', 'AA:BB', 'drink', 1, 5, 480, '2026-11-21', 'firmware', 1, "
        "'1:100:124:111')",
      ),
      throwsA(anything),
    );
  });

  test('全新安裝直接是 schema 2', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = IntakeRepository(db);
    await repo.init();
    final indexes = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'index'")
        .get();
    expect(indexes.map((r) => r.read<String>('name')), contains('idx_intake_fw'));
  });
}
