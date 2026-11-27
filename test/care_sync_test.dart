import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stut_food_intake_project/data/intake_repository.dart';
import 'package:stut_food_intake_project/services/ble_service.dart';
import 'package:stut_food_intake_project/services/care_api.dart';
import 'package:stut_food_intake_project/services/care_link_store.dart';
import 'package:stut_food_intake_project/services/device_store.dart';
import 'package:stut_food_intake_project/state/care_link_manager.dart';
import 'package:stut_food_intake_project/state/care_sync.dart';
import 'package:stut_food_intake_project/state/cup_connection_manager.dart';

import 'fakes/fake_ble_service.dart';
import 'fakes/fake_care_server.dart';

const _cup =
    BleDeviceInfo(deviceId: 'AA:BB', deviceName: 'SmartCup-E0CE', rssi: -50);
const _otherCup =
    BleDeviceInfo(deviceId: 'CC:DD', deviceName: 'SmartCup-0001', rssi: -40);

/// 已連結的狀態(存在 shared_preferences 裡的樣子)。
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

// 計時器(每 5 分鐘、退避重試)用 testWidgets 內建的假時鐘推進。
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late FakeCareServer server;
  late FakeBleService ble;
  late CupConnectionManager cups;
  late AppDatabase db;
  late IntakeRepository repo;
  late CareLinkStore store;
  late CareLinkManager care;
  late CareSync sync;
  late DateTime Function() now;

  CareSync newSync() => CareSync(
        api: CareApi(client: server.client),
        link: care,
        repo: repo,
        cups: cups,
        store: store,
        clock: now,
      );

  Future<void> connectCup(WidgetTester t, [BleDeviceInfo cup = _cup]) async {
    unawaited(cups.connectTo(cup));
    for (var i = 0; i < 10 && cups.state != CupConnectionState.ready; i++) {
      await t.pump(const Duration(milliseconds: 1));
    }
    expect(cups.state, CupConnectionState.ready);
    await t.pump();
  }

  /// 準備好各個元件(預設:已連結、水杯已連上、同步尚未啟動)再執行 [body]。
  void appTest(
    String name,
    Future<void> Function(WidgetTester t) body, {
    bool linked = true,
    bool cupConnected = true,
    int? goalMl = 1500,
    Map<String, Object> extraPrefs = const {},
    DeviceStatus status = const DeviceStatus(
        batteryPercent: 76, firmwareVersion: FirmwareVersion(0, 4, 0)),
  }) {
    testWidgets(name, (t) async {
      now = () => t.binding.clock.now();
      SharedPreferences.setMockInitialValues({
        if (linked)
          ..._linkedPrefs(goalMl: goalMl)
        else
          'care_server_url': FakeCareServer.base,
        ...extraPrefs,
      });
      server = FakeCareServer()..goalMl = goalMl;
      ble = FakeBleService()
        ..devicesInRange = [_cup, _otherCup]
        ..deviceStatus = status;
      cups = CupConnectionManager(ble: ble, store: DeviceStore());
      db = AppDatabase(NativeDatabase.memory());
      repo = IntakeRepository(db, clock: now);
      await repo.init();
      if (cupConnected) await connectCup(t);
      store = CareLinkStore();
      care = CareLinkManager(
        api: CareApi(client: server.client),
        store: store,
        repo: repo,
        cups: cups,
        clock: now,
        platform: () => 'android',
      );
      await care.load();
      expect(care.isLinked, linked);
      sync = newSync();

      await body(t);

      sync.dispose();
      care.dispose();
      cups.dispose();
      ble.dispose();
      await t.pump();
      await db.close();
    });
  }

  Future<IntakeEvent> add({String? cupId = 'AA:BB', int ml = 100}) => repo.addEvent(
        kind: IntakeKind.drink,
        ml: ml,
        startedAt: now(),
        cupId: cupId,
        source: cupId == null ? IntakeSource.manual : IntakeSource.appAuto,
      );

  Future<int> pendingCount() => repo.pendingSyncCount(cupId: 'AA:BB');

  int uploads() => server.requestsTo('/cup/events/').length;

  /// 啟動同步並等第一輪做完。
  Future<void> startSync(WidgetTester t) async {
    await sync.start();
    await t.pump();
    await sync.settled();
  }

  /// 新事件之後等 debounce 與上傳做完。
  Future<void> afterDebounce(WidgetTester t) async {
    await t.pump(CareSync.defaultDebounce);
    await sync.settled();
  }

  group('上傳', () {
    appTest('App 啟動:把還沒同步的事件上傳,client_event_id = 事件 id、updated_at = updatedAtMs',
        (t) async {
      final a = await add();
      await t.pump(const Duration(seconds: 1));
      final b = await add(cupId: null, ml: 250);
      await startSync(t);

      expect(uploads(), 1);
      final sent = server.uploaded;
      expect(sent.map((e) => e['client_event_id']), [a.id, b.id]);
      expect(sent.map((e) => e['updated_at']), [a.updatedAtMs, b.updatedAtMs]);
      expect(sent[0]['source'], 'app_auto');
      expect(sent[1]['source'], 'manual');
      expect(sent[1]['ml'], 250);
      expect(server.requestsTo('/cup/events/').single.headers['Authorization'],
          'Bearer ${FakeCareServer.token}');
      expect(await pendingCount(), 0);
      expect((await repo.event(a.id))!.syncedAtMs, isNotNull);
      expect(sync.pendingCount, 0);
      expect(sync.lastSyncedAt, isNotNull);
      expect(sync.lastError, isNull);
    });

    appTest('沒有待上傳的事件就不送 cup/events/', (t) async {
      await startSync(t);
      expect(uploads(), 0);
    });

    appTest('每次有新事件就上傳;修改、刪除(軟刪除)也會重新上傳', (t) async {
      await startSync(t);
      final a = await add();
      await afterDebounce(t);
      expect(server.uploaded.map((e) => e['client_event_id']), [a.id]);

      await t.pump(const Duration(seconds: 3));
      await repo.updateEvent(a.id, ml: 180);
      await afterDebounce(t);
      final edited = (await repo.event(a.id))!;
      expect(server.uploaded.last['ml'], 180);
      expect(server.uploaded.last['updated_at'], edited.updatedAtMs);
      expect(edited.updatedAtMs, greaterThan(a.updatedAtMs));

      await t.pump(const Duration(seconds: 3));
      await repo.deleteEvent(a.id);
      await afterDebounce(t);
      expect(server.uploaded.last['status'], 'deleted');
      expect(server.uploaded.last['client_event_id'], a.id);
      expect(uploads(), 3);
      expect(await pendingCount(), 0);
    });

    appTest('一批最多 200 筆:450 筆分三批', (t) async {
      for (var i = 0; i < 450; i++) {
        await add(cupId: null);
      }
      await startSync(t);
      expect(server.uploadedBatches.map((b) => b.length), [200, 200, 50]);
      expect(await pendingCount(), 0);
      expect(server.uploaded.map((e) => e['client_event_id']).toSet(), hasLength(450));
    });

    appTest('尚未連結:完全不連網', (t) async {
      await add();
      await startSync(t);
      await t.pump(const Duration(minutes: 11));
      expect(server.requests, isEmpty);
      expect(sync.pendingCount, 0);
    }, linked: false);

    appTest('不是已連結水杯的紀錄不上傳', (t) async {
      await add(cupId: 'CC:DD');
      final mine = await add();
      await startSync(t);
      expect(server.uploaded.map((e) => e['client_event_id']), [mine.id]);
    });

    appTest('每 5 分鐘試一次(就算沒有被新事件觸發)', (t) async {
      await startSync(t);
      await add();
      sync.debugCancelDebounce(); // 模擬「新事件」那一次沒有觸發
      await t.pump(const Duration(minutes: 4, seconds: 59));
      await sync.settled();
      expect(uploads(), 0);

      await t.pump(const Duration(seconds: 1));
      await sync.settled();
      expect(uploads(), 1);
      expect(await pendingCount(), 0);
    });

    appTest('連結核准的當下開始上傳之後的新紀錄', (t) async {
      await startSync(t);
      final before = await add(); // 連結之前的紀錄
      await care.startPairing(
          const CareResident(id: 12, label: '101-1', nameMasked: '王○明'));
      server.pollScript.add(() => server.approved());
      await t.pump(const Duration(seconds: 5));
      await sync.settled();
      expect(care.isLinked, isTrue);
      expect(server.statuses, hasLength(1), reason: '連結成功後馬上回報狀態');

      final after = await add();
      await afterDebounce(t);
      expect(server.uploaded.map((e) => e['client_event_id']), [after.id]);
      expect((await repo.event(before.id))!.syncExcluded, isTrue);
    }, linked: false);
  });

  group('上傳失敗', () {
    appTest('可重試的錯誤(503 RETRY_LATER):保留在佇列,退避後重試成功', (t) async {
      final a = await add();
      server.onEvents = (_) => FakeCareServer.fail(503, 'RETRY_LATER');
      await startSync(t);
      expect(uploads(), 1);
      expect(await pendingCount(), 1);
      expect(sync.pendingCount, 1);
      expect(sync.lastError, isNotNull);
      expect((await repo.event(a.id))!.syncError, isNull);

      server.onEvents = null;
      await t.pump(const Duration(seconds: 29));
      await sync.settled();
      expect(uploads(), 1, reason: '第一次退避 30 秒');
      await t.pump(const Duration(seconds: 1));
      await sync.settled();
      expect(uploads(), 2);
      expect(await pendingCount(), 0);
      expect(sync.lastError, isNull);
    });

    appTest('連續失敗:退避時間加倍(30、60、120 秒…),最多 5 分鐘', (t) async {
      await add();
      server.down = true;
      await startSync(t);
      expect(uploads(), 1);

      await t.pump(const Duration(seconds: 30));
      await sync.settled();
      expect(uploads(), 2);
      await t.pump(const Duration(seconds: 59));
      await sync.settled();
      expect(uploads(), 2);
      await t.pump(const Duration(seconds: 1));
      await sync.settled();
      expect(uploads(), 3);
      await t.pump(const Duration(seconds: 120));
      await sync.settled();
      expect(uploads(), 4);
      expect(CareSync.retryDelay(1), const Duration(seconds: 30));
      expect(CareSync.retryDelay(4), const Duration(seconds: 240));
      expect(CareSync.retryDelay(5), const Duration(minutes: 5));
      expect(CareSync.retryDelay(50), const Duration(minutes: 5));
    });

    appTest('逾時、網路斷線都算可重試', (t) async {
      await add();
      server.down = true;
      await startSync(t);
      expect(await pendingCount(), 1);
      server.down = false;
      await t.pump(const Duration(seconds: 30));
      await sync.settled();
      expect(await pendingCount(), 0);
    });

    appTest('不可重試、也不是某一筆紀錄的問題(404):這一輪放棄並記下錯誤,紀錄留在佇列,'
        '不排退避重試,下一個 5 分鐘再試', (t) async {
      final a = await add();
      server.onEvents = (_) => http.Response('Not Found', 404);
      await startSync(t);
      expect(uploads(), 1);
      expect(await pendingCount(), 1);
      expect((await repo.event(a.id))!.syncError, isNull);
      expect(sync.lastError, isNotNull);

      await t.pump(const Duration(minutes: 4));
      await sync.settled();
      expect(uploads(), 1, reason: '沒有退避重試');

      server.onEvents = null;
      await t.pump(const Duration(minutes: 1));
      await sync.settled();
      expect(uploads(), 2);
      expect(await pendingCount(), 0);
    });

    for (final code in ['INVALID_EVENT', 'CLIENT_EVENT_ID_TAKEN']) {
      appTest('$code:找出修不了的那一筆、移出佇列並記下原因,不卡住其他紀錄', (t) async {
        final events = <IntakeEvent>[];
        for (var i = 0; i < 7; i++) {
          events.add(await add(cupId: null, ml: 100 + i));
          await t.pump(const Duration(milliseconds: 10));
        }
        final bad = events[4];
        // 整批只要包含那一筆就 422。
        server.onEvents = (batch) =>
            batch.any((e) => e['client_event_id'] == bad.id)
                ? FakeCareServer.fail(422, code, message: '第 5 筆 ml 不合規定')
                : FakeCareServer.ok(FakeCareServer.resultsFor(batch));
        await startSync(t);

        expect(await pendingCount(), 0);
        final rejected = (await repo.event(bad.id))!;
        expect(rejected.syncedAtMs, isNull);
        expect(rejected.syncError, contains(code));
        expect(rejected.syncError, contains('第 5 筆 ml 不合規定'));
        expect(sync.rejectedCount, 1, reason: '設定頁要能告訴使用者有紀錄沒上傳');
        for (final e in events.where((e) => e.id != bad.id)) {
          expect((await repo.event(e.id))!.syncedAtMs, isNotNull);
        }
        expect(server.uploaded.map((e) => e['client_event_id']).toSet(),
            {for (final e in events.where((e) => e.id != bad.id)) e.id});

        // 之後的新紀錄照常上傳,被拒收的那筆不再重送。
        final before = uploads();
        final later = await add(cupId: null);
        await afterDebounce(t);
        expect(uploads(), before + 1);
        expect(server.uploadedBatches.last.single['client_event_id'], later.id);

        // 使用者修好那一筆(例如改水量)→ 重新上傳。
        server.onEvents = null;
        await t.pump(const Duration(seconds: 1));
        await repo.updateEvent(bad.id, ml: 50);
        await afterDebounce(t);
        expect((await repo.event(bad.id))!.syncedAtMs, isNotNull);
        expect((await repo.event(bad.id))!.syncError, isNull);
        expect(sync.rejectedCount, 0);
      });
    }

    appTest('TOO_MANY_EVENTS:拆成小批再送,不會把紀錄標成拒收', (t) async {
      for (var i = 0; i < 6; i++) {
        await add(cupId: null);
      }
      server.onEvents = (batch) => batch.length > 2
          ? FakeCareServer.fail(422, 'TOO_MANY_EVENTS')
          : FakeCareServer.ok(FakeCareServer.resultsFor(batch));
      await startSync(t);
      expect(await pendingCount(), 0);
      expect(server.uploaded, hasLength(6));
      for (final e in await repo.allEvents()) {
        expect(e.syncError, isNull);
      }
    });

    appTest('找壞紀錄的途中遇到可重試的錯誤:不會誤把紀錄標成拒收', (t) async {
      for (var i = 0; i < 4; i++) {
        await add(cupId: null);
      }
      var calls = 0;
      server.onEvents = (batch) => ++calls == 1
          ? FakeCareServer.fail(422, 'INVALID_EVENT')
          : FakeCareServer.fail(503, 'ERROR');
      await startSync(t);
      expect(await pendingCount(), 4);
      for (final e in await repo.allEvents()) {
        expect(e.syncError, isNull);
      }
    });

    appTest('伺服器的結果少了某幾筆:那幾筆留在佇列,不會無窮迴圈', (t) async {
      final a = await add(cupId: null);
      await t.pump(const Duration(milliseconds: 10));
      final b = await add(cupId: null);
      server.onEvents = (batch) => FakeCareServer.ok({
            'results': [
              for (final e in batch)
                if (e['client_event_id'] != a.id)
                  {'client_event_id': e['client_event_id'], 'record_id': 1, 'result': 'created'},
            ],
          });
      await startSync(t);
      expect((await repo.event(b.id))!.syncedAtMs, isNotNull);
      expect((await repo.event(a.id))!.syncedAtMs, isNull);
      expect(uploads(), 2, reason: '第二輪只剩 a,仍然沒有結果 → 停止');
      expect(sync.lastError, isNotNull);
    });

    appTest('上傳途中紀錄又被修改:舊版本不算已同步,新版本再上傳一次', (t) async {
      final a = await add(cupId: null);
      final gate = Completer<void>();
      var first = true;
      server.onEvents = (batch) async {
        if (first) {
          first = false;
          await gate.future;
        }
        return FakeCareServer.ok(FakeCareServer.resultsFor(batch));
      };
      unawaited(sync.start());
      await t.pump(const Duration(milliseconds: 1));
      expect(uploads(), 1);
      await repo.updateEvent(a.id, ml: 321);
      gate.complete();
      await t.pump();
      await afterDebounce(t);

      expect(server.uploaded.map((e) => e['ml']), [100, 321]);
      expect(await pendingCount(), 0);
    });

    appTest('401 TOKEN_EXPIRED:清掉 token、回到尚未連結並說明原因,本機紀錄保留,不再上傳',
        (t) async {
      final a = await add();
      server.tokenRevoked = true;
      await startSync(t);

      expect(care.isLinked, isFalse);
      expect(care.notice, contains('失效'));
      expect(await store.loadLink(), isNull);
      expect(await repo.event(a.id), isNotNull);
      expect((await repo.event(a.id))!.syncedAtMs, isNull);
      expect(repo.goalFromServer, isFalse);

      final n = server.requests.length;
      await add(cupId: null);
      await t.pump(const Duration(minutes: 11));
      await sync.settled();
      expect(server.requests.length, n, reason: '沒有 token 就不再連網');
    });
  });

  group('狀態回報', () {
    appTest('App 啟動時回報:水杯連線、電量、韌體、水位、待上傳筆數', (t) async {
      ble.pushPacket(WaterPacket(
          fill25: (0.555 * WaterPacket.fill25Max).round(), level: 5, timestamp: 1));
      await t.pump();
      await add(cupId: 'CC:DD'); // 不算在待上傳
      final startedAt = now();
      await startSync(t);

      expect(server.statuses, hasLength(1));
      final s = server.statuses.single;
      expect(s['cup_connected'], isTrue);
      expect(s['cup_last_seen_at'], startedAt.millisecondsSinceEpoch ~/ 1000);
      expect(s['battery_pct'], 76);
      expect(s['firmware'], '0.4.0');
      expect(s['level_pct'], 55.5);
      expect(s['pending_events'], 0);
      expect(server.requestsTo('/cup/status/').single.headers['Authorization'],
          'Bearer ${FakeCareServer.token}');
    });

    appTest('啟動時先回報狀態(含待上傳筆數)再上傳', (t) async {
      await add();
      await add(cupId: null);
      await startSync(t);
      expect(server.statuses.first['pending_events'], 2);
      final paths = [for (final r in server.requests) r.url.path.split('/cup/').last];
      expect(paths.indexOf('status/'), lessThan(paths.indexOf('events/')));
    });

    appTest('每 5 分鐘回報一次', (t) async {
      await startSync(t);
      expect(server.statuses, hasLength(1));
      await t.pump(const Duration(minutes: 4, seconds: 59));
      await sync.settled();
      expect(server.statuses, hasLength(1));
      await t.pump(const Duration(seconds: 1));
      await sync.settled();
      expect(server.statuses, hasLength(2));
      await t.pump(const Duration(minutes: 10));
      await sync.settled();
      expect(server.statuses, hasLength(4));
    });

    appTest('水杯斷線、連上時立刻回報;斷線後 cup_last_seen_at 停在斷線的時間', (t) async {
      await startSync(t);
      await t.pump(const Duration(seconds: 90));
      final droppedAt = now();
      await cups.disconnect();
      await t.pump();
      await sync.settled();

      expect(server.statuses, hasLength(2));
      final off = server.statuses.last;
      expect(off['cup_connected'], isFalse);
      expect(off['cup_last_seen_at'], droppedAt.millisecondsSinceEpoch ~/ 1000);
      expect(off['battery_pct'], isNull);
      expect(off['level_pct'], isNull);
      expect(off['firmware'], '0.4.0', reason: '最後知道的版本');

      await t.pump(const Duration(minutes: 5));
      await sync.settled();
      expect(server.statuses.last['cup_last_seen_at'],
          droppedAt.millisecondsSinceEpoch ~/ 1000);

      await connectCup(t);
      await sync.settled();
      final on = server.statuses.last;
      expect(on['cup_connected'], isTrue);
      expect(on['cup_last_seen_at'], greaterThan(off['cup_last_seen_at'] as int));
      expect(on['battery_pct'], 76);
    });

    appTest('連上的不是已連結的水杯:回報 cup_connected = false', (t) async {
      await connectCup(t, _otherCup);
      await startSync(t);
      final s = server.statuses.single;
      expect(s['cup_connected'], isFalse);
      expect(s['battery_pct'], isNull);
      expect(s['cup_last_seen_at'], isNull);
    }, cupConnected: false);

    appTest('從沒看過水杯:cup_last_seen_at、firmware、電量、水位都是 null', (t) async {
      await startSync(t);
      // day_totals 另有一組測試(「每日總量」)。
      expect(Map.of(server.statuses.single)..remove('day_totals'), {
        'cup_connected': false,
        'cup_last_seen_at': null,
        'battery_pct': null,
        'firmware': null,
        'pending_events': 0,
        'level_pct': null,
      });
    }, cupConnected: false);

    appTest('重開 App 而水杯不在:用上次記下的 cup_last_seen_at 與韌體版本', (t) async {
      await startSync(t);
      expect(server.statuses.single, containsPair('cup_last_seen_at', 1795600000));
      expect(server.statuses.single, containsPair('firmware', '0.3.0'));
    }, cupConnected: false, extraPrefs: const {
      'care_cup_last_seen_at_ms': 1795600000999,
      'care_cup_firmware': '0.3.0',
    });

    appTest('電量未知(0xFF)→ battery_pct = null', (t) async {
      await startSync(t);
      expect(server.statuses.single['battery_pct'], isNull);
      expect(server.statuses.single['cup_connected'], isTrue);
    }, status: const DeviceStatus(batteryPercent: null));

    appTest('回報失敗(可重試):不影響之後的回報與上傳', (t) async {
      server.onStatus = (_) => FakeCareServer.fail(503, 'ERROR');
      final a = await add();
      await startSync(t);
      expect(care.isLinked, isTrue);
      expect((await repo.event(a.id))!.syncedAtMs, isNotNull);

      server.onStatus = null;
      await t.pump(const Duration(minutes: 5));
      await sync.settled();
      expect(server.statuses, hasLength(2));
    });

    appTest('401 TOKEN_EXPIRED:回到尚未連結並說明原因', (t) async {
      server.tokenRevoked = true;
      await startSync(t);
      expect(care.isLinked, isFalse);
      expect(care.notice, contains('失效'));
      expect(care.notice, contains('本機紀錄仍保留'));
    });
  });

  group('每日總量(網站的喝水量以 App 為準)', () {
    List<Map<String, dynamic>> totalsOf(Map<String, dynamic> body) => [
          for (final d in body['day_totals'] as List)
            (d as Map).cast<String, dynamic>(),
        ];
    Map<String, dynamic> eventsBody(int index) =>
        (jsonDecode(server.requestsTo('/cup/events/')[index].body) as Map)
            .cast<String, dynamic>();
    String dayBefore(int days) {
      final today = startOfDay(now());
      return dayKey(DateTime(today.year, today.month, today.day - days));
    }

    appTest('上傳紀錄時帶「今天＋前 6 天」的總量,數字和統計頁相同', (t) async {
      await add(ml: 100);
      await add(cupId: null, ml: 250);
      await t.pump(const Duration(seconds: 1)); // 同一個水杯同一毫秒只能有一筆
      await repo.addEvent(
          kind: IntakeKind.refill,
          ml: 300,
          startedAt: now(),
          cupId: 'AA:BB',
          source: IntakeSource.appAuto);
      await startSync(t);

      final totals = totalsOf(eventsBody(0));
      expect([for (final d in totals) d['date']],
          [for (var i = 6; i >= 0; i--) dayBefore(i)]);
      expect(totals.last,
          {'date': dayBefore(0), 'total_ml': 350, 'drink_count': 2});
      expect(totals.first,
          {'date': dayBefore(6), 'total_ml': 0, 'drink_count': 0});
      final today = startOfDay(now());
      expect(totals.last['total_ml'], (await repo.dailyTotals(today, today))[today]);
    });

    appTest('狀態回報也帶每日總量', (t) async {
      await add(ml: 180);
      await startSync(t);
      expect(totalsOf(server.statuses.first), hasLength(7));
      expect(totalsOf(server.statuses.first).last,
          {'date': dayBefore(0), 'total_ml': 180, 'drink_count': 1});
    });

    appTest('連結之前的紀錄(不上傳、統計頁也不算)不算進總量', (t) async {
      await add(ml: 500);
      await repo.excludeAllFromSync();
      await t.pump(const Duration(seconds: 1));
      await add(ml: 120);
      await startSync(t);
      expect(totalsOf(server.statuses.first).last,
          {'date': dayBefore(0), 'total_ml': 120, 'drink_count': 1});
    });

    appTest('總量變了但沒有紀錄要上傳(別的水杯的紀錄):補送一次狀態回報,之後不重複送',
        (t) async {
      await startSync(t);
      final before = server.statuses.length;
      await add(cupId: 'CC:DD', ml: 80); // 統計會算,但不會上傳
      await afterDebounce(t);
      expect(uploads(), 0);
      expect(server.statuses, hasLength(before + 1));
      expect(totalsOf(server.statuses.last).last['total_ml'], 80);

      await t.pump(CareSync.defaultDebounce * 3);
      await sync.settled();
      expect(server.statuses, hasLength(before + 1));
    });

    appTest('有紀錄上傳時總量跟著那一批送出,不另外多送狀態回報', (t) async {
      await startSync(t);
      final before = server.statuses.length;
      await add(ml: 60);
      await afterDebounce(t);
      expect(uploads(), 1);
      expect(totalsOf(eventsBody(0)).last['total_ml'], 60);
      expect(server.statuses, hasLength(before));
    });

    appTest('Server 不接受 day_totals(422 INVALID_DAY_TOTALS):不帶總量重送,'
        '紀錄照常上傳,並讓使用者知道', (t) async {
      server.rejectDayTotals = true;
      final a = await add();
      await startSync(t);

      expect(await pendingCount(), 0);
      expect((await repo.event(a.id))!.syncError, isNull);
      expect(server.uploaded.map((e) => e['client_event_id']), [a.id]);
      // 第一次回報帶總量被拒收,重送的那一次與之後的請求都不帶。
      expect(server.statuses.first.containsKey('day_totals'), isTrue);
      expect(server.statuses.last.containsKey('day_totals'), isFalse);
      expect(eventsBody(uploads() - 1).containsKey('day_totals'), isFalse);
      expect(sync.dayTotalsRejected, isTrue);
      expect(sync.lastError, contains('每日總量'));

      // 同樣的內容不再重送;內容變了才再試一次(仍被拒收:帶總量一次、不帶總量一次)。
      final statuses = server.statuses.length;
      await t.pump(const Duration(minutes: 5));
      await sync.settled();
      expect(server.statuses.last.containsKey('day_totals'), isFalse);
      final afterHeartbeat = server.statuses.length;
      expect(afterHeartbeat, statuses + 1, reason: '同樣的總量不再試');

      await add(cupId: 'CC:DD', ml: 80);
      await afterDebounce(t);
      expect(server.statuses, hasLength(afterHeartbeat + 2));
      expect(server.statuses[afterHeartbeat].containsKey('day_totals'), isTrue);
      expect(server.statuses.last.containsKey('day_totals'), isFalse);
      await t.pump(CareSync.defaultDebounce * 3);
      await sync.settled();
      expect(server.statuses, hasLength(afterHeartbeat + 2), reason: '不會一直重試');
    });

    appTest('被拒收之後 Server 恢復接受:總量變動時重新送出,錯誤訊息消失', (t) async {
      server.rejectDayTotals = true;
      await startSync(t);
      expect(sync.dayTotalsRejected, isTrue);

      server.rejectDayTotals = false;
      await add(ml: 90);
      await afterDebounce(t);
      expect(totalsOf(eventsBody(uploads() - 1)).last['total_ml'], 90);
      expect(sync.dayTotalsRejected, isFalse);
      expect(sync.lastError, isNull);
    });

    appTest('某一天超過合約的上限(100000 mL):那一天不送,其他天照送,不會整批被拒收', (t) async {
      await repo.addEvent(
          kind: IntakeKind.drink,
          ml: 100001,
          startedAt: now(),
          cupId: 'CC:DD',
          source: IntakeSource.appAuto);
      await startSync(t);
      final totals = totalsOf(server.statuses.first);
      expect([for (final d in totals) d['date']],
          [for (var i = 6; i >= 1; i--) dayBefore(i)]);
      expect(sync.dayTotalsRejected, isFalse);
    });

    appTest('連不上 Server 時沒送出去的總量,恢復後會補送', (t) async {
      await startSync(t);
      server.onStatus = (_) => http.Response('Bad Gateway', 502);
      await add(cupId: 'CC:DD', ml: 80);
      await afterDebounce(t);
      final failed = server.statuses.length;

      server.onStatus = null;
      await t.pump(const Duration(minutes: 5));
      await sync.settled();
      expect(server.statuses.length, greaterThan(failed));
      expect(totalsOf(server.statuses.last).last['total_ml'], 80);
    });
  });

  group('住民資料跟著 Server', () {
    appTest('App 一直開著:住民換床位後,下一次狀態回報就更新顯示', (t) async {
      await startSync(t);
      expect(care.link!.resident.label, '101-1');

      server.residents[0] = {'id': 12, 'label': '305-2', 'name_masked': '王○明'};
      await t.pump(const Duration(minutes: 5));
      await sync.settled();
      expect(care.link!.resident.label, '305-2');
      expect((await store.loadLink())!.resident.label, '305-2');
    });

    appTest('舊版 Server 的狀態回報沒有 resident:住民資料不變', (t) async {
      server.statusIncludesResident = false;
      await startSync(t);
      await t.pump(const Duration(minutes: 5));
      await sync.settled();
      expect(care.link!.resident.label, '101-1');
    });
  });

  group('每日目標以 Server 為準', () {
    appTest('狀態回報的回應帶新的目標 → 更新 drinkers.daily_goal_ml', (t) async {
      expect(repo.goalMl, 1500);
      server.goalMl = 1800;
      server.goalFrom = '2026-11-26';
      await startSync(t);

      expect(repo.goalMl, 1800);
      expect(repo.dailyGoalMl, 1800);
      expect(care.link!.dailyGoalMl, 1800);
      expect(care.link!.goalEffectiveFrom, '2026-11-26');
      expect((await store.loadLink())!.dailyGoalMl, 1800);
    });

    appTest('Server 回 null(照護系統取消或尚未設定目標)→ 沒有目標,不套用預設值', (t) async {
      server.goalMl = null;
      await startSync(t);
      expect(repo.goalFromServer, isTrue);
      expect(repo.goalMl, isNull);
      expect(care.link!.dailyGoalMl, isNull);
    });

    appTest('連結時就沒有目標:一直是 null,之後 Server 設定了才有', (t) async {
      expect(repo.goalMl, isNull);
      await startSync(t);
      expect(repo.goalMl, isNull);

      server.goalMl = 2000;
      await t.pump(const Duration(minutes: 5));
      await sync.settled();
      expect(repo.goalMl, 2000);
    }, goalMl: null);

    appTest('App 啟動時用 cup/me/ 更新住民資訊(換床位)與目標', (t) async {
      server.residents = [
        {'id': 12, 'label': '203-2', 'name_masked': '王○明'},
      ];
      await startSync(t);
      expect(server.requestsTo('/cup/me/'), hasLength(1));
      expect(care.link!.resident.display, '203-2 王○明');
      expect((await store.loadLink())!.resident.label, '203-2');
    });

    appTest('cup/me/ 回 401 → 回到尚未連結,不再送其他請求', (t) async {
      server.tokenRevoked = true;
      await add();
      await startSync(t);
      expect(care.isLinked, isFalse);
      expect(server.requestsTo('/cup/status/'), isEmpty);
      expect(server.requestsTo('/cup/events/'), isEmpty);
    });
  });

  appTest('dispose 之後不再連網', (t) async {
    await startSync(t);
    final n = server.requests.length;
    sync.dispose();
    await add();
    await t.pump(const Duration(minutes: 11));
    expect(server.requests.length, n);
    sync = newSync(); // 讓 appTest 的收尾有東西可以 dispose
  });
}
