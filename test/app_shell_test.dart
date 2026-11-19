import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stut_food_intake_project/main.dart';
import 'package:stut_food_intake_project/services/ble_service.dart';
import 'package:stut_food_intake_project/state/cup_connection_manager.dart';
import 'package:stut_food_intake_project/ui/theme.dart';

import 'fakes/fake_ble_service.dart';

const _cup = BleDeviceInfo(deviceId: 'AA:BB', deviceName: 'SmartCup', rssi: -50);

void main() {
  late FakeBleService ble;
  late CupConnectionManager manager;

  /// [remembered] 不為 null 時視為先前已配對,並如 main() 一樣呼叫 init()。
  Future<void> pumpApp(WidgetTester tester, Size size,
      {BleDeviceInfo? remembered, List<BleDeviceInfo> inRange = const []}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({
      if (remembered != null) ...{
        'remembered_device_id': remembered.deviceId,
        'remembered_device_name': remembered.deviceName,
      },
    });
    ble = FakeBleService()..devicesInRange = inRange;
    manager = CupConnectionManager(ble: ble);
    addTearDown(() {
      manager.dispose();
      ble.dispose();
    });
    await tester.pumpWidget(SmartCupApp(manager: manager));
    if (remembered != null) {
      manager.init();
      await tester.pumpAndSettle();
    }
    await tester.pump();
  }

  Future<void> pairCup(WidgetTester tester) async {
    ble.devicesInRange = [_cup];
    await tester.tap(find.text('配對水杯'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SmartCup'));
    await tester.pumpAndSettle();
  }

  testWidgets('啟動未配對 → 只有水杯頁:未連線與配對入口', (tester) async {
    await pumpApp(tester, const Size(1400, 1000));

    expect(find.text('目前連線:未連線'), findsOneWidget);
    expect(find.text('配對水杯'), findsOneWidget);
    expect(find.text('尚未收到資料'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('配對水杯 → 連線成功後顯示電量、水量與接收紀錄', (tester) async {
    await pumpApp(tester, const Size(1400, 1000));
    await pairCup(tester);

    expect(find.byType(AlertDialog), findsNothing);
    expect(manager.state, CupConnectionState.ready);
    expect(find.text('目前連線:已連線'), findsOneWidget);
    expect(find.text('80%'), findsOneWidget);
    expect(find.byIcon(Icons.battery_5_bar), findsOneWidget);
    expect(find.text('配對其他水杯'), findsOneWidget);

    ble.pushPacket(const WaterPacket(
        fill25: WaterPacket.fill25Max, level: 10, timestamp: 1));
    await tester.pumpAndSettle();

    expect(find.text('100.0000'), findsOneWidget);
    expect(
        find.text('水量 100.0000% · 刻度 10 · fill25 ${WaterPacket.fill25Max}'),
        findsOneWidget);
    expect(find.textContaining('已接收 1 筆'), findsOneWidget);
  });

  testWidgets('電量未知(0xFF)→ 顯示「--」與「電量未知」;低電量變紅色', (tester) async {
    await pumpApp(tester, const Size(1400, 1000));
    ble.deviceStatus = const DeviceStatus(batteryPercent: null);
    await pairCup(tester);

    expect(find.text('電量未知'), findsOneWidget);
    expect(find.byIcon(Icons.battery_unknown), findsOneWidget);
    expect(find.textContaining('255%'), findsNothing);

    ble.pushStatus(const DeviceStatus(batteryPercent: 42));
    await tester.pumpAndSettle();
    expect(find.text('42%'), findsOneWidget);
    expect(tester.widget<Text>(find.text('42%')).style?.color, AppColors.teal);

    ble.pushStatus(const DeviceStatus(batteryPercent: 15));
    await tester.pumpAndSettle();
    expect(find.text('15%'), findsOneWidget);
    expect(tester.widget<Text>(find.text('15%')).style?.color, AppColors.red);
    expect(find.byIcon(Icons.battery_alert), findsOneWidget);
  });

  testWidgets('水杯姿態面板:未連線顯示 --,收到資料後顯示傾斜角與姿態標籤',
      (tester) async {
    await pumpApp(tester, const Size(1400, 1000));

    expect(find.text('水杯姿態'), findsOneWidget);
    expect(find.text('傾斜 --'), findsOneWidget);
    expect(find.text('pitch -- · roll --'), findsOneWidget);
    expect(find.text('姿態 --'), findsOneWidget);

    await pairCup(tester);
    ble.pushPacket(const WaterPacket(
        fill25: WaterPacket.fill25Max ~/ 2, level: 5, timestamp: 1));
    ble.pushPacket(const PosePacket(
        tiltDeciDegrees: 300,
        pose: CupPose.drinking,
        moving: true,
        timestamp: 1));
    ble.pushPacket(const AttitudePacket(
        pitchDeciDegrees: 0, rollDeciDegrees: -300, timestamp: 1));
    await tester.pumpAndSettle();

    expect(find.text('傾斜 30.0°'), findsOneWidget);
    expect(find.text('pitch 0.0° · roll -30.0°'), findsOneWidget);
    expect(find.widgetWithText(Chip, '飲用中'), findsOneWidget);
    expect(find.widgetWithText(Chip, '移動中'), findsOneWidget);
    // ATTITUDE 不算進接收紀錄。
    expect(find.textContaining('已接收 2 筆'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('有記憶水杯 → 啟動自動重連,顯示中斷/配對其他/忘記', (tester) async {
    await pumpApp(tester, const Size(1400, 1000),
        remembered: _cup, inRange: [_cup]);

    expect(manager.state, CupConnectionState.ready);
    expect(find.text('中斷連線'), findsOneWidget);
    expect(find.text('配對其他水杯'), findsOneWidget);
    expect(find.text('忘記此水杯'), findsOneWidget);
    expect(find.text('配對水杯'), findsNothing);
    expect(find.text('連線'), findsNothing);
  });

  testWidgets('中斷連線 → 未連線但保留記憶,可再按「連線」重連', (tester) async {
    await pumpApp(tester, const Size(1400, 1000),
        remembered: _cup, inRange: [_cup]);

    await tester.tap(find.text('中斷連線'));
    await tester.pumpAndSettle();

    expect(manager.state, CupConnectionState.idle);
    expect(find.text('目前連線:未連線'), findsOneWidget);
    expect(find.textContaining('SmartCup · AA:BB'), findsOneWidget);
    expect(find.text('中斷連線'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, '連線'));
    await tester.pumpAndSettle();

    expect(manager.state, CupConnectionState.ready);
    expect(find.text('中斷連線'), findsOneWidget);
  });

  testWidgets('記憶水杯不在附近 → 找不到水杯,顯示「重試」', (tester) async {
    await pumpApp(tester, const Size(1400, 1000), remembered: _cup);

    expect(manager.state, CupConnectionState.notFound);
    expect(find.text('目前連線:找不到水杯'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '重試'), findsOneWidget);
    expect(find.text('中斷連線'), findsNothing);

    ble.devicesInRange = [_cup];
    await tester.tap(find.widgetWithText(FilledButton, '重試'));
    await tester.pumpAndSettle();

    expect(manager.state, CupConnectionState.ready);
  });

  testWidgets('配對時找不到水杯 → 提示並可取消,維持未連線', (tester) async {
    await pumpApp(tester, const Size(1400, 1000));

    await tester.tap(find.text('配對水杯'));
    await tester.pumpAndSettle();
    expect(find.textContaining('尚未找到水杯'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(manager.state, CupConnectionState.idle);
    expect(manager.rememberedDevice, isNull);
  });

  testWidgets('連線失敗 → 對話框留著並顯示錯誤', (tester) async {
    await pumpApp(tester, const Size(1400, 1000));
    ble.connectError =
        const BleException(BleErrorCode.connectionFailed, '模擬連線失敗');

    await pairCup(tester);

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(manager.state, isNot(CupConnectionState.ready));
    expect(find.textContaining('模擬連線失敗'), findsWidgets);
  });

  testWidgets('忘記此水杯 → 確認後斷線並回到未配對', (tester) async {
    await pumpApp(tester, const Size(1400, 1000));
    await pairCup(tester);

    await tester.tap(find.text('忘記此水杯'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '忘記'));
    await tester.pumpAndSettle();

    expect(manager.rememberedDevice, isNull);
    expect(ble.isConnected, isFalse);
    expect(find.text('配對水杯'), findsOneWidget);
  });

  testWidgets('窄版(手機):連線後版面不溢位', (tester) async {
    await pumpApp(tester, const Size(390, 844));
    await pairCup(tester);
    ble.pushPacket(const WaterPacket(
        fill25: WaterPacket.fill25Max, level: 10, timestamp: 1));
    ble.pushPacket(const PosePacket(
        tiltDeciDegrees: 1700,
        pose: CupPose.lying,
        moving: false,
        timestamp: 1));
    ble.pushPacket(const AttitudePacket(
        pitchDeciDegrees: 1700, rollDeciDegrees: -1750, timestamp: 1));
    await tester.pumpAndSettle();

    expect(find.text('目前連線:已連線'), findsOneWidget);
    expect(find.text('倒下'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
