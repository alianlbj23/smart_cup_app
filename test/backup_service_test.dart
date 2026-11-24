import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stut_food_intake_project/data/intake_repository.dart';
import 'package:stut_food_intake_project/services/backup_service.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  var now = DateTime(2026, 11, 23, 15);
  final dbs = <AppDatabase>[];

  Future<IntakeRepository> newRepo() async {
    final db = AppDatabase(NativeDatabase.memory());
    dbs.add(db);
    final repo = IntakeRepository(db, clock: () => now);
    await repo.init();
    return repo;
  }

  setUp(() => now = DateTime(2026, 11, 23, 15));

  tearDown(() async {
    for (final db in dbs) {
      await db.close();
    }
    dbs.clear();
  });

  /// 建立一些紀錄:水杯、各種事件,其中一筆已刪除。
  Future<IntakeRepository> seeded() async {
    final repo = await newRepo();
    await repo.ensureCup('AA:BB', 'SmartCup-1');
    await repo.setCupCapacity('AA:BB', 500);
    await repo.setDailyGoal(2200);
    await repo.addEvent(
      kind: IntakeKind.drink,
      ml: 180,
      startedAt: DateTime(2026, 11, 22, 9, 5),
      endedAt: DateTime(2026, 11, 22, 9, 6),
      cupId: 'AA:BB',
      beforeMl: 400,
      afterMl: 220,
      source: IntakeSource.appAuto,
    );
    await repo.addEvent(
      kind: IntakeKind.refill,
      ml: 300,
      startedAt: DateTime(2026, 11, 22, 10),
    );
    final gone = await repo.addEvent(
      kind: IntakeKind.drink,
      ml: 90,
      startedAt: DateTime(2026, 11, 23, 8),
    );
    await repo.deleteEvent(gone.id);
    await repo.addEvent(
      kind: IntakeKind.drink,
      ml: 120,
      startedAt: DateTime(2026, 11, 23, 11, 30),
      status: IntakeStatus.uncertain,
    );
    return repo;
  }

  group('備份檔', () {
    test('匯出 → 匯入到全新資料庫,事件、水杯與目標完全相同', () async {
      final src = await seeded();
      final json = await exportBackupJson(src, now: now);

      final dst = await newRepo();
      final result = await importBackup(dst, json);

      expect(result.eventsInFile, 4);
      expect(result.eventsChanged, 4);
      expect(result.cupsChanged, 1);
      expect(result.goalChanged, isTrue);
      expect(dst.dailyGoalMl, 2200);
      expect(await dst.allEvents(), await src.allEvents());
      expect(await dst.cups(), await src.cups());
      // 已刪除的事件也有帶過去。
      expect(
        (await dst.allEvents()).where((e) => e.status == IntakeStatus.deleted),
        hasLength(1),
      );
    });

    test('同一個檔案匯入兩次,第二次沒有任何變更', () async {
      final src = await seeded();
      final json = await exportBackupJson(src, now: now);
      final dst = await newRepo();
      await importBackup(dst, json);

      final again = await importBackup(dst, json);
      expect(again.eventsChanged, 0);
      expect(again.cupsChanged, 0);
      expect(again.goalChanged, isFalse);
      expect(again.nothingChanged, isTrue);
      expect(await dst.allEvents(), hasLength(4));
    });

    test('合併:本機較新的修改不會被舊備份蓋掉,本機獨有的紀錄保留', () async {
      final src = await seeded();
      final json = await exportBackupJson(src, now: now);
      final dst = await newRepo();
      await importBackup(dst, json);

      now = now.add(const Duration(hours: 1));
      final first = (await dst.allEvents()).first;
      await dst.updateEvent(first.id, ml: 999);
      await dst.addEvent(
        kind: IntakeKind.drink,
        ml: 50,
        startedAt: DateTime(2026, 11, 23, 16),
      );

      final result = await importBackup(dst, json);
      expect(result.eventsChanged, 0);
      expect((await dst.event(first.id))!.ml, 999);
      expect(await dst.allEvents(), hasLength(5));
    });

    test('JSON 格式含 format/version/exportedAt', () async {
      final src = await seeded();
      final map = jsonDecode(
        await exportBackupJson(src, now: now),
      ) as Map<String, dynamic>;
      expect(map['format'], 'smart_cup_backup');
      expect(map['version'], 1);
      expect(
        DateTime.parse(map['exportedAt'] as String).isAtSameMomentAs(now),
        isTrue,
      );
      expect(map['dailyGoalMl'], 2200);
      expect(map['cups'], hasLength(1));
      expect(map['events'], hasLength(4));

      final parsed = parseBackupJson(jsonEncode(map));
      expect(parsed.exportedAt!.isAtSameMomentAs(now), isTrue);
    });

    test('檔案開頭有 BOM 也能解析', () async {
      final json = buildBackupJson(
        dailyGoalMl: 1500,
        cups: [],
        events: [],
        exportedAt: now,
      );
      expect(parseBackupJson('﻿$json').dailyGoalMl, 1500);
    });

    test('格式錯誤丟出 FormatException 且不改動資料', () async {
      final repo = await newRepo();
      Matcher fails = throwsA(isA<FormatException>());

      expect(() => parseBackupJson('不是 JSON'), fails);
      expect(() => parseBackupJson('[]'), fails);
      expect(() => parseBackupJson('{"format":"other","version":1}'), fails);
      expect(
        () => parseBackupJson(
          '{"format":"smart_cup_backup","version":2,"dailyGoalMl":1500,"cups":[],"events":[]}',
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('較新版本'),
          ),
        ),
      );
      expect(
        () => parseBackupJson(
          '{"format":"smart_cup_backup","version":1,"dailyGoalMl":1500,"cups":[]}',
        ),
        fails,
      );
      expect(
        () => parseBackupJson(
          '{"format":"smart_cup_backup","version":1,"dailyGoalMl":1500,"cups":[],"events":[{"id":"x"}]}',
        ),
        fails,
      );

      // 事件種類是未知的值:整個檔案拒絕,什麼都不寫入。
      final src = await seeded();
      final map = jsonDecode(
        await exportBackupJson(src, now: now),
      ) as Map<String, dynamic>;
      (map['events'] as List).last['kind'] = 'teleport';
      await expectLater(importBackup(repo, jsonEncode(map)), fails);
      expect(await repo.allEvents(), isEmpty);
      expect(await repo.cups(), isEmpty);
      expect(repo.dailyGoalMl, 1500);
    });
  });

  group('CSV', () {
    IntakeEvent event({
      required String id,
      required int startedAtMs,
      int tzOffsetMin = 480,
      IntakeKind kind = IntakeKind.drink,
      int ml = 100,
      IntakeSource source = IntakeSource.manual,
      IntakeStatus status = IntakeStatus.ok,
    }) => IntakeEvent(
      id: id,
      drinkerId: 'me',
      kind: kind,
      ml: ml,
      startedAtMs: startedAtMs,
      tzOffsetMin: tzOffsetMin,
      localDay: '',
      source: source,
      status: status,
      updatedAtMs: 0,
    );

    test('UTF-8 BOM、中文標題、CRLF、依時間排序、排除已刪除', () {
      // 2026-11-23 01:30 UTC = 台灣 09:30。
      final t = DateTime.utc(2026, 11, 23, 1, 30).millisecondsSinceEpoch;
      final csv = buildCsv([
        event(
          id: 'b',
          startedAtMs: t + 3600000,
          kind: IntakeKind.refill,
          ml: 300,
        ),
        event(id: 'a', startedAtMs: t, source: IntakeSource.appAuto),
        event(id: 'x', startedAtMs: t + 60000, status: IntakeStatus.deleted),
        event(
          id: 'c',
          startedAtMs: t + 7200000,
          source: IntakeSource.firmware,
          status: IntakeStatus.uncertain,
        ),
      ]);

      expect(csv.codeUnitAt(0), 0xFEFF);
      expect(utf8.encode(csv).sublist(0, 3), [0xEF, 0xBB, 0xBF]);
      final lines = csv.substring(1).split('\r\n');
      expect(lines, [
        '日期,時間,種類,水量(mL),來源,狀態',
        '2026-11-23,09:30,喝水,100,自動偵測,正常',
        '2026-11-23,10:30,加水,300,手動輸入,正常',
        '2026-11-23,11:30,喝水,100,水杯補傳,待確認',
        '',
      ]);
      expect(csv, isNot(contains('已刪除')));
    });

    test('依事件自己的時區顯示日期與時間', () {
      // 2026-11-23 20:00 UTC:台灣(+8)是 11/24 04:00,紐約(-5)是 11/23 15:00。
      final t = DateTime.utc(2026, 11, 23, 20).millisecondsSinceEpoch;
      final csv = buildCsv([
        event(id: 'tw', startedAtMs: t, tzOffsetMin: 480),
        event(id: 'ny', startedAtMs: t + 1, tzOffsetMin: -300),
      ]);
      final lines = csv.substring(1).split('\r\n');
      expect(lines[1], startsWith('2026-11-24,04:00,'));
      expect(lines[2], startsWith('2026-11-23,15:00,'));
    });

    test('只有標題的空 CSV', () {
      expect(buildCsv([]), '﻿日期,時間,種類,水量(mL),來源,狀態\r\n');
    });

    test('欄位跳脫', () {
      expect(csvEscape('plain'), 'plain');
      expect(csvEscape('a,b'), '"a,b"');
      expect(csvEscape('他說"好"'), '"他說""好"""');
      expect(csvEscape('兩\n行'), '"兩\n行"');
      expect(csvEscape('a\rb'), '"a\rb"');
      expect(csvEscape(''), '');
    });
  });

  test('預設檔名', () {
    expect(
      backupFileName(DateTime(2026, 11, 3)),
      'smart_cup_backup_2026-11-03.json',
    );
    expect(csvFileName(DateTime(2026, 11, 23)), 'smart_cup_紀錄_2026-11-23.csv');
  });
}
