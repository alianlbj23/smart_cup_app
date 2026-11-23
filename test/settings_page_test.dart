import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stut_food_intake_project/data/intake_repository.dart';
import 'package:stut_food_intake_project/services/backup_service.dart';
import 'package:stut_food_intake_project/ui/settings_page.dart';
import 'package:stut_food_intake_project/ui/theme.dart';

/// 假的檔案存取:記下存出去的檔案,匯入時回傳指定內容。
class FakeFileIO implements BackupFileIO {
  String? pickResult;
  final saved = <String, Uint8List>{};

  @override
  Future<String?> pickBackupFile() async => pickResult;

  @override
  Future<String?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    Rect? shareOrigin,
  }) async {
    saved[fileName] = bytes;
    return fileName;
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final now = DateTime(2026, 11, 23, 15);
  late AppDatabase db;
  late IntakeRepository repo;
  late FakeFileIO io;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = IntakeRepository(db, clock: () => now);
    await repo.init();
    io = FakeFileIO();
  });

  tearDown(() => db.close());

  Future<void> pumpPage(WidgetTester tester) async {
    // 手機寬度 360 dp,確認不會溢位。
    tester.view.physicalSize = const Size(360 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SettingsPage(repo: repo, fileIO: io, clock: () => now),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> enterMl(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const ValueKey('ml-input')), text);
    await tester.tap(find.text('確定'));
    await tester.pumpAndSettle();
  }

  testWidgets('修改每日目標,超出範圍會提示', (tester) async {
    await pumpPage(tester);
    expect(find.text('1500 mL'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('goal-tile')));
    await tester.pumpAndSettle();
    await enterMl(tester, '100');
    expect(find.text('請輸入 500–5000 之間的數字'), findsOneWidget);
    expect(repo.dailyGoalMl, 1500);

    await enterMl(tester, '2400');
    expect(repo.dailyGoalMl, 2400);
    expect(find.text('2400 mL'), findsOneWidget);
    expect(find.text('每日目標已改為 2400 mL'), findsOneWidget);
  });

  testWidgets('沒有水杯時顯示提示;連上後可修改容量', (tester) async {
    await pumpPage(tester);
    expect(find.text('連上水杯後會出現在這裡'), findsOneWidget);

    await tester.runAsync(() => repo.ensureCup('AA:BB', 'SmartCup-1'));
    await tester.pumpAndSettle();
    expect(find.text('SmartCup-1'), findsOneWidget);
    expect(find.text('350 mL'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('cup-AA:BB')));
    await tester.pumpAndSettle();
    await enterMl(tester, '3000');
    expect(find.text('請輸入 50–2000 之間的數字'), findsOneWidget);
    await enterMl(tester, '600');

    expect((await tester.runAsync(() => repo.cup('AA:BB')))!.capacityMl, 600);
    expect(find.text('600 mL'), findsOneWidget);
  });

  testWidgets('從備份檔匯入:確認後合併並顯示結果', (tester) async {
    io.pickResult = buildBackupJson(
      dailyGoalMl: 2000,
      exportedAt: now,
      cups: [
        CupRow(
          id: 'CC',
          name: '辦公室水杯',
          capacityMl: 450,
          createdAtMs: 1,
          updatedAtMs: 1,
        ),
      ],
      events: [
        IntakeEvent(
          id: 'e1',
          drinkerId: 'me',
          cupId: 'CC',
          kind: IntakeKind.drink,
          ml: 150,
          startedAtMs: now.millisecondsSinceEpoch,
          tzOffsetMin: now.timeZoneOffset.inMinutes,
          localDay: '2026-11-23',
          source: IntakeSource.appAuto,
          status: IntakeStatus.ok,
          updatedAtMs: 1,
        ),
      ],
    );
    await pumpPage(tester);

    // 取消確認:不匯入。
    await tester.tap(find.text('從備份檔匯入'));
    await tester.pumpAndSettle();
    expect(find.text('從備份檔匯入?'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(repo.dailyGoalMl, 1500);

    await tester.tap(find.text('從備份檔匯入'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('選擇檔案'));
    await tester.pumpAndSettle();

    expect(find.text('匯入完成:新增或更新 1 筆紀錄、1 個水杯,每日目標改為 2000 mL'), findsOneWidget);
    expect(repo.dailyGoalMl, 2000);
    expect(find.text('辦公室水杯'), findsOneWidget);
    expect(await tester.runAsync(() => repo.allEvents()), hasLength(1));

    // 同一個檔案再匯入一次:沒有變更。
    await tester.tap(find.text('從備份檔匯入'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('選擇檔案'));
    await tester.pumpAndSettle();
    expect(find.text('匯入完成:資料已是最新,沒有變更'), findsOneWidget);
  });

  testWidgets('匯入格式錯誤的檔案顯示錯誤訊息', (tester) async {
    io.pickResult = '{"hello": "world"}';
    await pumpPage(tester);
    await tester.tap(find.text('從備份檔匯入'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('選擇檔案'));
    await tester.pumpAndSettle();
    expect(find.text('這不是智慧水杯的備份檔'), findsOneWidget);
  });

  testWidgets('匯出備份檔與 CSV', (tester) async {
    await tester.runAsync(() async {
      await repo.setDailyGoal(1800);
      await repo.addEvent(
        kind: IntakeKind.drink,
        ml: 200,
        startedAt: DateTime(2026, 11, 23, 9),
      );
    });
    await pumpPage(tester);

    await tester.tap(find.text('匯出備份檔'));
    await tester.pumpAndSettle();
    final backup = io.saved['smart_cup_backup_2026-11-23.json']!;
    final data = parseBackupJson(utf8.decode(backup));
    expect(data.dailyGoalMl, 1800);
    expect(data.events, hasLength(1));
    expect(
      find.text('已匯出備份檔:smart_cup_backup_2026-11-23.json'),
      findsOneWidget,
    );

    await tester.tap(find.text('匯出紀錄(CSV)'));
    await tester.pumpAndSettle();
    final csv = utf8.decode(io.saved['smart_cup_紀錄_2026-11-23.csv']!);
    expect(csv, contains('2026-11-23,09:00,喝水,200,手動輸入,正常'));
  });
}
