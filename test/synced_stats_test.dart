import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stut_food_intake_project/data/intake_repository.dart';
import 'package:stut_food_intake_project/ui/stats_page.dart';
import 'package:stut_food_intake_project/ui/theme.dart';

/// 已連結照護系統時,App 的統計只算會上傳的紀錄,數字才會和照護系統一致。
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final now = DateTime(2026, 11, 26, 23);
  final today = DateTime(2026, 11, 26);
  late AppDatabase db;
  late IntakeRepository repo;

  Future<void> drink(DateTime t, int ml) => repo.addEvent(
      kind: IntakeKind.drink,
      ml: ml,
      startedAt: t,
      source: IntakeSource.appAuto);

  /// 連結到住民:原有的紀錄標成不上傳,目標改以 Server 為準。
  Future<void> link() async {
    await repo.excludeAllFromSync();
    await repo.applyServerGoal(1500);
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = IntakeRepository(db, clock: () => now);
    await repo.init();
    // 連結之前:今天 6,266 mL、昨天 300 mL
    await drink(DateTime(2026, 11, 26, 14, 30), 3000);
    await drink(DateTime(2026, 11, 26, 15), 3266);
    await drink(DateTime(2026, 11, 25, 9), 300);
  });

  tearDown(() => db.close());

  test('dailyIntake:每天的喝水量與筆數,和 dailyTotals 是同一個數字', () async {
    await repo.addEvent(
        kind: IntakeKind.refill,
        ml: 300,
        startedAt: DateTime(2026, 11, 26, 16),
        source: IntakeSource.appAuto);
    await repo.addEvent(
        kind: IntakeKind.drink,
        ml: 999,
        startedAt: DateTime(2026, 11, 26, 17),
        source: IntakeSource.appAuto,
        status: IntakeStatus.uncertain);
    final from = DateTime(2026, 11, 24);
    final to = DateTime(2026, 11, 26);
    final intake = await repo.dailyIntake(from, to);
    expect({for (final e in intake.entries) dayKey(e.key): (e.value.ml, e.value.count)}, {
      '2026-11-24': (0, 0),
      '2026-11-25': (300, 1),
      '2026-11-26': (6266, 2),
    });
    final totals = await repo.dailyTotals(from, to);
    expect({for (final e in intake.entries) e.key: e.value.ml}, totals);

    await link(); // 連結之後,原有的紀錄不算
    expect((await repo.dailyIntake(to, to))[to], (ml: 0, count: 0));
  });

  group('IntakeRepository', () {
    test('還沒連結:所有紀錄都算', () async {
      expect(repo.linkedToCare, isFalse);
      expect(await repo.eventsOnDay(today), hasLength(2));
      expect((await repo.dailyTotals(today, today))[today], 6266);
      expect(await repo.hiddenBeforeLinkCount(today, today), 0);
    });

    test('已連結:連結之前的紀錄不計入、不列出;之後的照常', () async {
      await link();
      await drink(DateTime(2026, 11, 26, 21), 608);
      await drink(DateTime(2026, 11, 26, 23), 240);

      expect(repo.linkedToCare, isTrue);
      final events = await repo.eventsOnDay(today);
      expect(events.map((e) => e.ml), [608, 240]);
      expect((await repo.dailyTotals(today, today))[today], 848);
      // 週、月的每日總量也一樣
      final yesterday = DateTime(2026, 11, 25);
      final totals = await repo.dailyTotals(yesterday, today);
      expect(totals[yesterday], 0);
      expect(totals[today], 848);
    });

    test('已連結:回報有幾筆連結前的紀錄沒有計入', () async {
      await link();
      await drink(DateTime(2026, 11, 26, 21), 608);

      expect(await repo.hiddenBeforeLinkCount(today, today), 2);
      expect(
          await repo.hiddenBeforeLinkCount(DateTime(2026, 11, 25), today), 3);
      expect(
          await repo.hiddenBeforeLinkCount(
              DateTime(2026, 11, 20), DateTime(2026, 11, 21)),
          0);
    });

    test('連結前的紀錄沒有被刪掉:備份、CSV 用的 allEvents 仍然有', () async {
      await link();

      expect(await repo.allEvents(), hasLength(3));
    });

    test('解除連結:連結前的紀錄又算回來', () async {
      await link();
      await drink(DateTime(2026, 11, 26, 21), 608);
      await repo.clearServerGoal();

      expect(repo.linkedToCare, isFalse);
      expect(await repo.eventsOnDay(today), hasLength(3));
      expect((await repo.dailyTotals(today, today))[today], 6874);
      expect(await repo.hiddenBeforeLinkCount(today, today), 0);
    });
  });

  group('統計頁', () {
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    Future<void> pumpPage(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: StatsPage(repo: repo, clock: () => now)),
      ));
      await settle(tester);
    }

    testWidgets('已連結:今日總量只算連結後的,並說明有幾筆沒計入', (tester) async {
      await link();
      await drink(DateTime(2026, 11, 26, 21), 608);
      await drink(DateTime(2026, 11, 26, 23), 240);
      await pumpPage(tester);

      expect(find.textContaining('848'), findsWidgets);
      expect(find.textContaining('7,114'), findsNothing);
      expect(find.textContaining('6,266'), findsNothing);
      expect(find.text('連結照護系統之前的 2 筆紀錄不計入'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('還沒連結:照常顯示全部,沒有說明', (tester) async {
      await pumpPage(tester);

      expect(find.textContaining('6,266'), findsWidgets);
      expect(find.textContaining('不計入'), findsNothing);
    });

    testWidgets('已連結但沒有連結前的紀錄:沒有說明', (tester) async {
      await link();
      await drink(DateTime(2026, 11, 26, 21), 608);
      await pumpPage(tester);
      // 換到沒有紀錄的日子
      await tester.tap(find.byIcon(Icons.chevron_left));
      await settle(tester);
      await tester.tap(find.byIcon(Icons.chevron_left));
      await settle(tester);

      expect(find.textContaining('不計入'), findsNothing);
    });
  });
}
