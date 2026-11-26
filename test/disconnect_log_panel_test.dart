import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stut_food_intake_project/services/device_store.dart';
import 'package:stut_food_intake_project/state/cup_connection_manager.dart';
import 'package:stut_food_intake_project/state/disconnect_log.dart';
import 'package:stut_food_intake_project/ui/disconnect_log_panel.dart';

import 'fakes/fake_ble_service.dart';

DisconnectRecord _rec({
  int? code,
  String? desc,
  bool bg = false,
  bool doze = false,
}) => DisconnectRecord(
  at: DateTime(2026, 11, 26, 21, 5),
  deviceName: 'SmartCup',
  code: code,
  description: desc,
  inBackground: bg,
  wasDozing: doze,
);

void main() {
  group('DisconnectRecord.reasonText', () {
    test('Android 常見代碼翻成中文', () {
      expect(_rec(code: 8).reasonText, contains('逾時'));
      expect(_rec(code: 19).reasonText, contains('水杯'));
      expect(_rec(code: 22).reasonText, contains('手機'));
      expect(_rec(code: 133).reasonText, contains('133'));
    });

    test('其他代碼顯示平台的描述和代碼', () {
      expect(
        _rec(code: 62, desc: 'GATT_CONN_FAIL_ESTABLISH').reasonText,
        allOf(contains('62'), contains('GATT_CONN_FAIL_ESTABLISH')),
      );
    });

    test('沒有代碼 → 原因不明', () {
      expect(_rec().reasonText, contains('不明'));
    });
  });

  testWidgets('連線紀錄區塊:列出每次斷線的時間、原因、App 在背景、水杯休眠', (tester) async {
    SharedPreferences.setMockInitialValues({
      DisconnectLog.prefsKey: jsonEncode([
        _rec(code: 8, desc: 'GATT_CONN_TIMEOUT', bg: true, doze: true).toJson(),
      ]),
    });
    final ble = FakeBleService();
    final manager = CupConnectionManager(ble: ble, store: DeviceStore());
    final log = DisconnectLog(manager: manager, isInBackground: () => false);
    await log.load();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: DisconnectLogPanel(log: log)),
        ),
      ),
    );

    expect(find.text('連線紀錄'), findsOneWidget);
    expect(find.textContaining('11/26 21:05'), findsOneWidget);
    expect(find.textContaining('逾時'), findsOneWidget);
    expect(find.textContaining('App 在背景'), findsOneWidget);
    expect(find.textContaining('水杯休眠中'), findsOneWidget);

    await tester.tap(find.text('清除'));
    await tester.pumpAndSettle();
    expect(find.textContaining('沒有斷線紀錄'), findsOneWidget);

    log.dispose();
    manager.dispose();
    ble.dispose();
  });

  testWidgets('沒有紀錄 → 顯示沒有斷線紀錄', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final ble = FakeBleService();
    final manager = CupConnectionManager(ble: ble, store: DeviceStore());
    final log = DisconnectLog(manager: manager, isInBackground: () => false);
    await log.load();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DisconnectLogPanel(log: log)),
      ),
    );

    expect(find.textContaining('沒有斷線紀錄'), findsOneWidget);
    log.dispose();
    manager.dispose();
    ble.dispose();
  });
}
