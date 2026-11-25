import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stut_food_intake_project/data/intake_repository.dart';
import 'package:stut_food_intake_project/main.dart' show SmartCupApp;
import 'package:stut_food_intake_project/services/backup_service.dart';
import 'package:stut_food_intake_project/services/ble_service.dart';
import 'package:stut_food_intake_project/services/care_api.dart';
import 'package:stut_food_intake_project/services/care_link_store.dart';
import 'package:stut_food_intake_project/services/device_store.dart';
import 'package:stut_food_intake_project/state/care_link_manager.dart';
import 'package:stut_food_intake_project/state/care_sync.dart';
import 'package:stut_food_intake_project/state/cup_connection_manager.dart';
import 'package:stut_food_intake_project/ui/settings_page.dart';
import 'package:stut_food_intake_project/ui/theme.dart';

import 'fakes/fake_ble_service.dart';
import 'fakes/fake_care_server.dart';

const _cup =
    BleDeviceInfo(deviceId: 'AA:BB', deviceName: 'SmartCup-E0CE', rssi: -50);

class _NoFileIO implements BackupFileIO {
  @override
  Future<String?> pickBackupFile() async => null;

  @override
  Future<String?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    Rect? shareOrigin,
  }) async =>
      null;
}

Map<String, Object> _linkedPrefs({int? goalMl = 1500}) => {
      'care_server_url': FakeCareServer.base,
      'care_last_resident': '${FakeCareServer.base}#12',
      'care_link_v1': jsonEncode({
        'token': FakeCareServer.token,
        'linkId': 7,
        'resident': {'id': 12, 'label': '101-1', 'name_masked': '王○明'},
        'dailyGoalMl': goalMl,
        'goalEffectiveFrom': goalMl == null ? null : '2026-11-25',
        'linkedAtMs': 1,
        'serverUrl': FakeCareServer.base,
        'cupLocalId': 'AA:BB',
        'cupHardwareId': '58:E6:C5:12:E0:CE',
        'cupName': 'SmartCup-E0CE',
      }),
    };

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late FakeCareServer server;
  late FakeBleService ble;
  late CupConnectionManager cups;
  late AppDatabase db;
  late IntakeRepository repo;
  late CareLinkManager care;
  late CareSync sync;

  /// 準備好各個元件、顯示「設定」頁(手機寬度 360 dp)再執行 [body]。
  void uiTest(
    String name,
    Future<void> Function(WidgetTester t) body, {
    bool pairCup = true,
    Map<String, Object> prefs = const {'care_server_url': FakeCareServer.base},
    int? serverGoalMl = 1500,
  }) {
    testWidgets(name, (t) async {
      t.view.physicalSize = const Size(360 * 3, 800 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      DateTime now() => t.binding.clock.now();
      SharedPreferences.setMockInitialValues(prefs);
      server = FakeCareServer()..goalMl = serverGoalMl;
      ble = FakeBleService()..devicesInRange = [_cup];
      cups = CupConnectionManager(ble: ble, store: DeviceStore());
      db = AppDatabase(NativeDatabase.memory());
      repo = IntakeRepository(db, clock: now);
      await repo.init();
      if (pairCup) {
        unawaited(cups.connectTo(_cup));
        for (var i = 0; i < 10 && cups.state != CupConnectionState.ready; i++) {
          await t.pump(const Duration(milliseconds: 1));
        }
        expect(cups.state, CupConnectionState.ready);
      }
      final store = CareLinkStore();
      final api = CareApi(client: server.client);
      care = CareLinkManager(
          api: api,
          store: store,
          repo: repo,
          cups: cups,
          clock: now,
          platform: () => 'android');
      await care.load();
      sync = CareSync(
          api: api, link: care, repo: repo, cups: cups, store: store, clock: now);

      await t.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SettingsPage(
              repo: repo, fileIO: _NoFileIO(), care: care, careSync: sync),
        ),
      ));
      await t.pumpAndSettle();

      await body(t);

      // 收尾:拆掉畫面(停止倒數)、取消所有計時器。
      await t.pumpWidget(const SizedBox());
      sync.dispose();
      care.dispose();
      cups.dispose();
      ble.dispose();
      await t.pump();
      await db.close();
      expect(t.takeException(), isNull);
    });
  }

  Future<void> reveal(WidgetTester t, Finder f) async {
    await t.scrollUntilVisible(f, 150, scrollable: find.byType(Scrollable).first);
    await t.pumpAndSettle();
  }

  Future<void> tapButton(WidgetTester t, String label) async {
    final f = find.text(label);
    await reveal(t, f);
    await t.tap(f);
    await t.pumpAndSettle();
  }

  int polls() => server.requestsTo('/cup/link/poll/').length;

  /// 從設定頁一路走到「等待核准」畫面。
  Future<void> openWaiting(WidgetTester t) async {
    await tapButton(t, '連結照護系統');
    await t.tap(find.text('101-1 王○明'));
    await t.pumpAndSettle();
    await t.tap(find.text('送出'));
    await t.pump();
    await t.pump();
  }

  group('尚未連結', () {
    uiTest('顯示「照護系統」區塊:預設伺服器位址、測試連線、連結照護系統', (t) async {
      await reveal(t, find.text('照護系統'));
      expect(find.text('尚未連結'), findsOneWidget);
      final field = t.widget<TextField>(find.byKey(const ValueKey('care-server-url')));
      expect(field.controller!.text, 'https://foodintakesystem.com');
      await reveal(t, find.text('連結照護系統'));
      expect(find.text('測試連線'), findsOneWidget);
      // 未連結:每日目標照原本的方式(可修改)。
      await reveal(t, find.byKey(const ValueKey('goal-tile')));
      expect(find.text('1500 mL'), findsOneWidget);
    }, prefs: const {});

    uiTest('伺服器位址不合法:顯示錯誤,不送出請求', (t) async {
      await reveal(t, find.byKey(const ValueKey('care-server-url')));
      await t.enterText(find.byKey(const ValueKey('care-server-url')), 'ftp://nope');
      await tapButton(t, '測試連線');
      expect(find.text('伺服器位址要以 https:// 或 http:// 開頭'), findsOneWidget);
      expect(server.requests, isEmpty);

      await tapButton(t, '連結照護系統');
      expect(server.requests, isEmpty);
      expect(find.text('請選擇您是哪一位'), findsNothing);
    });

    uiTest('測試連線:成功顯示「連線成功」並記住位址;失敗顯示原因', (t) async {
      await reveal(t, find.byKey(const ValueKey('care-server-url')));
      await t.enterText(
          find.byKey(const ValueKey('care-server-url')), 'https://other.test/');
      await tapButton(t, '測試連線');
      expect(find.textContaining('連線成功'), findsOneWidget);
      expect(server.requests.single.url.toString(),
          'https://other.test/api/machine/health/');
      expect(care.serverUrl, 'https://other.test');

      server.down = true;
      await tapButton(t, '測試連線');
      expect(find.textContaining('連線成功'), findsNothing);
      expect(find.textContaining('無法連上伺服器'), findsOneWidget);
    });

    uiTest('http 位址:提醒沒有加密', (t) async {
      await reveal(t, find.byKey(const ValueKey('care-server-url')));
      expect(find.textContaining('沒有加密'), findsNothing);
      await t.enterText(
          find.byKey(const ValueKey('care-server-url')), 'http://192.168.1.5:8000');
      await t.pumpAndSettle();
      expect(find.textContaining('沒有加密'), findsOneWidget);
    });

    uiTest('還沒配對水杯:不能連結,提示先配對', (t) async {
      await reveal(t, find.text('連結照護系統'));
      expect(find.textContaining('請先到「水杯」分頁配對水杯'), findsOneWidget);
      final button = t.widget<FilledButton>(
          find.widgetWithText(FilledButton, '連結照護系統'));
      expect(button.onPressed, isNull);
    }, pairCup: false);

    uiTest('連結失效的提示(401)會顯示,按「知道了」後消失', (t) async {
      await reveal(t, find.textContaining('連結已失效'));
      expect(find.textContaining('本機紀錄仍保留'), findsOneWidget);
      await tapButton(t, '知道了');
      expect(find.textContaining('連結已失效'), findsNothing);
      expect(care.notice, isNull);
    }, prefs: const {
      'care_server_url': FakeCareServer.base,
      'care_notice': '照護系統的連結已失效(可能已在網頁端解除綁定),請重新連結。本機紀錄仍保留。',
    });
  });

  group('連結流程', () {
    uiTest('選我是誰 → 送出 → 顯示配對碼與倒數 → 核准 → 已連結', (t) async {
      await tapButton(t, '連結照護系統');
      expect(find.text('請選擇您是哪一位'), findsOneWidget);
      expect(find.text('101-1 王○明'), findsOneWidget);
      expect(find.text('101-2 李○'), findsOneWidget);

      await t.tap(find.text('101-1 王○明'));
      await t.pumpAndSettle();
      expect(find.textContaining('確定是「101-1 王○明」'), findsOneWidget);
      expect(server.requestsTo('/cup/link/start/'), isEmpty, reason: '確認之後才送出');
      await t.tap(find.text('送出'));
      await t.pump();
      await t.pump();

      expect(find.text('K7QM42XP'), findsOneWidget);
      expect(find.textContaining('等待照護人員在網頁按下確定'), findsOneWidget);
      expect(find.textContaining('101-1 王○明'), findsWidgets);
      expect(find.textContaining('10:00'), findsOneWidget);
      await t.pump(const Duration(seconds: 3));
      expect(find.textContaining('9:57'), findsOneWidget, reason: '倒數每秒更新');
      await t.pump(const Duration(seconds: 2));
      expect(polls(), 1);

      server.pollScript.add(() => server.approved());
      await t.pump(const Duration(seconds: 5));
      await t.pump();
      expect(find.text('已連結:101-1 王○明'), findsOneWidget);
      expect(find.text('K7QM42XP'), findsNothing);

      await t.tap(find.text('完成'));
      await t.pumpAndSettle();
      // 回到設定頁:顯示已連結與 Server 的每日目標。
      await reveal(t, find.text('已連結:101-1 王○明'));
      expect(find.textContaining('每日目標:1,500 mL'), findsOneWidget);
      expect(find.text('解除連結'), findsOneWidget);
      expect(find.text('連結照護系統'), findsNothing);
      expect(care.isLinked, isTrue);
    });

    uiTest('照護系統尚未設定目標:顯示「照護系統尚未設定目標」,不顯示 1500', (t) async {
      await openWaiting(t);
      server.pollScript.add(() => server.approved());
      await t.pump(const Duration(seconds: 5));
      await t.pump();
      expect(find.textContaining('照護系統尚未設定目標'), findsOneWidget);
      await t.tap(find.text('完成'));
      await t.pumpAndSettle();

      await reveal(t, find.text('已連結:101-1 王○明'));
      expect(find.text('每日目標:照護系統尚未設定目標'), findsOneWidget);
      await t.drag(find.byType(ListView), const Offset(0, 2000));
      await t.pumpAndSettle();
      final goalTile = find.byKey(const ValueKey('goal-tile'));
      expect(find.descendant(of: goalTile, matching: find.text('照護系統尚未設定目標')),
          findsOneWidget);
      expect(find.textContaining('1500'), findsNothing);
      expect(find.textContaining('1,500'), findsNothing);
    }, serverGoalMl: null);

    uiTest('名單抓不到:顯示原因,可以重試', (t) async {
      server.down = true;
      await tapButton(t, '連結照護系統');
      expect(find.textContaining('無法連上伺服器'), findsOneWidget);
      expect(find.text('101-1 王○明'), findsNothing);

      server.down = false;
      await t.tap(find.text('重試'));
      await t.pumpAndSettle();
      expect(find.text('101-1 王○明'), findsOneWidget);
    });

    uiTest('名單是空的:說明沒有可選的住民', (t) async {
      server.residents = [];
      await tapButton(t, '連結照護系統');
      expect(find.textContaining('目前沒有可以選擇的住民'), findsOneWidget);
    });

    uiTest('送出失敗(次數太多):留在名單並顯示原因', (t) async {
      server.onStart =
          (_) => FakeCareServer.fail(429, 'THROTTLED', message: '嘗試太多次,請稍後再試');
      await openWaiting(t);
      await t.pumpAndSettle();
      expect(find.textContaining('嘗試太多次,請稍後再試'), findsOneWidget);
      expect(find.text('101-1 王○明'), findsOneWidget);
      expect(find.text('K7QM42XP'), findsNothing);
    });

    uiTest('被拒絕:說明原因,可以重新選擇', (t) async {
      await openWaiting(t);
      server.pollScript.add(() => FakeCareServer.fail(403, 'DENIED'));
      await t.pump(const Duration(seconds: 5));
      await t.pump();
      expect(find.textContaining('照護人員拒絕了這次連結請求'), findsOneWidget);
      expect(find.text('K7QM42XP'), findsNothing);
      await t.pump(const Duration(minutes: 1));
      expect(polls(), 1);

      await t.tap(find.text('重新選擇'));
      await t.pumpAndSettle();
      expect(find.text('請選擇您是哪一位'), findsOneWidget);
      expect(find.text('101-2 李○'), findsOneWidget);
    });

    uiTest('過期:說明原因', (t) async {
      await openWaiting(t);
      server.pollScript.add(() => FakeCareServer.fail(400, 'EXPIRED'));
      await t.pump(const Duration(seconds: 5));
      await t.pump();
      expect(find.text('配對碼已過期'), findsOneWidget);
      expect(find.text('配對碼已過期,請重新連結'), findsOneWidget);
      expect(care.isLinked, isFalse);
    });

    uiTest('暫時連不上:顯示提示並繼續等待', (t) async {
      await openWaiting(t);
      server.down = true;
      await t.pump(const Duration(seconds: 5));
      await t.pump();
      expect(find.textContaining('暫時連不上伺服器'), findsOneWidget);
      expect(find.text('K7QM42XP'), findsOneWidget);
    });

    uiTest('按「取消」:停止輪詢並回到設定頁', (t) async {
      await openWaiting(t);
      await t.pump(const Duration(seconds: 5));
      expect(polls(), 1);

      await t.tap(find.text('取消'));
      await t.pumpAndSettle();
      expect(find.text('K7QM42XP'), findsNothing);
      expect(find.text('連結照護系統'), findsOneWidget);
      await t.pump(const Duration(minutes: 2));
      expect(polls(), 1);
      expect(care.pairing, isNull);
    });

    uiTest('離開畫面(返回):停止輪詢', (t) async {
      await openWaiting(t);
      await t.pump(const Duration(seconds: 5));
      expect(polls(), 1);

      await t.pageBack();
      await t.pumpAndSettle();
      await t.pump(const Duration(minutes: 2));
      expect(polls(), 1);
      expect(care.pairing, isNull);
      expect(care.isLinked, isFalse);
    });
  });

  group('已連結', () {
    uiTest('顯示住民、目標、水杯與同步狀態;每日目標不能在 App 修改', (t) async {
      await reveal(t, find.text('已連結:101-1 王○明'));
      expect(find.textContaining('每日目標:1,500 mL'), findsOneWidget);
      expect(find.textContaining('SmartCup-E0CE'), findsWidgets);
      expect(find.byKey(const ValueKey('care-server-url')), findsNothing,
          reason: '已連結時不能改伺服器位址');

      await t.drag(find.byType(ListView), const Offset(0, 2000));
      await t.pumpAndSettle();
      final goalTile = find.byKey(const ValueKey('goal-tile'));
      expect(find.descendant(of: goalTile, matching: find.text('1500 mL')),
          findsOneWidget);
      expect(find.textContaining('由照護系統設定'), findsOneWidget);
      await t.tap(goalTile);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('ml-input')), findsNothing);
    }, prefs: _linkedPrefs());

    uiTest('顯示待上傳筆數與同步錯誤;「立即同步」會上傳', (t) async {
      server.down = true;
      await repo.addEvent(
          kind: IntakeKind.drink, ml: 100, startedAt: t.binding.clock.now());
      await repo.addEvent(
          kind: IntakeKind.drink,
          ml: 120,
          startedAt: t.binding.clock.now().add(const Duration(minutes: 1)));
      await sync.start();
      await t.pump();
      await sync.settled();
      await t.pumpAndSettle();
      await reveal(t, find.textContaining('待上傳 2 筆'));
      expect(find.textContaining('無法連上伺服器'), findsOneWidget);

      server.down = false;
      await tapButton(t, '立即同步');
      await sync.settled();
      await t.pumpAndSettle();
      expect(find.textContaining('已全部上傳'), findsOneWidget);
      expect(server.uploaded, hasLength(2));
    }, prefs: _linkedPrefs());

    uiTest('有紀錄被照護系統拒收:設定頁說明有幾筆沒上傳', (t) async {
      await repo.addEvent(
          kind: IntakeKind.drink, ml: 2500, startedAt: t.binding.clock.now());
      server.onEvents = (_) =>
          FakeCareServer.fail(422, 'INVALID_EVENT', message: '第 1 筆 ml 超出範圍');
      await sync.start();
      await t.pump();
      await sync.settled();
      await t.pumpAndSettle();
      await reveal(t, find.textContaining('1 筆紀錄被照護系統拒收'));
      expect(find.textContaining('紀錄已全部上傳'), findsNothing);
    }, prefs: _linkedPrefs());

    uiTest('連線中的不是已連結的水杯:提醒它的紀錄不會上傳', (t) async {
      await reveal(t, find.text('已連結:101-1 王○明'));
      expect(find.textContaining('紀錄不會上傳'), findsNothing);
      unawaited(cups.connectTo(const BleDeviceInfo(
          deviceId: 'CC:DD', deviceName: 'SmartCup-0001', rssi: -40)));
      ble.devicesInRange = [
        const BleDeviceInfo(deviceId: 'CC:DD', deviceName: 'SmartCup-0001', rssi: -40),
      ];
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 1));
      }
      expect(cups.activeDeviceId, 'CC:DD');
      expect(find.textContaining('紀錄不會上傳'), findsOneWidget);
    }, prefs: _linkedPrefs());

    uiTest('解除連結:先說明網頁端也要解除,確認後只清本機的 token', (t) async {
      await tapButton(t, '解除連結');
      expect(find.textContaining('網頁端也要請照護人員解除綁定'), findsOneWidget);
      expect(find.textContaining('本機紀錄會保留'), findsOneWidget);
      await t.tap(find.text('取消'));
      await t.pumpAndSettle();
      expect(care.isLinked, isTrue);

      final before = server.requests.length;
      await tapButton(t, '解除連結');
      await t.tap(find.widgetWithText(FilledButton, '解除連結'));
      await t.pumpAndSettle();
      expect(care.isLinked, isFalse);
      expect(server.requests.length, before, reason: '不通知伺服器');
      await reveal(t, find.text('連結照護系統'));
      expect(find.text('已連結:101-1 王○明'), findsNothing);
      expect((await SharedPreferences.getInstance()).getString('care_link_v1'), isNull);
    }, prefs: _linkedPrefs());

    uiTest('同步時收到 401:畫面回到尚未連結並說明原因', (t) async {
      server.tokenRevoked = true;
      await sync.start();
      await t.pump();
      await sync.settled();
      await t.pumpAndSettle();
      await reveal(t, find.textContaining('連結已失效'));
      expect(find.textContaining('本機紀錄仍保留'), findsOneWidget);
      await reveal(t, find.text('連結照護系統'));
      expect(find.text('已連結:101-1 王○明'), findsNothing);
    }, prefs: _linkedPrefs());
  });

  testWidgets('沒有傳入 care 時(舊的用法)不顯示「照護系統」區塊', (t) async {
    final db = AppDatabase(NativeDatabase.memory());
    final repo = IntakeRepository(db);
    await repo.init();
    await t.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: SettingsPage(repo: repo, fileIO: _NoFileIO())),
    ));
    await t.pumpAndSettle();
    expect(find.text('照護系統'), findsNothing);
    expect(find.text('每日飲水目標'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await db.close();
  });

  testWidgets('整個 App:「設定」分頁有「照護系統」區塊', (t) async {
    t.view.physicalSize = const Size(400, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    SharedPreferences.setMockInitialValues({});
    final server = FakeCareServer();
    final ble = FakeBleService();
    final cups = CupConnectionManager(ble: ble, store: DeviceStore());
    final db = AppDatabase(NativeDatabase.memory());
    final repo = IntakeRepository(db);
    await repo.init();
    final store = CareLinkStore();
    final api = CareApi(client: server.client);
    final care =
        CareLinkManager(api: api, store: store, repo: repo, cups: cups);
    await care.load();
    final sync =
        CareSync(api: api, link: care, repo: repo, cups: cups, store: store);
    await sync.start();

    await t.pumpWidget(
        SmartCupApp(manager: cups, repo: repo, care: care, careSync: sync));
    await t.tap(find.text('設定'));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('照護系統'), 150,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('尚未連結'), findsOneWidget);
    expect(server.requests, isEmpty, reason: '尚未連結時不連網');

    await t.pumpWidget(const SizedBox());
    sync.dispose();
    care.dispose();
    cups.dispose();
    ble.dispose();
    await t.pump();
    await db.close();
    expect(t.takeException(), isNull);
  });
}
