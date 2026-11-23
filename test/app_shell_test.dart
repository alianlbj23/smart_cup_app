import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stut_food_intake_project/data/intake_repository.dart';
import 'package:stut_food_intake_project/main.dart';
import 'package:stut_food_intake_project/services/ble_service.dart';
import 'package:stut_food_intake_project/state/cup_connection_manager.dart';
import 'package:stut_food_intake_project/ui/theme.dart';

import 'fakes/fake_ble_service.dart';

const _cup = BleDeviceInfo(deviceId: 'AA:BB', deviceName: 'SmartCup', rssi: -50);

void main() {
  late FakeBleService ble;
  late CupConnectionManager manager;
  late IntakeRepository repo;

  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

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
    // 水杯頁不碰資料庫;統計/設定分頁要打開才會建立,這裡先不 init。
    final db = AppDatabase(NativeDatabase.memory());
    repo = IntakeRepository(db);
    addTearDown(() {
      manager.dispose();
      ble.dispose();
    });
    addTearDown(db.close);
    await tester.pumpWidget(SmartCupApp(manager: manager, repo: repo));
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

  testWidgets('啟動未配對 → 停在水杯頁:未連線與配對入口', (tester) async {
    await pumpApp(tester, const Size(1400, 1000));

    expect(find.text('目前連線:未連線'), findsOneWidget);
    expect(find.text('配對水杯'), findsOneWidget);
    expect(find.text('尚未收到資料'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('底部分頁:切到飲水統計、設定,再回水杯頁', (tester) async {
    await pumpApp(tester, const Size(400, 800));
    await tester.runAsync(repo.init);

    Future<void> settle() async {
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
    }

    await tester.tap(find.text('飲水統計'));
    await settle();
    expect(find.text('週'), findsOneWidget);
    expect(find.text('最長未喝水間隔'), findsOneWidget);

    await tester.tap(find.text('設定'));
    await settle();
    expect(find.text('每日飲水目標'), findsWidgets);

    await tester.tap(find.text('水杯'));
    await tester.pump();
    expect(find.text('配對水杯'), findsOneWidget);
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

  /// 連線後推一組活動中的資料,再推 STATE=休眠(韌體回報已休眠 75 秒,畫面不顯示)。
  Future<void> pushDozing(WidgetTester tester) async {
    ble.pushPacket(const WaterPacket(
        fill25: WaterPacket.fill25Max ~/ 2, level: 5, timestamp: 1));
    ble.pushPacket(const PosePacket(
        tiltDeciDegrees: 20, pose: CupPose.upright, moving: false, timestamp: 1));
    ble.pushPacket(const AttitudePacket(
        pitchDeciDegrees: 10, rollDeciDegrees: -15, timestamp: 1));
    await tester.pumpAndSettle();
    ble.pushPacket(const StatePacket(
        activity: CupActivity.dozing, secondsInState: 75, timestamp: 2));
    await tester.pumpAndSettle();
  }

  testWidgets('休眠:STATE=1 → 休眠橫幅、連線面板與各面板改顯示休眠;STATE=0 → 回復',
      (tester) async {
    await pumpApp(tester, const Size(1400, 1000));
    await pairCup(tester);
    await pushDozing(tester);

    // 休眠橫幅
    expect(find.text('水杯休眠中'), findsOneWidget);
    expect(find.text('藍牙保持連線 · 拿起杯子就會喚醒'), findsOneWidget);
    // 休眠不計時:畫面上不出現「已休眠 X 分」
    expect(find.textContaining('已休眠'), findsNothing);
    expect(find.byIcon(Icons.bedtime), findsWidgets);

    // 連線面板:仍是已連線,只加註休眠中,不出現斷線/重新連線字樣
    expect(find.text('目前連線:已連線 · 休眠中'), findsOneWidget);
    expect(find.byIcon(Icons.bluetooth_connected), findsOneWidget);
    expect(find.text('80%'), findsOneWidget);
    expect(find.textContaining('斷線'), findsNothing);
    expect(find.textContaining('重新連線'), findsNothing);

    // 水位面板:照常顯示(不變灰)
    expect(find.text('50.0000'), findsOneWidget);
    expect(tester.widget<Text>(find.text('50.0000')).style?.color,
        AppColors.teal);
    expect(find.textContaining('休眠中 · 每 30 秒更新 · 更新於'), findsOneWidget);
    expect(find.textContaining('資料過期'), findsNothing);

    // 姿態面板:「休眠中」Chip 取代即時 Chip,不顯示姿態資料過期
    expect(find.widgetWithText(Chip, '休眠中'), findsOneWidget);
    expect(find.widgetWithText(Chip, '直立'), findsNothing);
    expect(find.widgetWithText(Chip, '靜止'), findsNothing);
    expect(find.text('休眠中 · 拿起杯子後恢復即時姿態'), findsOneWidget);
    expect(find.textContaining('姿態資料過期'), findsNothing);
    expect(find.text('傾斜 1.8°'), findsOneWidget);

    // 接收紀錄:只記「進入休眠」,不記時間
    expect(find.text('水杯進入休眠'), findsOneWidget);
    expect(find.textContaining('已接收 3 筆'), findsOneWidget);

    // 休眠中的 keepalive(狀態沒變)不寫進接收紀錄
    ble.pushPacket(const StatePacket(
        activity: CupActivity.dozing, secondsInState: 85, timestamp: 2));
    await tester.pumpAndSettle();
    expect(find.text('水杯進入休眠'), findsOneWidget);
    expect(find.textContaining('已接收 3 筆'), findsOneWidget);

    // 喚醒 → 回到一般畫面
    ble.pushPacket(const StatePacket(
        activity: CupActivity.active, secondsInState: 0, timestamp: 3));
    ble.pushPacket(const PosePacket(
        tiltDeciDegrees: 20, pose: CupPose.upright, moving: true, timestamp: 3));
    ble.pushPacket(const AttitudePacket(
        pitchDeciDegrees: 10, rollDeciDegrees: -15, timestamp: 3));
    await tester.pumpAndSettle();

    expect(find.text('水杯休眠中'), findsNothing);
    expect(find.textContaining('已休眠'), findsNothing);
    expect(find.text('目前連線:已連線'), findsOneWidget);
    expect(find.widgetWithText(Chip, '休眠中'), findsNothing);
    expect(find.widgetWithText(Chip, '直立'), findsOneWidget);
    expect(find.widgetWithText(Chip, '移動中'), findsOneWidget);
    expect(find.textContaining('即時姿態 · 更新於'), findsOneWidget);
    expect(find.text('水杯已喚醒'), findsOneWidget);
    expect(find.textContaining('資料過期'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄版(手機):休眠中版面不溢位', (tester) async {
    await pumpApp(tester, const Size(390, 844));
    // 低電量:電量標示與「已連線 · 休眠中」同一列,字最多。
    ble.deviceStatus = const DeviceStatus(batteryPercent: 15);
    await pairCup(tester);
    await pushDozing(tester);

    expect(find.text('水杯休眠中'), findsOneWidget);
    expect(find.text('目前連線:已連線 · 休眠中'), findsOneWidget);
    expect(find.text('15%'), findsOneWidget);
    expect(find.widgetWithText(Chip, '休眠中'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 寬度只有 320 也不溢位。
    tester.view.physicalSize = const Size(320, 700);
    await tester.pumpAndSettle();
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
