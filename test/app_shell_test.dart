import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stut_food_intake_project/main.dart';
import 'package:stut_food_intake_project/services/ble_service.dart';
import 'package:stut_food_intake_project/state/care_store.dart';
import 'package:stut_food_intake_project/state/cup_connection_manager.dart';

import 'fakes/fake_ble_service.dart';

const _cup = BleDeviceInfo(deviceId: 'AA:BB', deviceName: 'SmartCup', rssi: -50);

void main() {
  late FakeBleService ble;
  late CupConnectionManager manager;
  late CareStore store;

  Future<void> pumpApp(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    ble = FakeBleService();
    manager = CupConnectionManager(ble: ble);
    store = CareStore();
    addTearDown(() {
      manager.dispose();
      ble.dispose();
    });
    await tester.runAsync(store.load);
    await tester.pumpWidget(SmartCupApp(manager: manager, store: store));
    await tester.pump();
  }

  testWidgets('寬版:總覽顯示指標、住民與水杯配對入口', (tester) async {
    await pumpApp(tester, const Size(1400, 1000));

    expect(find.text('今日飲水照護'), findsOneWidget);
    expect(find.text('全區平均進度'), findsOneWidget);
    expect(find.text('水杯配對'), findsOneWidget);
    expect(find.text('水杯未連線'), findsOneWidget);
    expect(find.text('配對水杯'), findsNWidgets(2), reason: '區塊標題與按鈕');
    expect(tester.takeException(), isNull);
  });

  testWidgets('快速登錄飲水量', (tester) async {
    await pumpApp(tester, const Size(1400, 1000));
    final r = store.selected!;
    final before = r.totalOn(DateTime.now());

    await tester.tap(find.text('+200 mL'));
    await tester.pump();

    expect(r.totalOn(DateTime.now()), before + 200);
  });

  testWidgets('為住民配對水杯 → 連線成功後寫入配對並顯示已連線', (tester) async {
    await pumpApp(tester, const Size(1400, 1000));
    ble.devicesInRange = [_cup];
    final r = store.selected!;

    await tester.tap(find.widgetWithText(FilledButton, '配對水杯'));
    await tester.pumpAndSettle();
    expect(find.text('為「${r.name}」配對水杯'), findsOneWidget);

    await tester.tap(find.text('SmartCup'));
    await tester.pumpAndSettle();

    expect(r.cupId, 'AA:BB');
    expect(manager.state, CupConnectionState.ready);
    expect(find.text('水杯已連線 · ${r.name}'), findsOneWidget);
    expect(find.text('電量 80%'), findsOneWidget);
  });

  testWidgets('窄版(手機):底部導覽可切換各分頁', (tester) async {
    await pumpApp(tester, const Size(390, 844));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);

    for (final (tab, title) in [
      ('住民', '住民資料'),
      ('提醒', '提醒中心'),
      ('統計', '統計分析'),
      ('水杯', '水杯裝置'),
    ]) {
      await tester.tap(find.text(tab));
      await tester.pump();
      expect(find.text(title), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
