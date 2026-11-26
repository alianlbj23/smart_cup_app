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

    testWidgets('有新版:只顯示有新版本(不顯示更新說明),按「下載並安裝」交給安裝器', (tester) async {
      server
        ..latest = '1.2.0'
        ..notes = '修正藍牙斷線';
      final m = manager();
      await pumpPanel(tester, m);

      await tester.tap(find.text('檢查更新'));
      await tester.pumpAndSettle();

      expect(find.text('有新版本 1.2.0'), findsOneWidget);
      // 使用者不需要看更新了什麼
      expect(find.text('修正藍牙斷線'), findsNothing);

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

    /// App 開著的時候背景查到 1.2.0。
    Future<void> findUpdate(WidgetTester tester, UpdateManager m) async {
      server.latest = '1.2.0';
      await tester.runAsync(m.check);
      await tester.pumpAndSettle();
    }

    testWidgets('查到新版:自動跳出視窗,只問要不要更新(不顯示版本與說明)', (tester) async {
      server.notes = '修正藍牙斷線';
      final m = manager();
      await pumpApp(tester, m);
      expect(find.byType(AlertDialog), findsNothing);

      await findUpdate(tester, m);

      final dialog = find.byType(AlertDialog);
      expect(dialog, findsOneWidget);
      expect(find.descendant(of: dialog, matching: find.text('有新版本可以更新')),
          findsOneWidget);
      expect(
          find.descendant(
              of: dialog, matching: find.text('更新不會刪除這台裝置上的紀錄。')),
          findsOneWidget);
      // 版本號、更新說明都不顯示
      expect(find.descendant(of: dialog, matching: find.textContaining('1.2.0')),
          findsNothing);
      expect(find.descendant(of: dialog, matching: find.textContaining('1.1.0')),
          findsNothing);
      expect(find.text('修正藍牙斷線'), findsNothing);
      expect(find.text('稍後再說'), findsOneWidget);
      expect(find.text('立即更新'), findsOneWidget);
      // 還沒按之前不會自己下載。
      expect(server.downloads, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('App 啟動前就查到新版:進畫面後一樣跳出視窗', (tester) async {
      server.latest = '1.2.0';
      final m = manager();
      await tester.runAsync(m.check);
      await pumpApp(tester, m);
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('按「稍後再說」:不下載,留下提示列,同一版不再問', (tester) async {
      final m = manager();
      await pumpApp(tester, m);
      await findUpdate(tester, m);

      await tester.tap(find.text('稍後再說'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('有新版本 1.2.0'), findsOneWidget);
      expect(server.downloads, 0);
      expect(installer.installed, isEmpty);

      // 之後定期檢查又查到同一版:不再跳視窗。
      await findUpdate(tester, m);
      expect(find.byType(AlertDialog), findsNothing);

      // 出了更新的版本才會再問一次。
      server.latest = '1.3.0';
      await tester.runAsync(m.check);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('按「立即更新」:切到設定頁並開始下載', (tester) async {
      final m = manager();
      await pumpApp(tester, m);
      await findUpdate(tester, m);

      // 不在 runAsync 裡:下載的檔案 I/O 不會完成,畫面停在「下載中」
      // (下載完交給安裝器的部分由 update_manager_test 與上面的設定頁測試涵蓋)。
      await tester.tap(find.text('立即更新'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(AlertDialog), findsNothing);
      expect(m.phase, UpdatePhase.downloading);
      expect(find.text('軟體更新'), findsOneWidget);
      expect(find.textContaining('下載中'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('不能自行安裝的平台:視窗改成「前往設定」,不下載', (tester) async {
      final m = manager(withInstaller: false, platform: UpdatePlatform.ios);
      await pumpApp(tester, m);
      await findUpdate(tester, m);

      expect(find.text('立即更新'), findsNothing);
      await tester.tap(find.text('前往設定'));
      await tester.pumpAndSettle();

      expect(find.text('複製下載連結'), findsOneWidget);
      expect(server.downloads, 0);
    });

    testWidgets('選了稍後之後:按提示列的「查看」切到設定頁的「軟體更新」', (tester) async {
      server.latest = '1.1.0';
      final m = manager();
      await pumpApp(tester, m);
      expect(find.textContaining('有新版本'), findsNothing);

      await findUpdate(tester, m);
      await tester.tap(find.text('稍後再說'));
      await tester.pumpAndSettle();

      expect(find.text('有新版本 1.2.0'), findsOneWidget);

      await tester.tap(find.text('查看'));
      await tester.pumpAndSettle();

      expect(find.text('軟體更新'), findsOneWidget);
      expect(find.text('目前版本 1.1.0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
