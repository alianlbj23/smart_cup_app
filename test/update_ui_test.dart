import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stut_food_intake_project/data/intake_repository.dart';
import 'package:stut_food_intake_project/main.dart';
import 'package:stut_food_intake_project/services/update_service.dart';
import 'package:stut_food_intake_project/state/cup_connection_manager.dart';
import 'package:stut_food_intake_project/state/update_manager.dart';
import 'package:stut_food_intake_project/ui/theme.dart';
import 'package:stut_food_intake_project/ui/update_panel.dart';

import 'fakes/fake_ble_service.dart';
import 'fakes/fake_update_server.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late FakeUpdateServer server;
  late FakeUpdateInstaller installer;
  late Directory dir;

  UpdateManager manager({
    bool withInstaller = true,
    UpdatePlatform platform = UpdatePlatform.linux,
  }) {
    final m = UpdateManager(
      service: server.service(platform: platform),
      installer: withInstaller ? installer : null,
      downloadDir: () async => dir,
    );
    addTearDown(m.dispose);
    return m;
  }

  setUp(() {
    server = FakeUpdateServer();
    installer = FakeUpdateInstaller();
    dir = Directory.systemTemp.createTempSync('update_ui_test_');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  group('設定頁的「軟體更新」', () {
    Future<void> pumpPanel(WidgetTester tester, UpdateManager m) async {
      // 手機寬度 360 dp,確認不會溢位。
      tester.view.physicalSize = const Size(360 * 3, 900 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: ListView(children: [UpdatePanel(updates: m)]),
        ),
      ));
    }

    testWidgets('顯示目前版本;按「檢查更新」後已是最新', (tester) async {
      server.latest = '1.1.0';
      await pumpPanel(tester, manager());

      expect(find.text('目前版本 1.1.0'), findsOneWidget);
      expect(find.text('下載並安裝'), findsNothing);

      await tester.tap(find.text('檢查更新'));
      await tester.pumpAndSettle();

      expect(server.checks, 1);
      expect(find.text('已是最新版本'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('有新版:顯示版本與說明,按「下載並安裝」交給安裝器', (tester) async {
      server
        ..latest = '1.2.0'
        ..notes = '修正藍牙斷線';
      final m = manager();
      await pumpPanel(tester, m);

      await tester.tap(find.text('檢查更新'));
      await tester.pumpAndSettle();

      expect(find.text('有新版本 1.2.0'), findsOneWidget);
      expect(find.text('修正藍牙斷線'), findsOneWidget);

      // 下載會真的寫檔,要在 runAsync 裡等它做完。
      await tester.runAsync(() async {
        await tester.tap(find.text('下載並安裝'));
        while (m.busy) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pump();

      expect(installer.installed, hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('下載中顯示進度,而且不能再按', (tester) async {
      server.latest = '1.2.0';
      final m = manager();
      await pumpPanel(tester, m);
      await tester.runAsync(m.check);
      await tester.pump();

      // 不在 runAsync 裡:下載的檔案 I/O 不會完成,畫面停在「下載中」。
      await tester.tap(find.text('下載並安裝'));
      await tester.pump();

      expect(find.textContaining('下載中'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('下載並安裝'), findsNothing);
      expect(find.text('檢查更新'), findsNothing);
    });

    testWidgets('更新失敗:顯示原因,可以再按一次', (tester) async {
      server.latest = '1.2.0';
      final m = manager();
      await pumpPanel(tester, m);
      await tester.runAsync(m.check);
      server.downloadStatus = 503;
      await tester.runAsync(m.install);
      await tester.pump();

      expect(find.textContaining('503'), findsOneWidget);
      expect(find.text('下載並安裝'), findsOneWidget);
    });

    testWidgets('檢查失敗:顯示原因', (tester) async {
      server.checkStatus = 500;
      await pumpPanel(tester, manager());

      await tester.tap(find.text('檢查更新'));
      await tester.pumpAndSettle();

      expect(find.textContaining('500'), findsOneWidget);
      expect(find.text('檢查更新'), findsOneWidget);
    });

    testWidgets('不能自行安裝的平台:沒有「下載並安裝」,可以複製下載頁的連結', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      server.latest = '1.2.0';
      final m = manager(withInstaller: false, platform: UpdatePlatform.ios);
      await pumpPanel(tester, m);
      await tester.runAsync(m.check);
      await tester.pump();

      expect(find.text('有新版本 1.2.0'), findsOneWidget);
      expect(find.text('下載並安裝'), findsNothing);

      await tester.tap(find.text('複製下載連結'));
      await tester.pumpAndSettle();

      expect(copied, 'https://github.com/owner/cup/releases/tag/v1.2.0');
      expect(find.text('已複製下載連結'), findsOneWidget);
    });
  });

  group('首頁的新版提示', () {
    late AppDatabase db;
    late IntakeRepository repo;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      repo = IntakeRepository(db);
      await repo.init();
    });
    tearDown(() => db.close());

    Future<void> pumpApp(WidgetTester tester, UpdateManager m) async {
      tester.view.physicalSize = const Size(360 * 3, 900 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final ble = FakeBleService();
      final cups = CupConnectionManager(ble: ble);
      addTearDown(() {
        cups.dispose();
        ble.dispose();
      });
      await tester
          .pumpWidget(SmartCupApp(manager: cups, repo: repo, updates: m));
      await tester.pump();
    }

    testWidgets('沒有新版時不顯示', (tester) async {
      server.latest = '1.1.0';
      final m = manager();
      await tester.runAsync(m.check);
      await pumpApp(tester, m);

      expect(find.textContaining('有新版本'), findsNothing);
    });

    testWidgets('查到新版就出現;按「查看」切到設定頁的「軟體更新」', (tester) async {
      server.latest = '1.1.0';
      final m = manager();
      await pumpApp(tester, m);
      expect(find.textContaining('有新版本'), findsNothing);

      // App 開著的時候背景查到新版。
      server.latest = '1.2.0';
      await tester.runAsync(m.check);
      await tester.pump();

      expect(find.text('有新版本 1.2.0'), findsOneWidget);

      await tester.tap(find.text('查看'));
      await tester.pumpAndSettle();

      expect(find.text('軟體更新'), findsOneWidget);
      expect(find.text('目前版本 1.1.0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
