import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stut_food_intake_project/app_info.dart';
import 'package:stut_food_intake_project/data/intake_repository.dart';
import 'package:stut_food_intake_project/services/ble_service.dart';
import 'package:stut_food_intake_project/services/care_api.dart';
import 'package:stut_food_intake_project/services/care_link_store.dart';
import 'package:stut_food_intake_project/services/device_store.dart';
import 'package:stut_food_intake_project/state/care_link_manager.dart';
import 'package:stut_food_intake_project/state/cup_connection_manager.dart';

import 'fakes/fake_ble_service.dart';
import 'fakes/fake_care_server.dart';

const _cup =
    BleDeviceInfo(deviceId: 'AA:BB', deviceName: 'SmartCup-E0CE', rssi: -50);
const _wang = CareResident(id: 12, label: '101-1', nameMasked: '王○明');

// 輪詢靠 Timer:用 testWidgets 內建的假時鐘(t.pump(時間) 會把時間往前推),
// 不需要真的等 5 秒。
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late FakeCareServer server;
  late FakeBleService ble;
  late CupConnectionManager cups;
  late AppDatabase db;
  late IntakeRepository repo;
  late CareLinkStore store;
  late CareLinkManager care;
  late DateTime Function() now;

  /// 測試開始時的(假)時間。
  late DateTime t0;

  /// 等 [f] 完成,回傳結果或錯誤。
  Future<({T? value, Object? error})> wait<T>(Future<T> f) async {
    try {
      return (value: await f, error: null);
    } catch (e) {
      return (value: null, error: e);
    }
  }

  CareLinkManager newManager() => CareLinkManager(
        api: CareApi(client: server.client),
        store: store,
        repo: repo,
        cups: cups,
        clock: now,
        platform: () => 'android',
      );

  /// 準備好 App 的各個元件、執行 [body]、收尾(取消計時器)。
  ///
  /// [pairCup]:先配對並連上水杯。[prefs]:shared_preferences 的初始內容
  /// (有 `remembered_device_id` 時水杯是「配對過但沒連線」)。
  void appTest(
    String name,
    Future<void> Function(WidgetTester t) body, {
    bool pairCup = true,
    DeviceStatus status = const DeviceStatus(batteryPercent: 80),
    Map<String, Object> prefs = const {'care_server_url': FakeCareServer.base},
  }) {
    testWidgets(name, (t) async {
      now = () => t.binding.clock.now();
      SharedPreferences.setMockInitialValues(prefs);
      server = FakeCareServer();
      ble = FakeBleService()
        ..devicesInRange = [_cup]
        ..deviceStatus = status;
      cups = CupConnectionManager(ble: ble, store: DeviceStore());
      db = AppDatabase(NativeDatabase.memory());
      repo = IntakeRepository(db, clock: now);
      await repo.init();
      if (prefs.containsKey('remembered_device_id')) {
        ble.devicesInRange = [];
        unawaited(cups.init());
        await t.pump(const Duration(milliseconds: 1));
      } else if (pairCup) {
        unawaited(cups.connectTo(_cup));
        for (var i = 0; i < 10 && cups.state != CupConnectionState.ready; i++) {
          await t.pump(const Duration(milliseconds: 1));
        }
        expect(cups.state, CupConnectionState.ready);
      }
      store = CareLinkStore();
      care = newManager();
      await care.load();
      expect(care.loaded, isTrue);
      t0 = now();

      await body(t);

      care.dispose();
      cups.dispose();
      ble.dispose();
      await t.pump();
      await db.close();
    });
  }

  int polls() => server.requestsTo('/cup/link/poll/').length;

  Future<void> start([CareResident resident = _wang]) async {
    final r = await wait(care.startPairing(resident));
    expect(r.error, isNull);
    expect(care.pairing?.status, CarePairingStatus.waiting);
  }

  /// 走完整個流程:送出請求 → 照護人員核准([resident] 預設是名單第一位)。
  Future<void> link(WidgetTester t, {Map<String, Object?>? resident}) async {
    await start();
    server.pollScript.add(() => server.approved(resident: resident));
    await t.pump(const Duration(seconds: 5));
    expect(care.isLinked, isTrue);
  }

  Future<List<String>> pending() async => [
        for (final e in await repo.pendingSyncEvents(cupId: 'AA:BB')) e.id,
      ];

  group('啟動', () {
    appTest('預設:尚未連結,伺服器位址為預設值', (t) async {
      expect(care.serverUrl, 'https://foodintakesystem.com');
      expect(care.isLinked, isFalse);
      expect(care.link, isNull);
      expect(care.pairing, isNull);
      expect(care.notice, isNull);
      expect(care.pairedCup, isNull);
      expect(server.requests, isEmpty, reason: '啟動時不會自己連網');
    }, pairCup: false, prefs: const {});

    appTest('重開 App:還原已儲存的連結,並套用 Server 的目標', (t) async {
        await start();
        server.pollScript.add(() => server.approved());
        await t.pump(const Duration(seconds: 5));
        expect(care.isLinked, isTrue);

        final again = newManager();
        again.load();
        await t.pump();
        expect(again.isLinked, isTrue);
        expect(again.link!.resident.display, '101-1 王○明');
        expect(again.link!.token, FakeCareServer.token);
        expect(repo.goalFromServer, isTrue);
        again.dispose();
    });

    appTest('沒有連結但資料庫還記著「目標由 Server 設定」→ 還原成單機行為', (t) async {
        await wait(repo.applyServerGoal(null));
        final again = newManager();
        again.load();
        await t.pump();
        expect(repo.goalFromServer, isFalse);
        expect(repo.goalMl, 1500);
        again.dispose();
    });
  });

  group('伺服器位址與測試連線', () {
    appTest('儲存合法的位址;不合法的丟 FormatException、不儲存', (t) async {
        expect((await wait(care.setServerUrl('ftp://x'))).error, isFormatException);
        expect(care.serverUrl, FakeCareServer.base);

        expect((await wait(care.setServerUrl(' https://other.test/ '))).error, isNull);
        expect(care.serverUrl, 'https://other.test');
        expect((await wait(store.loadServerUrl())).value, 'https://other.test');
    });

    appTest('測試連線:打 GET /api/machine/health/', (t) async {
        final r = await wait(care.testConnection(FakeCareServer.base));
        expect(r.error, isNull);
        expect(r.value, isA<CareHealth>());
        expect(server.requests.single.url.toString(),
            'https://care.test/api/machine/health/');
    });

    appTest('測試連線:位址不合法 → FormatException,不送請求;連不上 → 往上丟', (t) async {
        expect((await wait(care.testConnection('nope'))).error, isFormatException);
        expect(server.requests, isEmpty);

        server.down = true;
        final r = await wait(care.testConnection(FakeCareServer.base));
        expect((r.error as CareApiException).code, 'NETWORK');
    });
  });

  group('選我是誰', () {
    appTest('抓 cup/residents/', (t) async {
        final r = await wait(care.fetchResidents());
        expect(r.value!.map((x) => x.display), ['101-1 王○明', '101-2 李○']);
    });

    appTest('失敗往上丟', (t) async {
        server.onResidents = (_) => FakeCareServer.fail(429, 'THROTTLED');
        final r = await wait(care.fetchResidents());
        expect((r.error as CareApiException).code, 'THROTTLED');
    });
  });

  group('送出綁定請求', () {
    appTest('沒有配對過水杯 → 不能連結,不送請求', (t) async {
        expect(care.pairedCup, isNull);
        final r = await wait(care.startPairing(_wang));
        expect(r.error, isA<CareLinkException>());
        expect((r.error as CareLinkException).message, contains('配對水杯'));
        expect(server.requests, isEmpty);
        expect(care.pairing, isNull);
    }, pairCup: false);

    appTest('body:install_id(UUID v4,固定)、住民、水杯、平台、版本', (t) async {
        await start();
        final body = jsonDecode(server.requestsTo('/cup/link/start/').single.body)
            as Map<String, dynamic>;
        expect(
            body['install_id'],
            matches(RegExp(
                r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
        expect(body, {
          'install_id': body['install_id'],
          'ltc_patient_id': 12,
          'cup_hardware_id': 'AA:BB',
          'cup_name': 'SmartCup-E0CE',
          'platform': 'android',
          'app_version': appVersion,
        });
        expect(care.pairing!.pairingCode, 'K7QM42XP');
        expect(care.pairing!.resident.display, '101-1 王○明');
        expect(care.pairing!.expiresAt, t0.add(const Duration(seconds: 600)));

        // 再送一次:install_id 不變。
        care.cancelPairing();
        await start();
        final second = jsonDecode(server.requestsTo('/cup/link/start/').last.body);
        expect(second['install_id'], body['install_id']);
    });

    appTest('cup_hardware_id:連線中的 Device Status 有 BLE 位址就用它(韌體 0.4.0)', (t) async {
        await start();
        final body = jsonDecode(server.requestsTo('/cup/link/start/').single.body);
        expect(body['cup_hardware_id'], '58:E6:C5:12:E0:CE');
    }, status: const DeviceStatus(
              batteryPercent: 80,
              firmwareVersion: FirmwareVersion(0, 4, 0),
              bleAddress: '58:E6:C5:12:E0:CE'));

    appTest('cup_hardware_id:水杯沒連線時用之前記下的 BLE 位址', (t) async {
        await wait(repo.ensureCup('AA:BB', 'SmartCup-E0CE'));
        await wait(repo.setCupBleAddress('AA:BB', '58:E6:C5:12:E0:CE'));
        await wait(cups.disconnect());
        expect(cups.state, CupConnectionState.idle);
        expect(care.pairedCup?.id, 'AA:BB');

        await start();
        final body = jsonDecode(server.requestsTo('/cup/link/start/').single.body);
        expect(body['cup_hardware_id'], '58:E6:C5:12:E0:CE');
        expect(body['cup_name'], 'SmartCup-E0CE');
    });

    appTest('cup_hardware_id 不符合 [A-Za-z0-9:._-]{1,64} → 不送請求', (t) async {
      expect(care.pairedCup?.id, 'web/id+with=bad chars');
      final r = await wait(care.startPairing(_wang));
      expect(r.error, isA<CareLinkException>());
      expect(server.requestsTo('/cup/link/start/'), isEmpty);
    }, prefs: const {
      'care_server_url': FakeCareServer.base,
      'remembered_device_id': 'web/id+with=bad chars',
      'remembered_device_name': 'SmartCup-E0CE',
    });

    appTest('水杯名稱超過 64 字會截短', (t) async {
      expect((await wait(care.startPairing(_wang))).error, isNull);
      final body = jsonDecode(server.requestsTo('/cup/link/start/').single.body);
      expect((body['cup_name'] as String).length, 64);
      care.cancelPairing();
    }, prefs: {
      'care_server_url': FakeCareServer.base,
      'remembered_device_id': 'AA:BB',
      'remembered_device_name': 'SmartCup-${'x' * 100}',
    });

    appTest('伺服器拒絕(RESIDENT_NOT_FOUND / THROTTLED)→ 往上丟,不進入等待', (t) async {
        for (final (status, code) in [(422, 'RESIDENT_NOT_FOUND'), (429, 'THROTTLED')]) {
          server.onStart = (_) => FakeCareServer.fail(status, code);
          final r = await wait(care.startPairing(_wang));
          expect((r.error as CareApiException).code, code);
          expect(care.pairing, isNull);
        }
        await t.pump(const Duration(minutes: 1));
        expect(polls(), 0);
    });

    appTest('已連結時不能再送綁定請求', (t) async {
        await start();
        server.pollScript.add(() => server.approved());
        await t.pump(const Duration(seconds: 5));
        expect(care.isLinked, isTrue);
        expect((await wait(care.startPairing(_wang))).error, isA<CareLinkException>());
    });
  });

  group('輪詢', () {
    appTest('依 interval 輪詢;pending 就繼續等', (t) async {
        await start();
        expect(polls(), 0);
        await t.pump(const Duration(seconds: 4));
        expect(polls(), 0);
        await t.pump(const Duration(seconds: 1));
        expect(polls(), 1);
        expect(jsonDecode(server.requestsTo('/cup/link/poll/').single.body),
            {'device_code': FakeCareServer.deviceCode});
        await t.pump(const Duration(seconds: 10));
        expect(polls(), 3);
        expect(care.pairing!.status, CarePairingStatus.waiting);
        expect(care.isLinked, isFalse);
    });

    appTest('approved:存 token、住民與目標,停止輪詢,目標套用到資料庫', (t) async {
        var notified = 0;
        care.addListener(() => notified++);
        await start();
        await t.pump(const Duration(seconds: 5));
        server.pollScript.add(() => server.approved());
        await t.pump(const Duration(seconds: 5));

        expect(care.isLinked, isTrue);
        expect(care.pairing!.status, CarePairingStatus.approved);
        final link = care.link!;
        expect(link.token, FakeCareServer.token);
        expect(link.linkId, 7);
        expect(link.resident.display, '101-1 王○明');
        expect((link.dailyGoalMl, link.goalEffectiveFrom), (1500, '2026-11-25'));
        expect(link.linkedAtMs,
            t0.add(const Duration(seconds: 10)).millisecondsSinceEpoch);
        expect(link.serverUrl, FakeCareServer.base);
        expect((link.cupLocalId, link.cupHardwareId, link.cupName),
            ('AA:BB', 'AA:BB', 'SmartCup-E0CE'));
        expect(notified, greaterThan(0));
        // 存進本機。
        expect((await wait(store.loadLink())).value!.token, FakeCareServer.token);
        // drinkers.daily_goal_ml 以 Server 為準。
        expect((repo.goalFromServer, repo.goalMl, repo.dailyGoalMl),
            (true, 1500, 1500));

        final before = polls();
        await t.pump(const Duration(minutes: 5));
        expect(polls(), before, reason: '核准後不再輪詢');
    });

    appTest('approved 但尚未設定目標:目標為 null,不套用預設值', (t) async {
        server.goalMl = null;
        await start();
        server.pollScript.add(() => server.approved());
        await t.pump(const Duration(seconds: 5));

        expect(care.isLinked, isTrue);
        expect(care.link!.dailyGoalMl, isNull);
        expect((repo.goalFromServer, repo.goalMl), (true, null));
    });

    appTest('DENIED:停止輪詢,說明被拒絕,維持未連結', (t) async {
        await start();
        server.pollScript.add(() => FakeCareServer.fail(403, 'DENIED'));
        await t.pump(const Duration(seconds: 5));

        expect(care.pairing!.status, CarePairingStatus.denied);
        expect(care.pairing!.message, contains('拒絕'));
        expect(care.isLinked, isFalse);
        await t.pump(const Duration(minutes: 1));
        expect(polls(), 1);
    });

    appTest('EXPIRED:停止輪詢,說明已過期', (t) async {
        await start();
        server.pollScript.add(() => FakeCareServer.fail(400, 'EXPIRED'));
        await t.pump(const Duration(seconds: 5));

        expect(care.pairing!.status, CarePairingStatus.expired);
        expect(care.pairing!.message, contains('過期'));
        await t.pump(const Duration(minutes: 1));
        expect(polls(), 1);
    });

    appTest('SLOW_DOWN:拉長間隔後繼續輪詢', (t) async {
        await start();
        server.pollScript.add(() => FakeCareServer.fail(429, 'SLOW_DOWN'));
        await t.pump(const Duration(seconds: 5));
        expect(polls(), 1);
        expect(care.pairing!.status, CarePairingStatus.waiting);

        await t.pump(const Duration(seconds: 9));
        expect(polls(), 1, reason: '間隔從 5 秒拉長到 10 秒');
        await t.pump(const Duration(seconds: 1));
        expect(polls(), 2);
        // 之後維持 10 秒。
        await t.pump(const Duration(seconds: 10));
        expect(polls(), 3);
    });

    appTest('暫時連不上(網路、5xx):顯示提示並繼續輪詢,恢復後照樣核准', (t) async {
        await start();
        server.down = true;
        await t.pump(const Duration(seconds: 5));
        expect(care.pairing!.status, CarePairingStatus.waiting);
        expect(care.pairing!.warning, isNotNull);

        server.down = false;
        server.pollScript.add(() => FakeCareServer.fail(503, 'ERROR'));
        await t.pump(const Duration(seconds: 5));
        expect(care.pairing!.status, CarePairingStatus.waiting);

        server.pollScript.add(() => server.approved());
        await t.pump(const Duration(seconds: 5));
        expect(care.isLinked, isTrue);
        expect(care.pairing!.warning, isNull);
    });

    appTest('其他不可重試的錯誤:停止輪詢並顯示訊息', (t) async {
        await start();
        server.pollScript.add(() => http.Response('Not Found', 404));
        await t.pump(const Duration(seconds: 5));

        expect(care.pairing!.status, CarePairingStatus.failed);
        expect(care.pairing!.message, isNotEmpty);
        await t.pump(const Duration(minutes: 1));
        expect(polls(), 1);
    });

    appTest('超過 expires_in 還沒核准:App 自己停止輪詢並標成過期', (t) async {
        server.expiresIn = 20;
        await start();
        expect(care.pairing!.remaining(t0), const Duration(seconds: 20));
        await t.pump(const Duration(seconds: 19));
        expect(polls(), 3);
        expect(care.pairing!.status, CarePairingStatus.waiting);

        await t.pump(const Duration(seconds: 2));
        expect(care.pairing!.status, CarePairingStatus.expired);
        final n = polls();
        await t.pump(const Duration(minutes: 2));
        expect(polls(), n);
    });

    appTest('取消:停止輪詢,回到未連結', (t) async {
        await start();
        await t.pump(const Duration(seconds: 5));
        expect(polls(), 1);

        care.cancelPairing();
        expect(care.pairing, isNull);
        await t.pump(const Duration(minutes: 2));
        expect(polls(), 1);
        expect(care.isLinked, isFalse);
    });

    appTest('dispose(離開畫面):停止輪詢', (t) async {
        await start();
        care.dispose();
        await t.pump(const Duration(minutes: 2));
        expect(polls(), 0);
        care = newManager(); // 讓 appTest 的收尾有東西可以 dispose
    });

    appTest('重新送出:舊的請求不再輪詢', (t) async {
        await start();
        await t.pump(const Duration(seconds: 3));
        await start();
        await t.pump(const Duration(seconds: 4));
        expect(polls(), 0, reason: '舊的計時器(第 5 秒)已取消');
        await t.pump(const Duration(seconds: 1));
        expect(polls(), 1);
    });

    appTest('按取消的同時伺服器回了 approved(只回一次):仍然存下 token', (t) async {
        await start();
        final gate = Completer<http.Response>();
        server.pollScript.add(() => gate.future);
        await t.pump(const Duration(seconds: 5));
        care.cancelPairing();
        gate.complete(server.approved());
        await t.pump();

        expect(care.isLinked, isTrue,
            reason: '網頁端已經顯示綁定,App 丟掉 token 會兩邊不一致');
        expect((await wait(store.loadLink())).value, isNotNull);
    });

    appTest('整個流程的 log 不會出現 token 或 device_code', (t) async {
      final logs = <String>[];
      final original = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) => logs.add(message ?? '');
      try {
        await start();
        server.down = true;
        await t.pump(const Duration(seconds: 5));
        server.down = false;
        server.pollScript.add(() => server.approved());
        await t.pump(const Duration(seconds: 5));
        expect(care.isLinked, isTrue);
        await care.handleTokenExpired('綁定已解除');
      } finally {
        debugPrint = original;
      }
      expect(logs, isNotEmpty);
      final all = logs.join('\n');
      expect(all, isNot(contains(FakeCareServer.token)));
      expect(all, isNot(contains(FakeCareServer.deviceCode)));
    });
  });

  group('已連結', () {
    appTest('解除連結:只清本機的 token,不通知伺服器;目標回到單機行為', (t) async {
        await link(t);
        final before = server.requests.length;
        await wait(care.unlink());

        expect(care.isLinked, isFalse);
        expect(care.pairing, isNull);
        expect(care.notice, isNull);
        expect((await wait(store.loadLink())).value, isNull);
        expect(server.requests.length, before);
        expect(repo.goalFromServer, isFalse);
        expect(repo.goalMl, 1500);
    });

    appTest('TOKEN_EXPIRED:清掉 token、回到尚未連結、說明原因(重開 App 還在)', (t) async {
        await link(t);
        await wait(repo.addEvent(kind: IntakeKind.drink, ml: 100, startedAt: t0));
        await wait(care.handleTokenExpired('綁定已解除,請重新連結'));

        expect(care.isLinked, isFalse);
        expect(care.notice, contains('失效'));
        expect(care.notice, contains('本機紀錄仍保留'));
        expect((await wait(store.loadLink())).value, isNull);
        expect(repo.goalFromServer, isFalse);
        expect((await wait(repo.allEvents())).value, hasLength(1), reason: '本機紀錄保留');

        final again = newManager()..load();
        await t.pump();
        expect(again.isLinked, isFalse);
        expect(again.notice, care.notice);
        again.dispose();

        await wait(care.dismissNotice());
        expect(care.notice, isNull);
        expect((await wait(store.loadNotice())).value, isNull);
    });

    appTest('重新連結成功後,先前的提示消失', (t) async {
        await link(t);
        await wait(care.handleTokenExpired('x'));
        expect(care.notice, isNotNull);
        await link(t);
        expect(care.notice, isNull);
    });

    appTest('Server 回報新的目標 / 住民資訊 → 更新連結與資料庫', (t) async {
        await link(t);
        final token = care.link!.token;
        await care.applyServerInfo(token,
                goal: const CareGoal(dailyGoalMl: 1800, effectiveFrom: '2026-11-26'));
        expect(care.link!.dailyGoalMl, 1800);
        expect(repo.goalMl, 1800);
        expect((await wait(store.loadLink())).value!.dailyGoalMl, 1800);

        await care.applyServerInfo(token,
                goal: const CareGoal(dailyGoalMl: null, effectiveFrom: null),
                resident:
                    const CareResident(id: 12, label: '203-2', nameMasked: '王○明'));
        expect(care.link!.dailyGoalMl, isNull);
        expect(repo.goalMl, isNull, reason: '照護系統取消目標 → 不沿用舊值');
        expect(care.link!.resident.label, '203-2');
    });

    appTest('已經不是目前的 token(回應到的時候已解除連結)→ 忽略', (t) async {
        await link(t);
        final token = care.link!.token;
        await wait(care.unlink());
        await care.applyServerInfo(token,
                goal: const CareGoal(dailyGoalMl: 1800, effectiveFrom: null));
        expect(care.isLinked, isFalse);
        expect(repo.goalFromServer, isFalse);
    });

    appTest('已連結時不能改伺服器位址', (t) async {
        await link(t);
        expect((await wait(care.setServerUrl('https://other.test'))).error,
            isA<CareLinkException>());
        expect(care.serverUrl, FakeCareServer.base);
    });
  });

  group('連結之前的紀錄(Server 會把收到的事件都算在 token 所屬的住民身上)', () {
    Future<IntakeEvent> add({String? cupId = 'AA:BB', int ml = 100}) =>
        repo.addEvent(
          kind: IntakeKind.drink,
          ml: ml,
          startedAt: now(),
          cupId: cupId,
          source: cupId == null ? IntakeSource.manual : IntakeSource.appAuto,
        );

    appTest('第一次連結:連結之前就存在、還沒上傳的紀錄標成不需同步', (t) async {
      final cupEvent = await add();
      await t.pump(const Duration(seconds: 1));
      final manual = await add(cupId: null);
      expect(await pending(), [cupEvent.id, manual.id]);

      await link(t);
      expect(await pending(), isEmpty);
      expect((await repo.event(cupEvent.id))!.syncExcluded, isTrue);
      expect((await repo.event(manual.id))!.syncExcluded, isTrue);

      // 連結之後的新紀錄照常上傳。
      await t.pump(const Duration(seconds: 1));
      final fresh = await add();
      expect(await pending(), [fresh.id]);
      // 舊紀錄之後被修改、刪除也不上傳(不然會算到這位住民頭上)。
      await repo.updateEvent(cupEvent.id, ml: 50);
      await repo.deleteEvent(manual.id);
      expect(await pending(), [fresh.id]);
    });

    appTest('重新連結到同一位住民:未上傳的紀錄照常補傳', (t) async {
      await link(t);
      await t.pump(const Duration(seconds: 1));
      final whileLinked = await add();
      await care.handleTokenExpired('綁定已解除');
      await t.pump(const Duration(seconds: 1));
      final whileUnlinked = await add(cupId: null);

      await link(t);
      expect(care.link!.resident.id, 12);
      expect(await pending(), [whileLinked.id, whileUnlinked.id]);
      expect((await repo.event(whileLinked.id))!.syncExcluded, isNot(true));
    });

    appTest('連結到不同的住民:先前的紀錄(不論有沒有上傳過)都不上傳', (t) async {
      await link(t);
      await t.pump(const Duration(seconds: 1));
      final uploaded = await add();
      await repo.markSynced(
          [(id: uploaded.id, updatedAtMs: uploaded.updatedAtMs)]);
      await t.pump(const Duration(seconds: 1));
      final notUploaded = await add();
      await care.unlink();

      await link(t,
          resident: {'id': 13, 'label': '101-2', 'name_masked': '李○'});
      expect(care.link!.resident.id, 13);
      expect(await pending(), isEmpty);
      expect((await repo.event(notUploaded.id))!.syncExcluded, isTrue);
      // 上一位住民時期上傳過的紀錄,之後被修改也不會送給新的住民。
      await repo.updateEvent(uploaded.id, ml: 999);
      expect(await pending(), isEmpty);

      await t.pump(const Duration(seconds: 1));
      final fresh = await add();
      expect(await pending(), [fresh.id]);
    });

    appTest('換了伺服器、住民 id 剛好相同 → 視為不同的住民', (t) async {
      await link(t);
      await t.pump(const Duration(seconds: 1));
      final old = await add();
      await care.unlink();
      await care.setServerUrl('https://other.test');

      await link(t);
      expect(care.link!.resident.id, 12);
      expect(care.link!.serverUrl, 'https://other.test');
      expect(await pending(), isEmpty);
      expect((await repo.event(old.id))!.syncExcluded, isTrue);
    });
  });

  test('carePlatformName:合約列出的平台名稱', () {
    expect(const ['android', 'ios', 'linux', 'windows', 'macos', 'web'],
        contains(carePlatformName()));
  });
}
