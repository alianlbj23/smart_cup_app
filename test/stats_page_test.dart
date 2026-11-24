import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stut_food_intake_project/data/intake_repository.dart';
import 'package:stut_food_intake_project/ui/stats_page.dart';
import 'package:stut_food_intake_project/ui/theme.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  // 2026-11-23 是週一。
  final now = DateTime(2026, 11, 23, 15);
  late AppDatabase db;
  late IntakeRepository repo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = IntakeRepository(db, clock: () => now);
    await repo.init();
    Future<void> add(DateTime t, int ml,
            {IntakeKind kind = IntakeKind.drink,
            IntakeStatus status = IntakeStatus.ok,
            IntakeSource source = IntakeSource.appAuto}) =>
        repo.addEvent(
            kind: kind, ml: ml, startedAt: t, source: source, status: status);
    // 今天:正常喝水 750,另有加水與待確認各一筆(不計入)。
    await add(DateTime(2026, 11, 23, 7, 30), 250);
    await add(DateTime(2026, 11, 23, 9), 200, source: IntakeSource.manual);
    await add(DateTime(2026, 11, 23, 10), 300, kind: IntakeKind.refill);
    await add(DateTime(2026, 11, 23, 13), 300);
    await add(DateTime(2026, 11, 23, 13, 40), 80,
        status: IntakeStatus.uncertain);
    // 上週:兩天達標。
    await add(DateTime(2026, 11, 17, 12), 1500);
    await add(DateTime(2026, 11, 20, 12), 1600);
  });

  tearDown(() => db.close());

  /// 讓真正的資料庫查詢跑完,再重建畫面。
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: StatsPage(repo: repo, clock: () => now)),
    ));
    await settle(tester);
  }

  /// 捲到 [f] 並確定它在畫面內。
  Future<void> reveal(WidgetTester tester, Finder f, {double delta = 200}) async {
    await tester.scrollUntilVisible(f, delta,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
  }

  Future<void> toTop(WidgetTester tester) async {
    await tester.drag(find.byType(ListView), const Offset(0, 5000));
    await tester.pumpAndSettle();
  }

  String dayTotal(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey('day-total')))
      .textSpan!
      .toPlainText();

  String richOf(WidgetTester tester, Key key) => tester
      .widgetList<RichText>(
          find.descendant(of: find.byKey(key), matching: find.byType(RichText)))
      .map((r) => r.text.toPlainText())
      .join(' ');

  testWidgets('日檢視:總量、分布指標與紀錄列表', (tester) async {
    await pumpPage(tester);

    expect(dayTotal(tester), '今日 750 / 1,500 mL');
    expect(find.text('11/23(一)'), findsOneWidget);
    expect(find.text('時段覆蓋'), findsOneWidget);
    expect(find.text('最集中時段占比'), findsOneWidget);
    expect(find.text('最長未喝水間隔'), findsOneWidget);
    // 15:00 時已開始 5 段(06、08、10、12、14),有喝水的是 06、08、12 三段。
    expect(find.text('3/5'), findsOneWidget);
    expect(find.byKey(const ValueKey('distribution-verdict')), findsOneWidget);
    // 未來不能去;已在今天時「今天」按鈕停用。
    final next = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_right));
    expect(next.onPressed, isNull);
    final todayBtn =
        tester.widget<TextButton>(find.widgetWithText(TextButton, '今天'));
    expect(todayBtn.onPressed, isNull);

    await reveal(tester, find.text('07:30'));
    expect(find.text('待確認'), findsOneWidget);
    expect(find.text('確認是喝水'), findsOneWidget);
    expect(find.text('不是喝水'), findsOneWidget);
    expect(find.text('手動'), findsOneWidget);
    expect(find.text('自動'), findsNWidgets(4));
  });

  testWidgets('切換到週、月,並往前一週', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.text('週'));
    await settle(tester);
    expect(find.text('11/23–11/29'), findsOneWidget);
    expect(find.text('週累積'), findsOneWidget);
    expect(richOf(tester, const ValueKey('period-total')), contains('750 mL'));
    expect(richOf(tester, const ValueKey('period-met')), contains('0/7'));

    await tester.tap(find.byTooltip('上一段'));
    await settle(tester);
    expect(find.text('11/16–11/22'), findsOneWidget);
    expect(richOf(tester, const ValueKey('period-total')), contains('3,100 mL'));
    expect(richOf(tester, const ValueKey('period-met')), contains('2/7'));
    // 回到今天。
    await tester.tap(find.text('今天'));
    await settle(tester);
    expect(find.text('11/23–11/29'), findsOneWidget);

    await tester.tap(find.text('月'));
    await settle(tester);
    expect(find.text('2026 年 11 月'), findsOneWidget);
    expect(find.text('月累積'), findsOneWidget);
    expect(richOf(tester, const ValueKey('period-total')), contains('3,850 mL'));
    expect(richOf(tester, const ValueKey('period-met')), contains('2/30'));

    // 往前到 10 月:沒有資料的空白狀態。
    await tester.tap(find.byTooltip('上一段'));
    await settle(tester);
    expect(find.text('這月沒有喝水紀錄'), findsOneWidget);
  });

  testWidgets('手動新增一筆,總量跟著更新', (tester) async {
    await pumpPage(tester);
    await reveal(tester, find.text('手動新增'));
    await tester.tap(find.text('手動新增'));
    await tester.pumpAndSettle();

    expect(find.text('11/23 15:00'), findsOneWidget); // 預設現在
    await tester.enterText(find.byKey(const ValueKey('event-ml')), '350');
    await tester.tap(find.text('儲存'));
    await settle(tester);

    await toTop(tester);
    expect(dayTotal(tester), '今日 1,100 / 1,500 mL');
    final today = await tester.runAsync(() => repo.eventsOnDay(now));
    final added = today!.where((e) => e.ml == 350).single;
    expect(added.source, IntakeSource.manual);
    expect(added.kind, IntakeKind.drink);
  });

  testWidgets('待確認事件:確認是喝水後計入', (tester) async {
    await pumpPage(tester);
    await reveal(tester, find.text('確認是喝水'));
    await tester.tap(find.text('確認是喝水'));
    await settle(tester);
    expect(find.text('待確認'), findsNothing);
    await toTop(tester);
    expect(dayTotal(tester), '今日 830 / 1,500 mL');
  });

  Future<IntakeEvent> addUncertainRefill(WidgetTester tester) async =>
      (await tester.runAsync(() => repo.addEvent(
            kind: IntakeKind.refill,
            ml: 230,
            startedAt: DateTime(2026, 11, 23, 14, 10),
            source: IntakeSource.appAuto,
            status: IntakeStatus.uncertain,
          )))!;

  testWidgets('待確認的加水:有喝,補記 → 新增手動喝水,加水改為正常且不計入',
      (tester) async {
    final refill = await addUncertainRefill(tester);
    await pumpPage(tester);
    await reveal(tester, find.text('有喝,補記'));
    expect(find.text('這次拿起時有喝的動作,可能也喝了水'), findsOneWidget);
    await tester.tap(find.text('有喝,補記'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('event-ml')), '150');
    await tester.tap(find.text('儲存'));
    await settle(tester);

    await toTop(tester);
    expect(dayTotal(tester), '今日 900 / 1,500 mL');
    final after = await tester.runAsync(() => repo.event(refill.id));
    expect(after!.status, IntakeStatus.ok);
    expect(after.kind, IntakeKind.refill);
    final today = await tester.runAsync(() => repo.eventsOnDay(now));
    final drink = today!.where((e) => e.ml == 150).single;
    expect(drink.source, IntakeSource.manual);
    expect(drink.startedAt, DateTime(2026, 11, 23, 14, 10));
  });

  testWidgets('待確認的加水:只是加水 → 改為正常,飲水量不變', (tester) async {
    final refill = await addUncertainRefill(tester);
    await pumpPage(tester);
    await reveal(tester, find.text('只是加水'));
    await tester.tap(find.text('只是加水'));
    await settle(tester);

    expect(find.text('只是加水'), findsNothing);
    await toTop(tester);
    expect(dayTotal(tester), '今日 750 / 1,500 mL');
    final after = await tester.runAsync(() => repo.event(refill.id));
    expect(after!.status, IntakeStatus.ok);
    expect(after.kind, IntakeKind.refill);
  });

  testWidgets('點紀錄可修改水量與刪除', (tester) async {
    await pumpPage(tester);
    await reveal(tester, find.text('07:30'));
    await tester.tap(find.text('07:30'));
    await tester.pumpAndSettle();
    expect(find.text('修改紀錄'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('event-ml')), '400');
    await tester.tap(find.text('儲存'));
    await settle(tester);

    await tester.tap(find.text('07:30'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('刪除'));
    await settle(tester);
    expect(find.text('07:30'), findsNothing);
    expect(find.textContaining('已刪除'), findsOneWidget);
    await toTop(tester);
    expect(dayTotal(tester), '今日 500 / 1,500 mL');
  });

  testWidgets('手機寬度 360×740 不會溢位(日、週、月與對話框)', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpPage(tester);
    await reveal(tester, find.text('手動新增'));
    await tester.tap(find.text('手動新增'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pumpAndSettle();

    for (final range in ['週', '月']) {
      await tester.drag(find.byType(ListView), const Offset(0, 3000));
      await tester.pumpAndSettle();
      await tester.tap(find.text(range));
      await settle(tester);
      await tester.tap(find.text('每日明細'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -3000));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });
}
