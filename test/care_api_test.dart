import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stut_food_intake_project/data/database.dart';
import 'package:stut_food_intake_project/services/care_api.dart';

final _base = Uri.parse('https://care.test');

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {'content-type': 'application/json'},
    );

http.Response _ok(Object data) => _json({'success': true, 'data': data});

http.Response _fail(int status, String code,
        {String message = '錯誤', bool? retryable}) =>
    _json({
      'success': false,
      'error': {
        'code': code,
        'message': message,
        'retryable': retryable ?? (status >= 500 || const [401, 408, 429].contains(status)),
      },
    }, status);

TypeMatcher<CareApiException> _apiError(String code, {bool? retryable, int? status}) =>
    isA<CareApiException>()
        .having((e) => e.code, 'code', code)
        .having((e) => e.retryable, 'retryable', retryable ?? anything)
        .having((e) => e.statusCode, 'statusCode', status ?? anything);

void main() {
  late List<http.Request> requests;

  CareApi api(FutureOr<http.Response> Function(http.Request r) handler,
          {Duration timeout = const Duration(seconds: 20)}) =>
      CareApi(
        client: MockClient((r) async {
          requests.add(r);
          return handler(r);
        }),
        totalTimeout: timeout,
      );

  setUp(() => requests = []);

  group('伺服器位址驗證', () {
    test('合法的 http / https 網址;去掉結尾的斜線與前後空白', () {
      expect(parseCareServerUrl('https://foodintakesystem.com').toString(),
          'https://foodintakesystem.com');
      expect(parseCareServerUrl('  https://care.test/  ').toString(),
          'https://care.test');
      expect(parseCareServerUrl('http://192.168.1.10:8000').toString(),
          'http://192.168.1.10:8000');
      expect(parseCareServerUrl('https://care.test/prefix/').toString(),
          'https://care.test/prefix');
    });

    test('不合法的網址丟出 FormatException', () {
      for (final bad in [
        '',
        '   ',
        'foodintakesystem.com',
        'ftp://care.test',
        'https://',
        'https:///path',
        'javascript:alert(1)',
        'https://care.test?x=1',
        'https://care.test/#frag',
        'https://user:pw@care.test',
        'https://care .test',
      ]) {
        expect(() => parseCareServerUrl(bad), throwsFormatException,
            reason: '「$bad」應該被拒絕');
      }
    });

    test('預設值本身是合法的', () {
      expect(parseCareServerUrl(defaultCareServerUrl).toString(),
          'https://foodintakesystem.com');
    });
  });

  group('envelope 與錯誤', () {
    test('health:GET /api/machine/health/,回傳伺服器時間', () async {
      final r = await api((_) => _ok(
          {'status': 'ok', 'server_time': 1795600000, 'api_version': 1})).health(_base);
      expect(requests.single.method, 'GET');
      expect(requests.single.url.toString(),
          'https://care.test/api/machine/health/');
      expect(requests.single.headers.containsKey('Authorization'), isFalse);
      expect(r.serverTime, DateTime.fromMillisecondsSinceEpoch(1795600000 * 1000));
    });

    test('Base URL 有路徑前綴時接在後面', () async {
      await api((_) => _ok({'status': 'ok'}))
          .health(Uri.parse('https://care.test/prefix'));
      expect(requests.single.url.toString(),
          'https://care.test/prefix/api/machine/health/');
    });

    test('success = false:code、message、retryable 照伺服器給的', () async {
      await expectLater(
        api((_) => _fail(422, 'RESIDENT_NOT_FOUND', message: '找不到這位住民'))
            .residents(_base),
        throwsA(_apiError('RESIDENT_NOT_FOUND', retryable: false, status: 422)
            .having((e) => e.message, 'message', '找不到這位住民')),
      );
      await expectLater(
        api((_) => _fail(429, 'THROTTLED')).residents(_base),
        throwsA(_apiError('THROTTLED', retryable: true, status: 429)),
      );
      await expectLater(
        api((_) => _fail(503, 'ERROR')).residents(_base),
        throwsA(_apiError('ERROR', retryable: true)),
      );
    });

    test('不是 JSON(例如被登入頁或 502 頁面擋住)→ BAD_RESPONSE,依狀態碼決定可否重試', () async {
      await expectLater(
        api((_) => http.Response('<html>login</html>', 200)).residents(_base),
        throwsA(_apiError('BAD_RESPONSE', retryable: false, status: 200)),
      );
      await expectLater(
        api((_) => http.Response('Bad Gateway', 502)).residents(_base),
        throwsA(_apiError('BAD_RESPONSE', retryable: true, status: 502)),
      );
      await expectLater(
        api((_) => http.Response('Not Found', 404)).residents(_base),
        throwsA(_apiError('BAD_RESPONSE', retryable: false, status: 404)),
      );
      // JSON 但不是 envelope。
      await expectLater(
        api((_) => _json({'detail': 'x'}, 403)).residents(_base),
        throwsA(_apiError('BAD_RESPONSE', retryable: false, status: 403)),
      );
      await expectLater(
        api((_) => _json([1, 2])).residents(_base),
        throwsA(_apiError('BAD_RESPONSE')),
      );
    });

    test('轉址(3xx)不跟著走,回報 BAD_RESPONSE', () async {
      await expectLater(
        api((_) => http.Response('', 301,
            headers: {'location': 'https://elsewhere.test/'})).residents(_base),
        throwsA(_apiError('BAD_RESPONSE', retryable: false, status: 301)),
      );
      expect(requests.single.followRedirects, isFalse);
    });

    test('error 欄位殘缺時仍丟出 CareApiException,retryable 依狀態碼推算', () async {
      await expectLater(
        api((_) => _json({'success': false}, 500)).residents(_base),
        throwsA(_apiError('ERROR', retryable: true, status: 500)),
      );
      await expectLater(
        api((_) => _json({'success': false, 'error': {'code': 7}}, 400))
            .residents(_base),
        throwsA(_apiError('ERROR', retryable: false, status: 400)),
      );
    });

    test('連不上(ClientException)→ NETWORK,可重試', () async {
      await expectLater(
        api((_) => throw http.ClientException('Connection refused'))
            .residents(_base),
        throwsA(_apiError('NETWORK', retryable: true)),
      );
    });

    test('整體逾時 → TIMEOUT,可重試', () async {
      final never = Completer<http.Response>();
      await expectLater(
        api((_) => never.future, timeout: const Duration(milliseconds: 30))
            .residents(_base),
        throwsA(_apiError('TIMEOUT', retryable: true)),
      );
    });

    test('預設逾時:連線 10 秒、整體 20 秒', () {
      expect(CareApi.connectTimeout, const Duration(seconds: 10));
      expect(CareApi(client: MockClient((_) async => _ok({}))).totalTimeout,
          const Duration(seconds: 20));
    });
  });

  group('cup/residents/', () {
    test('解析名單,維持伺服器的順序', () async {
      final list = await api((_) => _ok({
            'residents': [
              {'id': 12, 'label': '101-1', 'name_masked': '王○明'},
              {'id': 3, 'label': '101-2', 'name_masked': ''},
            ],
          })).residents(_base);
      expect(requests.single.url.path, '/api/machine/cup/residents/');
      expect(list.map((r) => (r.id, r.label, r.nameMasked)),
          [(12, '101-1', '王○明'), (3, '101-2', '')]);
      expect(list.first.display, '101-1 王○明');
      expect(list.last.display, '101-2');
    });

    test('欄位型別不對 → BAD_RESPONSE', () async {
      for (final bad in [
        {'residents': 'x'},
        {},
        {
          'residents': [
            {'id': '12', 'label': '101-1', 'name_masked': '王○明'},
          ],
        },
        {
          'residents': [
            {'id': 12, 'label': null, 'name_masked': '王○明'},
          ],
        },
      ]) {
        await expectLater(api((_) => _ok(bad)).residents(_base),
            throwsA(_apiError('BAD_RESPONSE', retryable: false)));
      }
    });
  });

  group('cup/link/start/', () {
    Future<CareLinkStart> start(CareApi a) => a.startLink(
          _base,
          installId: '7b0f8c1e-4a2d-4c6f-9d3a-1e2f3a4b5c6d',
          residentId: 12,
          cupHardwareId: '58:E6:C5:12:E0:CE',
          cupName: 'SmartCup-E0CE',
          platform: 'android',
          appVersion: '1.1.0',
        );

    test('送出合約規定的 body,解析回應', () async {
      final r = await start(api((_) => _ok({
            'device_code': 'a' * 64,
            'pairing_code': 'K7QM42XP',
            'expires_in': 600,
            'interval': 5,
          })));
      final req = requests.single;
      expect(req.method, 'POST');
      expect(req.url.path, '/api/machine/cup/link/start/');
      expect(req.headers['Content-Type'], startsWith('application/json'));
      expect(jsonDecode(utf8.decode(req.bodyBytes)), {
        'install_id': '7b0f8c1e-4a2d-4c6f-9d3a-1e2f3a4b5c6d',
        'ltc_patient_id': 12,
        'cup_hardware_id': '58:E6:C5:12:E0:CE',
        'cup_name': 'SmartCup-E0CE',
        'platform': 'android',
        'app_version': '1.1.0',
      });
      expect(r.deviceCode, 'a' * 64);
      expect(r.pairingCode, 'K7QM42XP');
      expect(r.expiresIn, const Duration(seconds: 600));
      expect(r.interval, const Duration(seconds: 5));
    });

    test('伺服器的錯誤碼照樣往上丟', () async {
      for (final code in ['INVALID_INSTALL_ID', 'INVALID_CUP', 'RESIDENT_NOT_FOUND']) {
        await expectLater(start(api((_) => _fail(422, code))),
            throwsA(_apiError(code, retryable: false)));
      }
      await expectLater(start(api((_) => _fail(429, 'THROTTLED'))),
          throwsA(_apiError('THROTTLED', retryable: true)));
    });

    test('回應欄位不合理(interval ≤ 0、缺 device_code)→ BAD_RESPONSE', () async {
      for (final bad in [
        {'device_code': 'x', 'pairing_code': 'K', 'expires_in': 600, 'interval': 0},
        {'device_code': 'x', 'pairing_code': 'K', 'expires_in': -1, 'interval': 5},
        {'pairing_code': 'K', 'expires_in': 600, 'interval': 5},
        {'device_code': '', 'pairing_code': 'K', 'expires_in': 600, 'interval': 5},
        {'device_code': 'x', 'pairing_code': 5, 'expires_in': 600, 'interval': 5},
      ]) {
        await expectLater(start(api((_) => _ok(bad))),
            throwsA(_apiError('BAD_RESPONSE')));
      }
    });
  });

  group('cup/link/poll/', () {
    test('pending', () async {
      final r = await api((_) => _ok({'status': 'pending'})).pollLink(_base, 'dc');
      expect(r, isA<CareLinkPending>());
      expect(requests.single.url.path, '/api/machine/cup/link/poll/');
      expect(jsonDecode(requests.single.body), {'device_code': 'dc'});
    });

    test('approved:token、住民、目標', () async {
      final r = await api((_) => _ok({
            'status': 'approved',
            'token': 'cup_${'f' * 64}',
            'link_id': 7,
            'resident': {'id': 12, 'label': '101-1', 'name_masked': '王○明'},
            'daily_goal_ml': 1500,
            'goal_effective_from': '2026-11-25',
          })).pollLink(_base, 'dc') as CareLinkApproved;
      expect(r.token, 'cup_${'f' * 64}');
      expect(r.linkId, 7);
      expect(r.resident.display, '101-1 王○明');
      expect(r.goal.dailyGoalMl, 1500);
      expect(r.goal.effectiveFrom, '2026-11-25');
    });

    test('approved 但尚未設定目標:daily_goal_ml 為 null', () async {
      final r = await api((_) => _ok({
            'status': 'approved',
            'token': 'cup_abc',
            'link_id': 7,
            'resident': {'id': 12, 'label': '101-1', 'name_masked': '王○明'},
            'daily_goal_ml': null,
            'goal_effective_from': null,
          })).pollLink(_base, 'dc') as CareLinkApproved;
      expect(r.goal.dailyGoalMl, isNull);
      expect(r.goal.effectiveFrom, isNull);
    });

    test('DENIED / EXPIRED / SLOW_DOWN', () async {
      await expectLater(api((_) => _fail(403, 'DENIED')).pollLink(_base, 'dc'),
          throwsA(_apiError('DENIED', retryable: false, status: 403)));
      await expectLater(api((_) => _fail(400, 'EXPIRED')).pollLink(_base, 'dc'),
          throwsA(_apiError('EXPIRED', retryable: false, status: 400)));
      await expectLater(api((_) => _fail(429, 'SLOW_DOWN')).pollLink(_base, 'dc'),
          throwsA(_apiError('SLOW_DOWN', retryable: true, status: 429)));
    });

    test('未知的 status、token 不合法、目標不是正整數 → BAD_RESPONSE', () async {
      Map<String, Object?> approved(Map<String, Object?> patch) => {
            'status': 'approved',
            'token': 'cup_abc',
            'link_id': 7,
            'resident': {'id': 12, 'label': '101-1', 'name_masked': '王○明'},
            'daily_goal_ml': 1500,
            'goal_effective_from': '2026-11-25',
            ...patch,
          };
      for (final bad in [
        {'status': 'weird'},
        approved({'token': ''}),
        approved({'token': 'cup abc\r\nX: y'}),
        approved({'token': null}),
        approved({'link_id': 'seven'}),
        approved({'resident': null}),
        approved({'daily_goal_ml': 0}),
        approved({'daily_goal_ml': '1500'}),
        approved({'goal_effective_from': 20261125}),
      ]) {
        await expectLater(api((_) => _ok(bad)).pollLink(_base, 'dc'),
            throwsA(_apiError('BAD_RESPONSE')));
      }
    });
  });

  group('需要 token 的端點', () {
    const token = 'cup_secret';

    test('cup/me/:帶 Authorization: Bearer', () async {
      final me = await api((_) => _ok({
            'link_id': 7,
            'resident': {'id': 12, 'label': '101-2', 'name_masked': '王○明'},
            'daily_goal_ml': null,
            'goal_effective_from': null,
            'server_time': 1795600000,
          })).me(_base, token);
      final req = requests.single;
      expect(req.method, 'GET');
      expect(req.url.path, '/api/machine/cup/me/');
      expect(req.headers['Authorization'], 'Bearer cup_secret');
      expect(me.linkId, 7);
      expect(me.resident.label, '101-2');
      expect(me.goal.dailyGoalMl, isNull);
    });

    test('401 TOKEN_EXPIRED', () async {
      final a = api((_) => _fail(401, 'TOKEN_EXPIRED', message: '綁定已解除'));
      await expectLater(
          a.me(_base, token),
          throwsA(_apiError('TOKEN_EXPIRED', status: 401)
              .having((e) => e.isTokenExpired, 'isTokenExpired', isTrue)));
    });

    test('錯誤訊息與 toString 不包含 token', () async {
      Object? caught;
      try {
        await api((_) => throw http.ClientException('boom')).me(_base, token);
      } catch (e) {
        caught = e;
      }
      expect('$caught', isNot(contains(token)));
    });

    test('cup/events/:送出事件、解析結果', () async {
      final results = await api((_) => _ok({
            'results': [
              {'client_event_id': 'e1', 'record_id': 345, 'result': 'created'},
              {'client_event_id': 'e2', 'record_id': 346, 'result': 'unchanged'},
            ],
          })).uploadEvents(_base, token, [
        {'client_event_id': 'e1'},
        {'client_event_id': 'e2'},
      ]);
      final req = requests.single;
      expect(req.method, 'POST');
      expect(req.url.path, '/api/machine/cup/events/');
      expect(req.headers['Authorization'], 'Bearer cup_secret');
      expect(jsonDecode(req.body), {
        'events': [
          {'client_event_id': 'e1'},
          {'client_event_id': 'e2'},
        ],
      });
      expect(results.map((r) => (r.clientEventId, r.recordId, r.result)),
          [('e1', 345, 'created'), ('e2', 346, 'unchanged')]);
    });

    test('cup/events/:一次超過 200 筆 → 不送出,丟 ArgumentError', () async {
      final a = api((_) => _ok({'results': []}));
      await expectLater(
        a.uploadEvents(_base, token,
            [for (var i = 0; i < 201; i++) {'client_event_id': '$i'}]),
        throwsArgumentError,
      );
      expect(requests, isEmpty);
    });

    test('cup/events/:INVALID_EVENT、CLIENT_EVENT_ID_TAKEN 不可重試', () async {
      for (final code in ['INVALID_EVENT', 'CLIENT_EVENT_ID_TAKEN']) {
        await expectLater(
          api((_) => _fail(422, code)).uploadEvents(_base, token, [
            {'client_event_id': 'e1'},
          ]),
          throwsA(_apiError(code, retryable: false, status: 422)),
        );
      }
    });

    test('cup/events/:results 格式不對 → BAD_RESPONSE', () async {
      await expectLater(
        api((_) => _ok({'results': [{'client_event_id': 5}]}))
            .uploadEvents(_base, token, [{'client_event_id': 'e1'}]),
        throwsA(_apiError('BAD_RESPONSE')),
      );
    });

    test('cup/events/ 與 cup/status/:有每日總量時放在 day_totals,沒有就不帶這個欄位', () async {
      final totals = [
        CareDayTotal(day: DateTime(2026, 11, 26), totalMl: 4293, drinkCount: 26),
        CareDayTotal(day: DateTime(2026, 11, 27), totalMl: 362, drinkCount: 4),
      ];
      const wire = [
        {'date': '2026-11-26', 'total_ml': 4293, 'drink_count': 26},
        {'date': '2026-11-27', 'total_ml': 362, 'drink_count': 4},
      ];
      final a = api((_) => _ok({'results': <Object>[]}));
      await a.uploadEvents(_base, token, [], dayTotals: totals);
      await a.uploadEvents(_base, token, []);
      expect(jsonDecode(requests[0].body), {'events': <Object>[], 'day_totals': wire});
      expect(jsonDecode(requests[1].body), {'events': <Object>[]});

      const report = CareStatusReport(
          cupConnected: false,
          cupLastSeenAt: null,
          batteryPct: null,
          firmware: null,
          pendingEvents: 0,
          levelPct: null);
      expect(report.toJson().containsKey('day_totals'), isFalse);
      expect(
          CareStatusReport(
            cupConnected: false,
            cupLastSeenAt: null,
            batteryPct: null,
            firmware: null,
            pendingEvents: 0,
            levelPct: null,
            dayTotals: totals,
          ).toJson()['day_totals'],
          wire);
    });

    test('每日總量的日期一律補零成 YYYY-MM-DD', () {
      expect(CareDayTotal(day: DateTime(2026, 1, 5, 23, 59), totalMl: 0, drinkCount: 0).toJson(),
          {'date': '2026-01-05', 'total_ml': 0, 'drink_count': 0});
    });

    test('每日總量不可以是負數', () {
      expect(() => CareDayTotal(day: DateTime(2026, 11, 27), totalMl: -1, drinkCount: 0),
          throwsArgumentError);
      expect(() => CareDayTotal(day: DateTime(2026, 11, 27), totalMl: 0, drinkCount: -1),
          throwsArgumentError);
    });

    test('cup/status/:送出狀態,回傳 Server 的目標', () async {
      final reply = await api((_) => _ok({
            'server_time': 1795600000,
            'daily_goal_ml': 1800,
            'goal_effective_from': '2026-11-26',
          })).postStatus(
        _base,
        token,
        CareStatusReport(
          cupConnected: true,
          cupLastSeenAt: DateTime.fromMillisecondsSinceEpoch(1795600000999),
          batteryPct: 76,
          firmware: '0.4.0',
          pendingEvents: 0,
          levelPct: 55.5,
        ),
      );
      final req = requests.single;
      expect(req.url.path, '/api/machine/cup/status/');
      expect(req.headers['Authorization'], 'Bearer cup_secret');
      expect(jsonDecode(req.body), {
        'cup_connected': true,
        'cup_last_seen_at': 1795600000,
        'battery_pct': 76,
        'firmware': '0.4.0',
        'pending_events': 0,
        'level_pct': 55.5,
      });
      expect(reply.goal.dailyGoalMl, 1800);
      expect(reply.goal.effectiveFrom, '2026-11-26');
      expect(reply.resident, isNull); // 舊版 Server 不帶 resident:選填
    });

    test('cup/status/:回應帶住民目前的資料(換床位)', () async {
      final reply = await api((_) => _ok({
            'server_time': 1795600000,
            'daily_goal_ml': 1500,
            'goal_effective_from': '2026-11-25',
            'resident': {'id': 12, 'label': '305-2', 'name_masked': '王○明'},
          })).postStatus(
        _base,
        token,
        const CareStatusReport(
          cupConnected: false,
          cupLastSeenAt: null,
          batteryPct: null,
          firmware: null,
          pendingEvents: 0,
          levelPct: null,
        ),
      );
      expect(reply.resident!.id, 12);
      expect(reply.resident!.label, '305-2');
      expect(reply.resident!.nameMasked, '王○明');
    });

    test('cup/status/:resident 格式不對 → BAD_RESPONSE', () async {
      await expectLater(
        api((_) => _ok({
              'server_time': 1795600000,
              'daily_goal_ml': null,
              'goal_effective_from': null,
              'resident': {'id': 'x', 'label': 3},
            })).postStatus(
          _base,
          token,
          const CareStatusReport(
            cupConnected: false,
            cupLastSeenAt: null,
            batteryPct: null,
            firmware: null,
            pendingEvents: 0,
            levelPct: null,
          ),
        ),
        throwsA(_apiError('BAD_RESPONSE')),
      );
    });

    test('cup/status/:未知的值送 null;Server 回 null 目標', () async {
      final reply = await api((_) => _ok({
            'server_time': 1795600000,
            'daily_goal_ml': null,
            'goal_effective_from': null,
          })).postStatus(
        _base,
        token,
        const CareStatusReport(
          cupConnected: false,
          cupLastSeenAt: null,
          batteryPct: null,
          firmware: null,
          pendingEvents: 3,
          levelPct: null,
        ),
      );
      expect(jsonDecode(requests.single.body), {
        'cup_connected': false,
        'cup_last_seen_at': null,
        'battery_pct': null,
        'firmware': null,
        'pending_events': 3,
        'level_pct': null,
      });
      expect(reply.goal.dailyGoalMl, isNull);
    });
  });

  group('事件 → 上傳格式', () {
    IntakeEvent event({
      IntakeSource source = IntakeSource.firmware,
      IntakeStatus status = IntakeStatus.ok,
      IntakeKind kind = IntakeKind.drink,
      bool firmwareFields = true,
    }) =>
        IntakeEvent(
          id: '3f2b6c1a-0d4e-4f5a-8b9c-0a1b2c3d4e5f',
          drinkerId: 'me',
          cupId: 'AA:BB',
          kind: kind,
          ml: 23,
          startedAtMs: 1795600000456,
          endedAtMs: firmwareFields ? null : 1795600008999,
          tzOffsetMin: 480,
          localDay: '2026-11-25',
          beforeMl: 217,
          afterMl: 194,
          source: source,
          status: status,
          updatedAtMs: 1795600009123,
          capacityMl: 350,
          levelBeforePct: firmwareFields ? 62.0 : null,
          levelAfterPct: firmwareFields ? 55.5 : null,
          timeEstimated: firmwareFields ? false : null,
          sawDrinking: firmwareFields ? true : null,
          tooLong: firmwareFields ? false : null,
          fwSeq: firmwareFields ? 12 : null,
          fwKey: firmwareFields ? '12:1795600000:124:111' : null,
        );

    test('韌體事件:欄位名稱、單位與合約一致', () {
      expect(careEventPayload(event()), {
        'client_event_id': '3f2b6c1a-0d4e-4f5a-8b9c-0a1b2c3d4e5f',
        'kind': 'drink',
        'ml': 23,
        'capacity_ml': 350,
        'level_before_pct': 62.0,
        'level_after_pct': 55.5,
        'started_at': 1795600000,
        'ended_at': null,
        'tz_offset_min': 480,
        'source': 'firmware',
        'status': 'ok',
        'time_estimated': false,
        'saw_drinking': true,
        'too_long': false,
        'seq': 12,
        'updated_at': 1795600009123,
      });
    });

    test('App 自動偵測:source = app_auto,沒有的欄位為 null,time_estimated = false', () {
      final p = careEventPayload(event(
          source: IntakeSource.appAuto,
          status: IntakeStatus.uncertain,
          firmwareFields: false));
      expect(p['source'], 'app_auto');
      expect(p['status'], 'uncertain');
      expect(p['ended_at'], 1795600008);
      expect(p['time_estimated'], false);
      expect(p['saw_drinking'], isNull);
      expect(p['too_long'], isNull);
      expect(p['seq'], isNull);
      expect(p['level_before_pct'], isNull);
    });

    test('手動、刪除、加水、倒掉的對應', () {
      expect(careEventPayload(event(source: IntakeSource.manual))['source'], 'manual');
      expect(careEventPayload(event(status: IntakeStatus.deleted))['status'], 'deleted');
      expect(careEventPayload(event(kind: IntakeKind.refill))['kind'], 'refill');
      expect(careEventPayload(event(kind: IntakeKind.discard))['kind'], 'discard');
    });
  });
}
