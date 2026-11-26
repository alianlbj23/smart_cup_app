import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stut_food_intake_project/data/intake_repository.dart';
import 'package:stut_food_intake_project/services/device_store.dart';
import 'package:stut_food_intake_project/state/cup_connection_manager.dart';
import 'package:stut_food_intake_project/state/disconnect_log.dart';
import 'package:stut_food_intake_project/ui/settings_page.dart';
import 'package:stut_food_intake_project/ui/theme.dart';

import 'fakes/fake_ble_service.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late IntakeRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    repo = IntakeRepository(db);
    await repo.init();
  });

  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester, {DisconnectLog? log}) async {
    tester.view.physicalSize = const Size(360 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SettingsPage(repo: repo, disconnectLog: log),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('有傳入斷線紀錄 → 設定頁有「連線紀錄」區塊', (tester) async {
    final ble = FakeBleService();
    final manager = CupConnectionManager(ble: ble, store: DeviceStore());
    final log = DisconnectLog(manager: manager, isInBackground: () => false);
    await tester.runAsync(log.load);

    await pump(tester, log: log);
    await tester.scrollUntilVisible(find.text('連線紀錄'), 200);

    expect(find.text('連線紀錄'), findsOneWidget);
    log.dispose();
    manager.dispose();
    ble.dispose();
  });

  testWidgets('沒傳入 → 沒有「連線紀錄」區塊', (tester) async {
    await pump(tester);
    expect(find.text('連線紀錄'), findsNothing);
  });
}
